#!/usr/bin/env python3
"""
Async, progress-aware Nmap probe runner for Cybernet / Neuron audits.

The runner scans one target at a time by default, but it is implemented with
async subprocess execution and an async event logger so artifacts are updated
continuously while the probe is running.

Key guarantees:
- Console shows target, index, percent, elapsed time, and analysis counts.
- probe_progress.jsonl is flushed after every event.
- probe_status.csv is rewritten after every state change.
- nmap_probe_matches.csv and probe_run_summary.json are refreshed after every
  completed target, not only at the end.
- Ctrl+C / premature termination triggers best-effort analysis of completed XML.
- Resume mode preserves completed targets as completed; --fresh clears previous
  probe artifacts and starts over cleanly.

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
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from cybernet_target_audit import build_inventory, match_nmap, parse_nmap_xml, read_xlsx_rows, write_csv

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


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def safe_name(value: str, max_len: int = 80) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    value = value.strip("._-") or "target"
    return value[:max_len]


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


def write_status(path: Path, statuses: Dict[str, Dict[str, str]]) -> None:
    rows = sorted(statuses.values(), key=lambda r: int(r.get("index") or 0))
    write_csv(path, rows, STATUS_FIELDS)


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


def analyze_current(inventory: Sequence[Dict[str, str]], out_dir: Path, source_xlsx: Path, sheet: str) -> Dict[str, object]:
    hosts = parse_all_xml(out_dir / "probe_xml")
    matches = match_nmap(hosts, inventory)
    write_csv(out_dir / "nmap_probe_matches.csv", matches)

    status_rows = list(read_status(out_dir / "probe_status.csv").values())
    completed = sum(1 for row in status_rows if row.get("status") == "completed")
    failed = sum(1 for row in status_rows if row.get("status") == "failed")
    skipped = sum(1 for row in status_rows if row.get("status") == "skipped")
    resumed = sum(1 for row in status_rows if row.get("status") == "resumed_completed")
    running = sum(1 for row in status_rows if row.get("status") == "running")
    total = int(status_rows[0].get("total", "0") or 0) if status_rows else 0
    percent_complete = (completed + failed + skipped + resumed) / total * 100 if total else 0.0

    summary = {
        "source": str(source_xlsx),
        "sheet": sheet,
        "total_targets": total,
        "completed_targets": completed,
        "resumed_completed_targets": resumed,
        "failed_targets": failed,
        "skipped_targets": skipped,
        "running_or_interrupted_targets": running,
        "percent_accounted_for": round(percent_complete, 2),
        "parsed_probe_hosts": len(hosts),
        "nmap_matches": len(matches),
        "last_updated": now_iso(),
        "outputs": {
            "probe_status_csv": str(out_dir / "probe_status.csv"),
            "probe_progress_jsonl": str(out_dir / "probe_progress.jsonl"),
            "nmap_probe_matches_csv": str(out_dir / "nmap_probe_matches.csv"),
            "probe_run_summary_json": str(out_dir / "probe_run_summary.json"),
            "probe_xml_dir": str(out_dir / "probe_xml"),
            "probe_logs_dir": str(out_dir / "probe_logs"),
        },
    }
    (out_dir / "probe_run_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


async def event_logger(queue: asyncio.Queue[Optional[Dict[str, object]]], progress_path: Path) -> None:
    progress_path.parent.mkdir(parents=True, exist_ok=True)
    with progress_path.open("a", encoding="utf-8") as f:
        while True:
            event = await queue.get()
            try:
                if event is None:
                    return
                f.write(json.dumps(event, ensure_ascii=False) + "\n")
                f.flush()
            finally:
                queue.task_done()


async def log_event(queue: asyncio.Queue[Optional[Dict[str, object]]], event: Dict[str, object]) -> None:
    event.setdefault("time", now_iso())
    await queue.put(event)


async def run_nmap_target(
    nmap_exe: str,
    target: str,
    xml_path: Path,
    stdout_path: Path,
    stderr_path: Path,
    host_timeout: str,
    process_timeout: int,
) -> Tuple[str, int, str, float]:
    command = [nmap_exe, "-sn", "-n", "--reason", "--host-timeout", host_timeout, "-oX", str(xml_path), target]
    start = time.monotonic()
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout_b, stderr_b = await asyncio.wait_for(process.communicate(), timeout=process_timeout)
    except asyncio.TimeoutError:
        process.kill()
        stdout_b, stderr_b = await process.communicate()
        stdout_path.write_text((stdout_b or b"").decode("utf-8", errors="replace"), encoding="utf-8", errors="replace")
        stderr_path.write_text((stderr_b or b"").decode("utf-8", errors="replace"), encoding="utf-8", errors="replace")
        return "failed", 124, f"Process timeout after {process_timeout} seconds", time.monotonic() - start
    except asyncio.CancelledError:
        process.terminate()
        try:
            stdout_b, stderr_b = await asyncio.wait_for(process.communicate(), timeout=5)
        except Exception:
            process.kill()
            stdout_b, stderr_b = await process.communicate()
        stdout_path.write_text((stdout_b or b"").decode("utf-8", errors="replace"), encoding="utf-8", errors="replace")
        stderr_path.write_text((stderr_b or b"").decode("utf-8", errors="replace"), encoding="utf-8", errors="replace")
        raise

    stdout = (stdout_b or b"").decode("utf-8", errors="replace")
    stderr = (stderr_b or b"").decode("utf-8", errors="replace")
    stdout_path.write_text(stdout, encoding="utf-8", errors="replace")
    stderr_path.write_text(stderr, encoding="utf-8", errors="replace")

    rc = process.returncode if process.returncode is not None else 1
    status = "completed" if rc == 0 else "failed"
    error = "" if rc == 0 else (stderr or stdout or "Nmap returned non-zero exit code").strip()[:500]
    return status, rc, error, time.monotonic() - start


async def run_probe_async(args: argparse.Namespace) -> int:
    source_xlsx = Path(args.source_xlsx)
    out_dir = Path(args.out_dir)

    if args.fresh and not args.analyze_only:
        print("Fresh run requested: clearing previous live-probe artifacts only.", flush=True)
        clear_probe_artifacts(out_dir)

    xml_dir = out_dir / "probe_xml"
    log_dir = out_dir / "probe_logs"
    status_csv = out_dir / "probe_status.csv"
    progress_jsonl = out_dir / "probe_progress.jsonl"
    xml_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    rows = read_xlsx_rows(source_xlsx, args.sheet)
    inventory = build_inventory(rows)
    targets = read_target_rows(out_dir)
    total = len(targets)
    statuses = read_status(status_csv)

    if args.analyze_only:
        summary = analyze_current(inventory, out_dir, source_xlsx, args.sheet)
        print(json.dumps(summary, indent=2))
        return 0

    if total == 0:
        print("No targets to probe.")
        return 0

    queue: asyncio.Queue[Optional[Dict[str, object]]] = asyncio.Queue()
    logger_task = asyncio.create_task(event_logger(queue, progress_jsonl))

    await log_event(queue, {"event": "run_started", "total_targets": total, "async_logging": True, "incremental_analysis": True, "fresh": bool(args.fresh), "force": bool(args.force)})

    try:
        for idx, row in enumerate(targets, start=1):
            target = row["target"].strip()
            percent = (idx / total) * 100
            base = f"{idx:04d}-{safe_name(target)}"
            xml_path = xml_dir / f"{base}.xml"
            stdout_path = log_dir / f"{base}.stdout.log"
            stderr_path = log_dir / f"{base}.stderr.log"

            existing = statuses.get(target, {})
            if not args.force and existing.get("status") in {"completed", "resumed_completed"} and xml_path.exists():
                # Resume mode: do not relabel a completed target as skipped. Keep it accounted for.
                statuses[target] = {
                    **existing,
                    "index": str(idx),
                    "total": str(total),
                    "percent": f"{percent:.2f}",
                    "status": "resumed_completed",
                    "xml_path": str(xml_path),
                    "stdout_log": str(stdout_path),
                    "stderr_log": str(stderr_path),
                }
                write_status(status_csv, statuses)
                summary = analyze_current(inventory, out_dir, source_xlsx, args.sheet)
                print(
                    f"[{idx}/{total} | {percent:6.2f}%] resume: already completed: {target} | "
                    f"matches={summary['nmap_matches']} hosts={summary['parsed_probe_hosts']} analyzed={summary['percent_accounted_for']}%",
                    flush=True,
                )
                await log_event(queue, {"event": "target_resumed_completed", "index": idx, "total": total, "percent": round(percent, 2), "target": target, "summary": summary})
                continue

            print(f"[{idx}/{total} | {percent:6.2f}%] probing: {target}", flush=True)
            started_at = now_iso()
            statuses[target] = {
                "target": target,
                "index": str(idx),
                "total": str(total),
                "percent": f"{percent:.2f}",
                "status": "running",
                "started_at": started_at,
                "ended_at": "",
                "duration_seconds": "",
                "return_code": "",
                "xml_path": str(xml_path),
                "stdout_log": str(stdout_path),
                "stderr_log": str(stderr_path),
                "source_column": row.get("source_column", ""),
                "first_source_row": row.get("first_source_row", ""),
                "source_rows": row.get("source_rows", ""),
                "error": "",
            }
            write_status(status_csv, statuses)
            await log_event(queue, {"event": "target_started", "index": idx, "total": total, "percent": round(percent, 2), "target": target})

            status, rc, error, duration = await run_nmap_target(
                args.nmap_exe,
                target,
                xml_path,
                stdout_path,
                stderr_path,
                args.host_timeout,
                args.process_timeout,
            )

            ended_at = now_iso()
            statuses[target].update({
                "status": status,
                "ended_at": ended_at,
                "duration_seconds": f"{duration:.2f}",
                "return_code": str(rc),
                "error": error,
            })
            write_status(status_csv, statuses)

            summary = analyze_current(inventory, out_dir, source_xlsx, args.sheet)
            print(
                f"[{idx}/{total} | {percent:6.2f}%] {status}: {target} | "
                f"rc={rc} elapsed={duration:.1f}s hosts={summary['parsed_probe_hosts']} "
                f"matches={summary['nmap_matches']} analyzed={summary['percent_accounted_for']}%",
                flush=True,
            )
            await log_event(queue, {
                "event": f"target_{status}",
                "index": idx,
                "total": total,
                "percent": round(percent, 2),
                "target": target,
                "return_code": rc,
                "duration_seconds": round(duration, 2),
                "summary": summary,
            })

    except KeyboardInterrupt:
        print("\nProbe interrupted. Refreshing analysis artifacts from completed XML files...", flush=True)
        await log_event(queue, {"event": "run_interrupted"})
        summary = analyze_current(inventory, out_dir, source_xlsx, args.sheet)
        print(json.dumps(summary, indent=2))
        return 130
    finally:
        final_summary = analyze_current(inventory, out_dir, source_xlsx, args.sheet)
        await log_event(queue, {"event": "analysis_refreshed", "summary": final_summary})
        await queue.put(None)
        await queue.join()
        await logger_task

    summary = analyze_current(inventory, out_dir, source_xlsx, args.sheet)
    print(json.dumps(summary, indent=2))
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Run or analyze an async progress-aware Nmap probe.")
    parser.add_argument("--source-xlsx", required=True, help="Path to the source deployment workbook")
    parser.add_argument("--sheet", default="Deployments", help="Worksheet name, default: Deployments")
    parser.add_argument("--out-dir", required=True, help="Audit output folder containing targets.txt/nmap_targets.csv")
    parser.add_argument("--nmap-exe", default="nmap", help="Path to nmap.exe or command name")
    parser.add_argument("--host-timeout", default="45s", help="Nmap host timeout per target, default: 45s")
    parser.add_argument("--process-timeout", type=int, default=90, help="Python subprocess timeout per target in seconds")
    parser.add_argument("--force", action="store_true", help="Rescan targets even if completed XML already exists")
    parser.add_argument("--fresh", action="store_true", help="Clear previous live-probe artifacts before starting")
    parser.add_argument("--analyze-only", action="store_true", help="Do not probe. Analyze completed XML/logs only")
    args = parser.parse_args(argv)
    return asyncio.run(run_probe_async(args))


if __name__ == "__main__":
    sys.exit(main())
