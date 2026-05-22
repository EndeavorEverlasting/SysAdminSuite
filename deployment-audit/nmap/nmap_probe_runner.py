#!/usr/bin/env python3
"""
Progress-aware Nmap probe runner for Cybernet / Neuron audits.

This runner intentionally scans one target at a time so the console and logs show
exactly what target is being probed, how far through the target list the run is,
and what completed before any premature termination.

No third-party Python packages are required.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Sequence

from cybernet_target_audit import build_inventory, match_nmap, parse_nmap_xml, read_xlsx_rows, write_csv


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def safe_name(value: str, max_len: int = 80) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    value = value.strip("._-") or "target"
    return value[:max_len]


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


def append_jsonl(path: Path, event: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")


def write_status(path: Path, statuses: Dict[str, Dict[str, str]]) -> None:
    fields = [
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
    write_csv(path, list(statuses.values()), fields)


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


def analyze_partial(source_xlsx: Path, sheet: str, out_dir: Path) -> Dict[str, object]:
    rows = read_xlsx_rows(source_xlsx, sheet)
    inventory = build_inventory(rows)
    hosts = parse_all_xml(out_dir / "probe_xml")
    matches = match_nmap(hosts, inventory)
    write_csv(out_dir / "nmap_probe_matches.csv", matches)

    status_rows = list(read_status(out_dir / "probe_status.csv").values())
    completed = sum(1 for row in status_rows if row.get("status") == "completed")
    failed = sum(1 for row in status_rows if row.get("status") == "failed")
    skipped = sum(1 for row in status_rows if row.get("status") == "skipped")
    running = sum(1 for row in status_rows if row.get("status") == "running")
    total = int(status_rows[0].get("total", "0") or 0) if status_rows else 0

    summary = {
        "source": str(source_xlsx),
        "sheet": sheet,
        "total_targets": total,
        "completed_targets": completed,
        "failed_targets": failed,
        "skipped_targets": skipped,
        "running_or_interrupted_targets": running,
        "parsed_probe_hosts": len(hosts),
        "nmap_matches": len(matches),
        "outputs": {
            "probe_status_csv": str(out_dir / "probe_status.csv"),
            "probe_progress_jsonl": str(out_dir / "probe_progress.jsonl"),
            "nmap_probe_matches_csv": str(out_dir / "nmap_probe_matches.csv"),
            "probe_xml_dir": str(out_dir / "probe_xml"),
        },
    }
    (out_dir / "probe_run_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def run_probe(args: argparse.Namespace) -> int:
    source_xlsx = Path(args.source_xlsx)
    out_dir = Path(args.out_dir)
    xml_dir = out_dir / "probe_xml"
    log_dir = out_dir / "probe_logs"
    status_csv = out_dir / "probe_status.csv"
    progress_jsonl = out_dir / "probe_progress.jsonl"
    xml_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    targets = read_target_rows(out_dir)
    total = len(targets)
    statuses = read_status(status_csv)

    if args.analyze_only:
        print(json.dumps(analyze_partial(source_xlsx, args.sheet, out_dir), indent=2))
        return 0

    if total == 0:
        print("No targets to probe.")
        return 0

    started_run = now_iso()
    append_jsonl(progress_jsonl, {"event": "run_started", "time": started_run, "total_targets": total})

    try:
        for idx, row in enumerate(targets, start=1):
            target = row["target"].strip()
            percent = (idx / total) * 100
            base = f"{idx:04d}-{safe_name(target)}"
            xml_path = xml_dir / f"{base}.xml"
            stdout_path = log_dir / f"{base}.stdout.log"
            stderr_path = log_dir / f"{base}.stderr.log"

            existing = statuses.get(target, {})
            if not args.force and existing.get("status") == "completed" and xml_path.exists():
                print(f"[{idx}/{total} | {percent:6.2f}%] skipping completed: {target}", flush=True)
                existing.update({"index": str(idx), "total": str(total), "percent": f"{percent:.2f}", "status": "skipped"})
                statuses[target] = existing
                write_status(status_csv, statuses)
                continue

            print(f"[{idx}/{total} | {percent:6.2f}%] probing: {target}", flush=True)
            start = time.monotonic()
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
            append_jsonl(progress_jsonl, {"event": "target_started", "time": started_at, "index": idx, "total": total, "percent": round(percent, 2), "target": target})

            command = [args.nmap_exe, "-sn", "-n", "--reason", "--host-timeout", args.host_timeout, "-oX", str(xml_path), target]
            try:
                completed = subprocess.run(command, capture_output=True, text=True, timeout=args.process_timeout, shell=False)
                stdout_path.write_text(completed.stdout or "", encoding="utf-8", errors="replace")
                stderr_path.write_text(completed.stderr or "", encoding="utf-8", errors="replace")
                status = "completed" if completed.returncode == 0 else "failed"
                error = "" if completed.returncode == 0 else (completed.stderr or completed.stdout or "Nmap returned non-zero exit code").strip()[:500]
                rc = completed.returncode
            except subprocess.TimeoutExpired as exc:
                stdout_path.write_text(exc.stdout or "", encoding="utf-8", errors="replace")
                stderr_path.write_text(exc.stderr or "", encoding="utf-8", errors="replace")
                status = "failed"
                error = f"Process timeout after {args.process_timeout} seconds"
                rc = 124

            ended_at = now_iso()
            duration = time.monotonic() - start
            statuses[target].update({
                "status": status,
                "ended_at": ended_at,
                "duration_seconds": f"{duration:.2f}",
                "return_code": str(rc),
                "error": error,
            })
            write_status(status_csv, statuses)
            append_jsonl(progress_jsonl, {"event": f"target_{status}", "time": ended_at, "index": idx, "total": total, "percent": round(percent, 2), "target": target, "return_code": rc, "duration_seconds": round(duration, 2)})

    except KeyboardInterrupt:
        print("\nProbe interrupted. Analyzing completed probe XML files...", flush=True)
        append_jsonl(progress_jsonl, {"event": "run_interrupted", "time": now_iso()})
        summary = analyze_partial(source_xlsx, args.sheet, out_dir)
        print(json.dumps(summary, indent=2))
        return 130

    summary = analyze_partial(source_xlsx, args.sheet, out_dir)
    append_jsonl(progress_jsonl, {"event": "run_finished", "time": now_iso(), "summary": summary})
    print(json.dumps(summary, indent=2))
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Run or analyze a progress-aware Nmap probe.")
    parser.add_argument("--source-xlsx", required=True, help="Path to the source deployment workbook")
    parser.add_argument("--sheet", default="Deployments", help="Worksheet name, default: Deployments")
    parser.add_argument("--out-dir", required=True, help="Audit output folder containing targets.txt/nmap_targets.csv")
    parser.add_argument("--nmap-exe", default="nmap", help="Path to nmap.exe or command name")
    parser.add_argument("--host-timeout", default="45s", help="Nmap host timeout per target, default: 45s")
    parser.add_argument("--process-timeout", type=int, default=90, help="Python subprocess timeout per target in seconds")
    parser.add_argument("--force", action="store_true", help="Rescan targets even if completed XML already exists")
    parser.add_argument("--analyze-only", action="store_true", help="Do not probe. Analyze completed XML/logs only")
    args = parser.parse_args(argv)
    return run_probe(args)


if __name__ == "__main__":
    sys.exit(main())
