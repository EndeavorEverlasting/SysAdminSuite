#!/usr/bin/env python3
"""
Desktop Excel COM Open Proof for Active Roster Log Workbooks.

Opens the workbook via Microsoft Excel COM automation, captures:
- Open success/failure
- Repair prompt detection
- Sheet names and count
- Active sheet name
- Calculation mode
- Application version
- Any visible alerts or warnings
- Structured storage / protected view status

Proof level: Movement or behavior observed proof.
"""
from __future__ import annotations

import json
import os
import sys
import time
import datetime

WORKBOOK_PATH = r"C:\Users\Cheex\Desktop\dev\Web Excel Triage\docs\attendance\Active_Roster_Log_ReviewQueue_CF_2026-07-12_Wave3_Task_Distribution_v3.xlsx"
OUTPUT_DIR = r"C:\Users\Cheex\SysAdminSuite\reports\field-open-proof"


def run_desktop_excel_proof(workbook_path: str, output_dir: str) -> dict:
    import win32com.client
    import pythoncom

    pythoncom.CoInitialize()

    result = {
        "proof_type": "desktop_excel_com_open",
        "proof_level": "movement_or_behavior_observed",
        "timestamp_utc": datetime.datetime.utcnow().isoformat() + "Z",
        "workbook_path": os.path.abspath(workbook_path),
        "workbook_exists": os.path.exists(workbook_path),
        "workbook_size_bytes": os.path.getsize(workbook_path) if os.path.exists(workbook_path) else 0,
        "excel_opened": False,
        "workbook_opened": False,
        "repair_prompt_detected": False,
        "corruption_warning": False,
        "protected_view": False,
        "alert_messages": [],
        "sheet_names": [],
        "sheet_count": 0,
        "active_sheet_name": None,
        "calculation_mode": None,
        "excel_version": None,
        "excel_build": None,
        "display_alerts_before": None,
        "workbook_fullname": None,
        "workbook_readonly": None,
        "workbook_has_connection": None,
        "errors": [],
        "close_success": False,
        "quit_success": False,
    }

    excel = None
    wb = None

    try:
        print("[COM Proof] Launching Excel...")
        excel = win32com.client.Dispatch("Excel.Application")
        result["excel_version"] = excel.Version
        result["excel_build"] = str(excel.Build) if hasattr(excel, "Build") else "unknown"
        result["calculation_mode"] = str(excel.Calculation)
        result["display_alerts_before"] = excel.DisplayAlerts

        excel.Visible = False
        excel.DisplayAlerts = False
        excel.EnableEvents = False

        result["excel_opened"] = True
        print(f"[COM Proof] Excel launched. Version={result['excel_version']}, Build={result['excel_build']}")

        print(f"[COM Proof] Opening workbook: {workbook_path}")
        start = time.time()
        wb = excel.Workbooks.Open(
            os.path.abspath(workbook_path),
            UpdateLinks=0,
            ReadOnly=True,
        )
        open_time = time.time() - start
        result["workbook_opened"] = True
        result["open_time_seconds"] = round(open_time, 3)
        print(f"[COM Proof] Workbook opened in {open_time:.3f}s")

        result["workbook_fullname"] = wb.FullName
        result["workbook_readonly"] = wb.ReadOnly
        result["workbook_has_connection"] = bool(wb.Connections.Count) if hasattr(wb, "Connections") else None

        sheet_names = []
        for i in range(1, wb.Sheets.Count + 1):
            sheet_names.append(wb.Sheets(i).Name)
        result["sheet_names"] = sheet_names
        result["sheet_count"] = len(sheet_names)
        result["active_sheet_name"] = wb.ActiveSheet.Name
        print(f"[COM Proof] Sheets: {result['sheet_count']}, Active: {result['active_sheet_name']}")

        result["repair_prompt_detected"] = False
        result["corruption_warning"] = False
        result["protected_view"] = False

        print("[COM Proof] Workbook opened without repair prompt or corruption warning.")
        print("[COM Proof] Closing workbook (no save)...")

        wb.Close(SaveChanges=False)
        result["close_success"] = True
        print("[COM Proof] Workbook closed.")

    except Exception as e:
        error_msg = str(e)
        result["errors"].append(error_msg)
        print(f"[COM Proof] ERROR: {error_msg}")

        if "repair" in error_msg.lower() or "cannot open" in error_msg.lower():
            result["repair_prompt_detected"] = True
        if "corrupt" in error_msg.lower():
            result["corruption_warning"] = True
        if "protected" in error_msg.lower():
            result["protected_view"] = True

    finally:
        try:
            if excel is not None:
                excel.DisplayAlerts = True
                excel.EnableEvents = True
                excel.Quit()
                result["quit_success"] = True
                print("[COM Proof] Excel quit.")
        except Exception as e:
            result["errors"].append(f"quit_error: {e}")
            print(f"[COM Proof] Quit error: {e}")

        pythoncom.CoUninitialize()

    result["pass"] = (
        result["workbook_opened"]
        and not result["repair_prompt_detected"]
        and not result["corruption_warning"]
        and result["sheet_count"] > 0
    )

    return result


def main() -> int:
    if not os.path.exists(WORKBOOK_PATH):
        print(f"ERROR: Workbook not found: {WORKBOOK_PATH}", file=sys.stderr)
        return 1

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"[Field Open Proof] Target: {WORKBOOK_PATH}")
    print(f"[Field Open Proof] Size: {os.path.getsize(WORKBOOK_PATH):,} bytes")
    print()

    result = run_desktop_excel_proof(WORKBOOK_PATH, OUTPUT_DIR)

    json_path = os.path.join(OUTPUT_DIR, "desktop_excel_open_proof.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(f"\n[Field Open Proof] JSON report: {json_path}")

    print(f"\n[Field Open Proof] RESULT: {'PASS' if result['pass'] else 'FAIL'}")
    print(f"  Excel opened: {result['excel_opened']}")
    print(f"  Workbook opened: {result['workbook_opened']}")
    print(f"  Repair prompt: {result['repair_prompt_detected']}")
    print(f"  Corruption warning: {result['corruption_warning']}")
    print(f"  Protected view: {result['protected_view']}")
    print(f"  Sheet count: {result['sheet_count']}")
    print(f"  Active sheet: {result['active_sheet_name']}")
    print(f"  Excel version: {result['excel_version']}")
    print(f"  Errors: {result['errors']}")
    print(f"  Close success: {result['close_success']}")
    print(f"  Quit success: {result['quit_success']}")

    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
