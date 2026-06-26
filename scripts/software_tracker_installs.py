#!/usr/bin/env python3
"""Guarded Software Tracker install planner/runner.

Primary operator surface for new SysAdminSuite Software Tracker install work is
Python + Bash/CMD. Existing PowerShell install scripts remain legacy/reference
tooling for other Windows corporate environments and are not used here.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shlex
import subprocess
import sys
import time
import zipfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pkgrel": "http://schemas.openxmlformats.org/package/2006/relationships",
}

DIRECT_INSTALLER_EXTENSIONS = {".msi", ".exe", ".cmd", ".bat", ".ps1", ".msix"}
PLACEHOLDERS = {"", "list", "n/a", "na", "none", "tbd", "manual", "manual review"}


@dataclass
class PlanOptions:
    tracker_path: Path
    output_dir: Path
    execute: bool = False
    allow_discovered_folder_installs: bool = False
    config_path: Path | None = None
    list_name: str | None = None
    software_name: str | None = None
    path_aliases: dict[str, str] = field(default_factory=dict)


@dataclass
class PlanItem:
    source_sheet: str
    row_number: int
    software_name: str
    original_path: str
    normalized_path: str
    resolved_path: str
    path_kind: str
    action: str
    status: str
    reason: str
    install_args: str = ""
    command_argv: list[str] = field(default_factory=list)
    execute_requested: bool = False
    executed: bool = False
    exit_code: int | None = None
    errors: list[str] = field(default_factory=list)


def _cell_ref_col(ref: str) -> int:
    match = re.match(r"([A-Z]+)", ref or "A")
    col = match.group(1) if match else "A"
    value = 0
    for ch in col:
        value = value * 26 + (ord(ch) - 64)
    return value - 1


def _shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    values: list[str] = []
    for si in root.findall(".//main:si", NS):
        values.append("".join((node.text or "") for node in si.findall(".//main:t", NS)))
    return values


def _sheet_paths(zf: zipfile.ZipFile) -> list[tuple[str, str]]:
    workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rel_map = {rel.get("Id"): rel.get("Target") for rel in rels}
    sheets: list[tuple[str, str]] = []
    for sheet in workbook.findall(".//main:sheets/main:sheet", NS):
        name = sheet.get("name") or "Sheet"
        rel_id = sheet.get(f"{{{NS['rel']}}}id")
        target = rel_map.get(rel_id or "")
        if not target:
            continue
        sheets.append((name, "xl/" + target.lstrip("/")))
    return sheets


def _read_sheet(zf: zipfile.ZipFile, path: str, shared: list[str]) -> list[list[str]]:
    root = ET.fromstring(zf.read(path))
    rows: list[list[str]] = []
    for row in root.findall(".//main:sheetData/main:row", NS):
        cells: dict[int, str] = {}
        for cell in row.findall("main:c", NS):
            index = _cell_ref_col(cell.get("r", "A"))
            cell_type = cell.get("t")
            value = ""
            if cell_type == "inlineStr":
                inline = cell.find("main:is", NS)
                if inline is not None:
                    value = "".join((node.text or "") for node in inline.findall(".//main:t", NS))
            else:
                raw = cell.find("main:v", NS)
                if raw is not None and raw.text is not None:
                    value = shared[int(raw.text)] if cell_type == "s" and shared else raw.text
            cells[index] = value
        if cells:
            max_index = max(cells)
            rows.append([cells.get(i, "") for i in range(max_index + 1)])
    return rows


def read_xlsx(path: Path) -> dict[str, list[list[str]]]:
    with zipfile.ZipFile(path) as zf:
        shared = _shared_strings(zf)
        return {name: _read_sheet(zf, sheet_path, shared) for name, sheet_path in _sheet_paths(zf)}


def normalize_header(value: str) -> str:
    key = re.sub(r"[^a-z0-9]+", "_", (value or "").strip().lower()).strip("_")
    aliases = {
        "raw_names": "software_name",
        "software": "software_name",
        "softwarename": "software_name",
        "package": "software_name",
        "path": "installer_path",
        "installerpath": "installer_path",
        "installargs": "install_args",
        "install_required": "install_required",
        "installrequired": "install_required",
    }
    return aliases.get(key, key)


def rows_to_dicts(rows: list[list[str]]) -> list[tuple[int, dict[str, str]]]:
    if not rows:
        return []
    headers = [normalize_header(cell) for cell in rows[0]]
    output: list[tuple[int, dict[str, str]]] = []
    for offset, row in enumerate(rows[1:], start=2):
        data = {headers[i]: row[i].strip() if i < len(row) else "" for i in range(len(headers))}
        if any(data.values()):
            output.append((offset, data))
    return output


def detect_mode(sheets: dict[str, list[list[str]]]) -> str:
    lower = {name.lower(): name for name in sheets}
    if "directories" in lower:
        return "catalog"
    if "software tracker" in lower:
        return "tracker"
    raise ValueError("SUPPORTED_SHEET_NOT_FOUND")


def load_config(path: Path | None) -> dict[str, Any]:
    if not path:
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_options(args: argparse.Namespace) -> PlanOptions:
    config_path = Path(args.config) if args.config else None
    config = load_config(config_path)
    return PlanOptions(
        tracker_path=Path(args.tracker_path),
        output_dir=Path(args.output_dir),
        execute=bool(args.execute),
        allow_discovered_folder_installs=bool(args.allow_discovered_folder_installs),
        config_path=config_path,
        list_name=args.list_name,
        software_name=args.software_name,
        path_aliases=dict(config.get("pathAliases", {})),
    )


def strip_quotes(value: str) -> str:
    value = (value or "").strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1].strip()
    return value


def split_path_cell(value: str) -> list[str]:
    parts: list[str] = []
    for line in re.split(r"[\r\n]+", value or ""):
        text = strip_quotes(line)
        if not text:
            continue
        # Strip human labels like "Prod: \\server\share\setup.msi" but keep
        # drive letters such as "Z:\path\setup.msi" intact.
        label_match = re.match(r"^[A-Za-z][A-Za-z0-9 _-]{1,30}:\s+(.+)$", text)
        if label_match:
            text = label_match.group(1).strip()
        parts.append(strip_quotes(text))
    return parts or [""]


def classify_path(path_text: str) -> str:
    value = strip_quotes(path_text)
    if value.lower() in PLACEHOLDERS:
        return "placeholder" if value else "blank"
    if re.match(r"^https?://", value, re.IGNORECASE):
        return "url"
    suffix = Path(value.replace("\\", "/")).suffix.lower()
    if suffix in DIRECT_INSTALLER_EXTENSIONS:
        return "direct_installer_file"
    if value.startswith("\\\\") or re.match(r"^[A-Za-z]:[\\/]", value) or "/" in value or "\\" in value:
        return "directory_path"
    return "unknown"


def _alias_key_sort(key: str) -> int:
    return len(key.replace("/", "\\").lower())


def resolve_alias(path_text: str, aliases: dict[str, str]) -> str:
    value = strip_quotes(path_text)
    if not value:
        return value
    norm = value.replace("/", "\\").lower()
    for source in sorted(aliases, key=_alias_key_sort, reverse=True):
        source_norm = source.replace("/", "\\").lower()
        if norm == source_norm:
            return aliases[source]
        if norm.startswith(source_norm.rstrip("\\") + "\\"):
            tail = value[len(source.rstrip("\\/")) :].lstrip("\\/")
            return str(Path(aliases[source]) / tail)
    return value


def installer_type(path_text: str) -> str:
    suffix = Path(path_text.replace("\\", "/")).suffix.lower()
    return suffix.lstrip(".") if suffix in DIRECT_INSTALLER_EXTENSIONS else "unknown"


def split_args(args: str) -> list[str]:
    if not args:
        return []
    try:
        return shlex.split(args, posix=False)
    except ValueError:
        return args.split()


def build_command(path_text: str, resolved_path: str, install_args: str) -> tuple[list[str], str | None]:
    kind = installer_type(path_text)
    if kind == "msi":
        return ["msiexec.exe", "/i", resolved_path, "/qn", "/norestart", *split_args(install_args)], None
    if kind == "exe":
        if not install_args.strip():
            return [], "EXE_REQUIRES_EXPLICIT_SILENT_ARGS"
        return [resolved_path, *split_args(install_args)], None
    if kind == "cmd":
        return ["cmd.exe", "/c", resolved_path, *split_args(install_args)], None
    if kind == "bat":
        return ["cmd.exe", "/c", resolved_path, *split_args(install_args)], None
    if kind == "ps1":
        return ["python", "-c", "raise SystemExit('PS1 execution is legacy/manual-review in this workflow')"], "POWERSHELL_INSTALLER_MANUAL_REVIEW"
    if kind == "msix":
        return [], "MSIX_MANUAL_REVIEW"
    return [], "UNKNOWN_INSTALLER_TYPE"


def make_item(sheet: str, row_number: int, row: dict[str, str], path_text: str, options: PlanOptions) -> PlanItem:
    software = row.get("software_name", "").strip()
    install_args = row.get("install_args", "").strip()
    normalized = strip_quotes(path_text)
    path_kind = classify_path(normalized)
    resolved = resolve_alias(normalized, options.path_aliases)
    item = PlanItem(
        source_sheet=sheet,
        row_number=row_number,
        software_name=software,
        original_path=path_text,
        normalized_path=normalized,
        resolved_path=resolved,
        path_kind=path_kind,
        action="Review",
        status="Blocked",
        reason="",
        install_args=install_args,
        execute_requested=options.execute,
    )

    if not software:
        item.reason = "MISSING_SOFTWARE_NAME"
        item.errors.append(item.reason)
        return item
    if path_kind == "blank":
        item.reason = "MISSING_INSTALLER_PATH"
        item.errors.append(item.reason)
        return item
    if path_kind == "placeholder":
        item.action = "ManualReview"
        item.status = "ManualReview"
        item.reason = "PLACEHOLDER_PATH"
        return item
    if path_kind == "url":
        item.reason = "URL_EXECUTION_BLOCKED"
        item.errors.append(item.reason)
        return item
    if path_kind == "directory_path":
        item.action = "ManualReview"
        item.status = "ManualReview"
        item.reason = "DIRECTORY_PATH_REQUIRES_MANUAL_REVIEW"
        if options.execute and options.allow_discovered_folder_installs:
            discovered = discover_folder_installers(Path(resolved))
            if discovered:
                item.action = "DiscoverFolderInstallers"
                item.status = "DryRun" if not options.execute else "Planned"
                item.reason = f"DISCOVERED_{len(discovered)}_INSTALLER_CANDIDATES"
            else:
                item.status = "Blocked"
                item.reason = "NO_INSTALLERS_DISCOVERED_IN_FOLDER"
                item.errors.append(item.reason)
        return item
    if path_kind != "direct_installer_file":
        item.reason = "UNSUPPORTED_PATH_KIND"
        item.errors.append(item.reason)
        return item

    command, error = build_command(normalized, resolved, install_args)
    if error:
        item.reason = error
        item.errors.append(error)
        return item
    item.command_argv = command
    item.action = "Install"
    if not options.execute:
        item.status = "DryRun"
        item.reason = "DRY_RUN_NO_INSTALL"
        return item
    item.status = "Planned"
    item.reason = "EXECUTE_REQUESTED"
    return item


def discover_folder_installers(folder: Path) -> list[Path]:
    if not folder.exists() or not folder.is_dir():
        return []
    found: list[Path] = []
    for child in folder.iterdir():
        if child.suffix.lower() in DIRECT_INSTALLER_EXTENSIONS:
            found.append(child)
    return sorted(found)


def catalog_allowed_names(sheets: dict[str, list[list[str]]], list_name: str | None) -> set[str] | None:
    if not list_name or "Packages" not in sheets:
        return None
    rows = rows_to_dicts(sheets["Packages"])
    names = {row.get("software_name", "").strip().lower() for _, row in rows if row.get("software_name", "").strip()}
    return names


def plan_catalog(sheets: dict[str, list[list[str]]], options: PlanOptions) -> list[PlanItem]:
    rows = rows_to_dicts(sheets["Directories"])
    allowed = catalog_allowed_names(sheets, options.list_name)
    items: list[PlanItem] = []
    for row_number, row in rows:
        names = [part.strip() for part in row.get("software_name", "").split(",") if part.strip()]
        primary = names[0] if names else row.get("software_name", "")
        if allowed is not None and primary.lower() not in allowed:
            continue
        if options.software_name and options.software_name.lower() not in {name.lower() for name in names} | {primary.lower()}:
            continue
        row = {**row, "software_name": primary}
        for path_text in split_path_cell(row.get("installer_path", "")):
            items.append(make_item("Directories", row_number, row, path_text, options))
    return items


def _required_flag(value: str) -> tuple[bool, str | None]:
    normalized = (value or "").strip().lower()
    if normalized in {"yes", "y", "true", "1", "required", "pending"}:
        return True, None
    if normalized in {"no", "n", "false", "0", "not required", "installed"}:
        return False, None
    return False, "AMBIGUOUS_INSTALL_REQUIRED"


def plan_tracker(sheets: dict[str, list[list[str]]], options: PlanOptions) -> list[PlanItem]:
    rows = rows_to_dicts(sheets["Software Tracker"])
    items: list[PlanItem] = []
    for row_number, row in rows:
        if options.software_name and row.get("software_name", "").lower() != options.software_name.lower():
            continue
        required, error = _required_flag(row.get("install_required", "yes"))
        if error:
            item = make_item("Software Tracker", row_number, row, row.get("installer_path", ""), options)
            item.status = "Blocked"
            item.reason = error
            item.errors.append(error)
            items.append(item)
            continue
        if not required:
            continue
        for path_text in split_path_cell(row.get("installer_path", "")):
            items.append(make_item("Software Tracker", row_number, row, path_text, options))
    return items


def execute_items(items: list[PlanItem], options: PlanOptions) -> None:
    if not options.execute:
        return
    for item in items:
        if item.status != "Planned" or not item.command_argv:
            continue
        try:
            completed = subprocess.run(item.command_argv, shell=False, check=False)
            item.executed = True
            item.exit_code = completed.returncode
            item.status = "Succeeded" if completed.returncode == 0 else "Failed"
            item.reason = "EXECUTED" if completed.returncode == 0 else f"EXIT_CODE_{completed.returncode}"
        except Exception as exc:  # pragma: no cover - defensive path
            item.status = "Failed"
            item.reason = "EXECUTION_ERROR"
            item.errors.append(str(exc))


def summarize(items: list[PlanItem]) -> dict[str, Any]:
    counts: dict[str, int] = {}
    for item in items:
        counts[item.status] = counts.get(item.status, 0) + 1
    return {
        "total": len(items),
        "counts": counts,
        "blocked": sum(1 for item in items if item.status == "Blocked"),
        "manual_review": sum(1 for item in items if item.status == "ManualReview"),
    }


def write_reports(items: list[PlanItem], output_dir: Path) -> dict[str, str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    summary = summarize(items)
    rows = [asdict(item) for item in items]
    json_path = output_dir / "install-summary.json"
    csv_path = output_dir / "install-summary.csv"
    text_path = output_dir / "install-log.txt"
    json_path.write_text(json.dumps({"summary": summary, "items": rows}, indent=2), encoding="utf-8")
    fieldnames = [
        "source_sheet",
        "row_number",
        "software_name",
        "path_kind",
        "status",
        "action",
        "reason",
        "normalized_path",
        "resolved_path",
        "install_args",
        "execute_requested",
        "executed",
        "exit_code",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for item in items:
            data = asdict(item)
            writer.writerow({name: data.get(name, "") for name in fieldnames})
    lines = [
        "SysAdminSuite Software Tracker install plan",
        f"Generated: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
        f"Total: {summary['total']}",
        f"Counts: {summary['counts']}",
        "",
    ]
    for item in items:
        lines.append(f"{item.status}: {item.software_name} [{item.reason}] {item.normalized_path}")
    text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"json": str(json_path), "csv": str(csv_path), "text": str(text_path)}


def plan_workbook(options: PlanOptions) -> list[PlanItem]:
    sheets = read_xlsx(options.tracker_path)
    mode = detect_mode(sheets)
    if mode == "catalog":
        return plan_catalog(sheets, options)
    return plan_tracker(sheets, options)


def run(options: PlanOptions) -> tuple[list[PlanItem], dict[str, str]]:
    items = plan_workbook(options)
    execute_items(items, options)
    reports = write_reports(items, options.output_dir)
    return items, reports


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Plan or run guarded installs from a Software Tracker workbook.")
    parser.add_argument("--tracker-path", "--tracker", dest="tracker_path", required=True)
    parser.add_argument("--list-name", "--list", dest="list_name")
    parser.add_argument("--software-name", "--software", dest="software_name")
    parser.add_argument("--output-dir", default="survey/output/software-tracker-install")
    parser.add_argument("--config")
    parser.add_argument("--execute", action="store_true", help="Actually run allowed installer commands. Default is dry-run.")
    parser.add_argument("--allow-discovered-folder-installs", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    options = load_options(args)
    try:
        items, reports = run(options)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    summary = summarize(items)
    print(json.dumps({"summary": summary, "reports": reports}, indent=2))
    # Blocked/manual-review items are expected safety outcomes (for URLs,
    # folders, EXEs without args, and bad rows). The CLI exits nonzero only when
    # the tool itself fails or an executed installer reports failure.
    return 1 if any(item.status == "Failed" for item in items) else 0


if __name__ == "__main__":
    raise SystemExit(main())
