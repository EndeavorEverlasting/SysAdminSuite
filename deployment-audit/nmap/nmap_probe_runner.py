#!/usr/bin/env python3
"""
Async, progress-aware Nmap probe runner for Cybernet / Neuron audits.

This module is intentionally more than a thin wrapper around nmap. It owns the
live-probe lifecycle:

- queue-based async target execution
- async JSONL event logging
- atomic artifact writes so partial files are less likely
- resumable status tracking
- incremental analysis after every completed target
- Ctrl+C / premature-stop recovery

Default concurrency is 1 to avoid aggressive scanning. The implementation is
async so the logger, status writer, subprocess handling, and analysis refreshes
stay responsive and structured even when concurrency remains conservative.

No third-party Python packages are required.
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import json
import re
import shutil
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from cybernet_target_audit import build_inventory, match_nmap, parse_nmap_xml, read_xlsx_rows

STATUS_FIELDS = [
    "target",
    "index",
    "total",
    "percent",
    "status",
    "started_at",
    "ended_at",
    "duration_seconds",
    "return_code",
    "xml_path",
    "stdout_log",
    "stderr_log",
    "source_column",
    "first_source_row",
    "source_rows",
    "error",
]

PROBE_ARTIFACTS_TO_CLEAR = [
    "probe_status.csv",
    "probe_progress.jsonl",
    "nmap_probe_matches.csv",
    "probe_run_summary.json",
]

PROBE_DIRS_TO_CLEAR = [
    "probe_xml",
    "probe_logs",
]

TERMINAL_STATUSES = {"completed", "failed", "skipped", "resumed_completed"}


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def safe_name(value: str, max_len: int = 80) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    value = value.strip("._-") or "target"
    return value[:max_len]


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def atomic_write_json(path: Path, payload: object) -> None:
    atomic_write_text(path, json.dumps(payload, indent=2, ensure_ascii=False))


def atomic_write_csv(path: Path, rows: Sequence[Dict[str, str]], fields: Sequence[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(fields), extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    tmp.replace(path)


def clear_probe_artifacts(out_dir: Path) -> None:
    """Delete only live-probe artifacts. Keep workbook analysis outputs."""
    for name in PROBE_ARTIFACTS_TO_CLEAR:
        path = out_dir / name
        if path.exists():
            path.unlink()
    for name in PROBE_DIRS_TO_CLEAR:
        path = out_dir / name
        if path.exists():
            shutil.rmtree(path)


def read_target_rows(out_dir: Path) -> List[Dict[str, str]]:
    csv_path = out_dir / "nmap_targets.csv"
    txt_path = out_dir / "targets.txt"
    if csv_path.exists():
        with csv_path.open("r", newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
            return [row for row in rows if row.get("target", "").strip()]
    if txt_path.exists():
        targets = [line.strip() for line in txt_path.read_text(encoding="utf-8").splitlines() if line.strip()]
        return [{"target": target, "source_column": "", "first_source_row": "", "source_rows": ""} for target in targets]
    raise FileNotFoundError(f"No targets found in {out_dir}. Run cybernet_target_audit.py first.")


def read_status(path: Path) -> Dict[str, Dict[str, str]]:
    if not path.exists():
        return {}
    with path.open("r", newline="", encoding="utf-8") as f:
        return {row["target"]: row for row in csv.DictReader(f) if row.get("target")}


def parse_all_xml(xml_dir: Path) -> List[Dict[str, str]]:
    hosts: List[Dict[str, str]] = []
    if not xml_dir.exists():
        return hosts
    for xml_file in sorted(xml_dir.glob("*.xml")):
        try:
            parsed = parse_nmap_xml(xml_file)
        except Exception as exc:
            hosts.append({
                "nmap_status": "parse_error",
                "nmap_reason": str(exc),
                "nmap_ipv4": "",
                "nmap_mac": "",
                "nmap_vendor": "",
                "nmap_hostname": xml_file.stem,
                "source_xml": str(xml_file),
            })
            continue
        for host in parsed:
            host["source_xml"] = str(xml_file)
            hosts.append(host)
    return hosts


@dataclass(frozen=True)
class ProbePaths:
    out_dir: Path
    xml_dir: Path
    log_dir: Path
    status_csv: Path
    progress_jsonl: Path
    matches_csv: Path
    summary_json: Path

    @classmethod
    def from_out_dir(cls, out_dir: Path) -> "ProbePaths":
        return cls(
            out_dir=out_dir,
            xml_dir=out_dir / "probe_xml",
            log_dir=out_dir / "probe_logs",
            status_csv=out_dir / "probe_status.csv",
            progress_jsonl=out_dir / "probe_progress.jsonl",
            matches_csv=out_dir / "nmap_probe_matches.csv",
            summary_json=out_dir / "probe_run_summary.json",
        )

    def ensure(self) -> None:
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.xml_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class ProbeTarget:
    index: int
    total: int
    target: str
    source_column: str = ""
    first_source_row: str = ""
    source_rows: str = ""

    @property
    def percent(self) -> float:
        return (self.index / self.total) * 100 if self.total else 0.0

    @property
    def base_name(self) -> str:
        return f"{self.index:04d}-{safe_name(self.target)}"


@dataclass(frozen=True)
class ProbeResult:
    status: str
    return_code: int
    error: str
    duration_seconds: float


class AsyncEventLogger:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.queue: asyncio.Queue[Optional[Dict[str, object]]] = asyncio.Queue()
        self.task: Optional[asyncio.Task[None]] = None

    async def start(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.task = asyncio.create_task(self._run())

    async def _run(self) -> None:
        with self.path.open("a", encoding="utf-8") as f:
            while True:
                event = await self.queue.get()
                try:
                    if event is None:
                        return
                    event.setdefault("time", now_iso())
                    f.write(json.dumps(event, ensure_ascii=False) + "\n")
                    f.flush()
                finally:
                    self.queue.task_done()

    async def emit(self, event: Dict[str, object]) -> None:
        await self.queue.put(event)

    async def stop(self) -> None:
        await self.queue.put(None)
        await self.queue.join()
        if self.task:
            await self.task


class ArtifactStore:
    """Serialized, atomic writes for status and analysis artifacts."""

    def __init__(self, paths: ProbePaths, inventory: Sequence[Dict[str, str]], source_xlsx: Path, sheet: str) -> None:
        self.paths = paths
        self.inventory = inventory
        self.source_xlsx = source_xlsx
        self.sheet = sheet
        self.statuses: Dict[str, Dict[str, str]] = read_status(paths.status_csv)
        self.status_lock = asyncio.Lock()
        self.analysis_lock = asyncio.Lock()

    async def update_status(self, target: str, updates: Dict[str, str]) -> None:
        async with self.status_lock:
            current = self.statuses.get(target, {})
            current.update(updates)
            self.statuses[target] = current
            rows = sorted(self.statuses.values(), key=lambda r: int(r.get("index") or 0))
            await asyncio.to_thread(atomic_write_csv, self.paths.status_csv, rows, STATUS_FIELDS)

    async def refresh_analysis(self) -> Dict[str, object]:
        async with self.analysis_lock:
            hosts = await asyncio.to_thread(parse_all_xml, self.paths.xml_dir)
            matches = await asyncio.to_thread(match_nmap, hosts, self.inventory)
            match_fields = sorted({key for row in matches for key in row}) if matches else [
                "nmap_status",
                "nmap_reason",
                "nmap_ipv4",
                "nmap_mac",
                "nmap_vendor",
                "nmap_hostname",
                "source_xml",
                "match_type",
                "source_row",
            ]
            await asyncio.to_thread(atomic_write_csv, self.paths.matches_csv, matches, match_fields)

            async with self.status_lock:
                status_rows = list(self.statuses.values())

            completed = sum(1 for row in status_rows if row.get("status") == "completed")
            failed = sum(1 for row in status_rows if row.get("status") == "failed")
            skipped = sum(1 for row in status_rows if row.get("status") == "skipped")
            resumed = sum(1 for row in status_rows if row.get("status") == "resumed_completed")
            running = sum(1 for row in status_rows if row.get("status") == "running")
            total = int(status_rows[0].get("total", "0") or 0) if status_rows else 0
            accounted = completed + failed + skipped + resumed
            percent_complete = accounted / total * 100 if total else 0.0

            summary = {
                "source": str(self.source_xlsx),
                "sheet": self.sheet,
                "total_targets": total,
                "completed_targets": completed,
                "resumed_completed_targets": resumed,
                "failed_targets": failed,
                "skipped_targets": skipped,
                "running_or_interrupted_targets": running,
                "accounted_targets": accounted,
                "percent_accounted_for": round(percent_complete, 2),
                "parsed_probe_hosts": len(hosts),
                "nmap_matches": len(matches),
                "last_updated": now_iso(),
                "outputs": {
                    "probe_status_csv": str(self.paths.status_csv),
                    "probe_progress_jsonl": str(self.paths.progress_jsonl),
                    "nmap_probe_matches_csv": str(self.paths.matches_csv),
                    "probe_run_summary_json": str(self.paths.summary_json),
                    "probe_xml_dir": str(self.paths.xml_dir),
                    "probe_logs_dir": str(self.paths.log_dir),
                },
            }
            await asyncio.to_thread(atomic_write_json, self.paths.summary_json, summary)
            return summary


class ProbeOrchestrator:
    def __init__(self, args: argparse.Namespace, paths: ProbePaths, store: ArtifactStore, targets: Sequence[ProbeTarget]) -> None:
        self.args = args
        self.paths = paths
        self.store = store
        self.targets = list(targets)
        self.logger = AsyncEventLogger(paths.progress_jsonl)
        self.print_lock = asyncio.Lock()
        self.target_queue: asyncio.Queue[ProbeTarget] = asyncio.Queue()

    async def print_line(self, text: str) -> None:
        async with self.print_lock:
            print(text, flush=True)

    def target_paths(self, target: ProbeTarget) -> Tuple[Path, Path, Path]:
        xml_path = self.paths.xml_dir / f"{target.base_name}.xml"
        stdout_path = self.paths.log_dir / f"{target.base_name}.stdout.log"
        stderr_path = self.paths.log_dir / f"{target.base_name}.stderr.log"
        return xml_path, stdout_path, stderr_path

    async def run_nmap_target(self, target: ProbeTarget, xml_path: Path, stdout_path: Path, stderr_path: Path) -> ProbeResult:
        command = [
            self.args.nmap_exe,
            "-sn",
            "-n",
            "--reason",
            "--host-timeout",
            self.args.host_timeout,
            "-oX",
            str(xml_path),
            target.target,
        ]
        start = time.monotonic()
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout_b, stderr_b = await asyncio.wait_for(process.communicate(), timeout=self.args.process_timeout)
        except asyncio.TimeoutError:
            process.kill()
            stdout_b, stderr_b = await process.communicate()
            await asyncio.to_thread(atomic_write_text, stdout_path, (stdout_b or b"").decode("utf-8", errors="replace"))
            await asyncio.to_thread(atomic_write_text, stderr_path, (stderr_b or b"").decode("utf-8", errors="replace"))
            return ProbeResult("failed", 124, f"Process timeout after {self.args.process_timeout} seconds", time.monotonic() - start)
        except asyncio.CancelledError:
            process.terminate()
            try:
                stdout_b, stderr_b = await asyncio.wait_for(process.communicate(), timeout=5)
            except Exception:
                process.kill()
                stdout_b, stderr_b = await process.communicate()
            await asyncio.to_thread(atomic_write_text, stdout_path, (stdout_b or b"").decode("utf-8", errors="replace"))
            await asyncio.to_thread(atomic_write_text, stderr_path, (stderr_b or b"").decode("utf-8", errors="replace"))
            raise

        stdout = (stdout_b or b"").decode("utf-8", errors="replace")
        stderr = (stderr_b or b"").decode("utf-8", errors="replace")
        await asyncio.to_thread(atomic_write_text, stdout_path, stdout)
        await asyncio.to_thread(atomic_write_text, stderr_path, stderr)

        rc = process.returncode if process.returncode is not None else 1
        status = "completed" if rc == 0 else "failed"
        error = "" if rc == 0 else (stderr or stdout or "Nmap returned non-zero exit code").strip()[:500]
        return ProbeResult(status, rc, error, time.monotonic() - start)

    async def mark_resumed(self, target: ProbeTarget, xml_path: Path, stdout_path: Path, stderr_path: Path, existing: Dict[str, str]) -> None:
        await self.store.update_status(target.target, {
            **existing,
            "target": target.target,
            "index": str(target.index),
            "total": str(target.total),
            "percent": f"{target.percent:.2f}",
            "status": "resumed_completed",
            "xml_path": str(xml_path),
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
        })
        summary = await self.store.refresh_analysis()
        await self.print_line(
            f"[{target.index}/{target.total} | {target.percent:6.2f}%] resume: already completed: {target.target} | "
            f"matches={summary['nmap_matches']} hosts={summary['parsed_probe_hosts']} analyzed={summary['percent_accounted_for']}%"
        )
        await self.logger.emit({"event": "target_resumed_completed", "target": target.target, "index": target.index, "total": target.total, "percent": round(target.percent, 2), "summary": summary})

    async def probe_one(self, target: ProbeTarget) -> None:
        xml_path, stdout_path, stderr_path = self.target_paths(target)
        existing = self.store.statuses.get(target.target, {})
        if not self.args.force and existing.get("status") in {"completed", "resumed_completed"} and xml_path.exists():
            await self.mark_resumed(target, xml_path, stdout_path, stderr_path, existing)
            return

        await self.print_line(f"[{target.index}/{target.total} | {target.percent:6.2f}%] probing: {target.target}")
        started_at = now_iso()
        await self.store.update_status(target.target, {
            "target": target.target,
            "index": str(target.index),
            "total": str(target.total),
            "percent": f"{target.percent:.2f}",
            "status": "running",
            "started_at": started_at,
            "ended_at": "",
            "duration_seconds": "",
            "return_code": "",
            "xml_path": str(xml_path),
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
            "source_column": target.source_column,
            "first_source_row": target.first_source_row,
            "source_rows": target.source_rows,
            "error": "",
        })
        await self.logger.emit({"event": "target_started", "target": target.target, "index": target.index, "total": target.total, "percent": round(target.percent, 2)})

        result = await self.run_nmap_target(target, xml_path, stdout_path, stderr_path)
        await self.store.update_status(target.target, {
            "status": result.status,
            "ended_at": now_iso(),
            "duration_seconds": f"{result.duration_seconds:.2f}",
            "return_code": str(result.return_code),
            "error": result.error,
        })

        summary = await self.store.refresh_analysis()
        await self.print_line(
            f"[{target.index}/{target.total} | {target.percent:6.2f}%] {result.status}: {target.target} | "
            f"rc={result.return_code} elapsed={result.duration_seconds:.1f}s hosts={summary['parsed_probe_hosts']} "
            f"matches={summary['nmap_matches']} analyzed={summary['percent_accounted_for']}%"
        )
        await self.logger.emit({
            "event": f"target_{result.status}",
            "target": target.target,
            "index": target.index,
            "total": target.total,
            "percent": round(target.percent, 2),
            "return_code": result.return_code,
            "duration_seconds": round(result.duration_seconds, 2),
            "summary": summary,
        })

    async def worker(self, worker_id: int) -> None:
        while True:
            target = await self.target_queue.get()
            try:
                await self.probe_one(target)
            except Exception as exc:
                await self.print_line(f"worker-{worker_id} failed target {target.target}: {exc}")
                await self.store.update_status(target.target, {
                    "target": target.target,
                    "index": str(target.index),
                    "total": str(target.total),
                    "percent": f"{target.percent:.2f}",
                    "status": "failed",
                    "ended_at": now_iso(),
                    "return_code": "1",
                    "error": str(exc)[:500],
                })
                await self.store.refresh_analysis()
                await self.logger.emit({"event": "target_exception", "target": target.target, "index": target.index, "error": str(exc)})
            finally:
                self.target_queue.task_done()

    async def run(self) -> int:
        await self.logger.start()
        await self.logger.emit({
            "event": "run_started",
            "total_targets": len(self.targets),
            "async_logging": True,
            "incremental_analysis": True,
            "fresh": bool(self.args.fresh),
            "force": bool(self.args.force),
            "max_concurrency": self.args.max_concurrency,
        })

        for target in self.targets:
            await self.target_queue.put(target)

        workers = [asyncio.create_task(self.worker(i + 1)) for i in range(self.args.max_concurrency)]
        try:
            await self.target_queue.join()
        except KeyboardInterrupt:
            await self.print_line("\nProbe interrupted. Refreshing analysis artifacts from completed XML files...")
            await self.logger.emit({"event": "run_interrupted"})
            summary = await self.store.refresh_analysis()
            print(json.dumps(summary, indent=2))
            return 130
        finally:
            for worker in workers:
                worker.cancel()
            await asyncio.gather(*workers, return_exceptions=True)
            final_summary = await self.store.refresh_analysis()
            await self.logger.emit({"event": "analysis_refreshed", "summary": final_summary})
            await self.logger.stop()

        summary = await self.store.refresh_analysis()
        print(json.dumps(summary, indent=2))
        return 0


async def run_probe_async(args: argparse.Namespace) -> int:
    source_xlsx = Path(args.source_xlsx)
    out_dir = Path(args.out_dir)

    if args.max_concurrency < 1:
        raise ValueError("--max-concurrency must be at least 1")
    if args.max_concurrency > 8:
        raise ValueError("--max-concurrency is capped at 8 for safety")

    if args.fresh and not args.analyze_only:
        print("Fresh run requested: clearing previous live-probe artifacts only.", flush=True)
        clear_probe_artifacts(out_dir)

    paths = ProbePaths.from_out_dir(out_dir)
    paths.ensure()

    rows = read_xlsx_rows(source_xlsx, args.sheet)
    inventory = build_inventory(rows)
    target_rows = read_target_rows(out_dir)
    targets = [
        ProbeTarget(
            index=i,
            total=len(target_rows),
            target=row["target"].strip(),
            source_column=row.get("source_column", ""),
            first_source_row=row.get("first_source_row", ""),
            source_rows=row.get("source_rows", ""),
        )
        for i, row in enumerate(target_rows, start=1)
    ]

    store = ArtifactStore(paths, inventory, source_xlsx, args.sheet)

    if args.analyze_only:
        summary = await store.refresh_analysis()
        print(json.dumps(summary, indent=2))
        return 0

    if not targets:
        print("No targets to probe.")
        return 0

    if args.max_concurrency > 1:
        print(f"Concurrent probing enabled: {args.max_concurrency} workers. Use only when approved for the network segment.", flush=True)

    orchestrator = ProbeOrchestrator(args, paths, store, targets)
    return await orchestrator.run()


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Run or analyze an async progress-aware Nmap probe.")
    parser.add_argument("--source-xlsx", required=True, help="Path to the source deployment workbook")
    parser.add_argument("--sheet", default="Deployments", help="Worksheet name, default: Deployments")
    parser.add_argument("--out-dir", required=True, help="Audit output folder containing targets.txt/nmap_targets.csv")
    parser.add_argument("--nmap-exe", default="nmap", help="Path to nmap.exe or command name")
    parser.add_argument("--host-timeout", default="45s", help="Nmap host timeout per target, default: 45s")
    parser.add_argument("--process-timeout", type=int, default=90, help="Python subprocess timeout per target in seconds")
    parser.add_argument("--max-concurrency", type=int, default=1, help="Number of async probe workers. Default 1; capped at 8.")
    parser.add_argument("--force", action="store_true", help="Rescan targets even if completed XML already exists")
    parser.add_argument("--fresh", action="store_true", help="Clear previous live-probe artifacts before starting")
    parser.add_argument("--analyze-only", action="store_true", help="Do not probe. Analyze completed XML/logs only")
    args = parser.parse_args(argv)
    return asyncio.run(run_probe_async(args))


if __name__ == "__main__":
    sys.exit(main())
