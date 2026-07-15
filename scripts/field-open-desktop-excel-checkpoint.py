#!/usr/bin/env python3
"""Quick COM open proof for the Attendance Checkpoint workbook."""
from __future__ import annotations
import json, os, sys, time, datetime
import win32com.client
import pythoncom

WORKBOOK_PATH = r"C:\Users\Cheex\Desktop\dev\Web Excel Triage\docs\attendance\Active_Roster_Log_ReviewQueue_CF_2026-07-12_Wave3_Attendance_Checkpoint.xlsx"
OUTPUT_DIR = r"C:\Users\Cheex\SysAdminSuite\reports\field-open-proof"

def main() -> int:
    pythoncom.CoInitialize()
    result = {
        "proof_type": "desktop_excel_com_open_checkpoint",
        "proof_level": "movement_or_behavior_observed",
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "workbook_path": os.path.abspath(WORKBOOK_PATH),
        "workbook_exists": os.path.exists(WORKBOOK_PATH),
        "workbook_size_bytes": os.path.getsize(WORKBOOK_PATH) if os.path.exists(WORKBOOK_PATH) else 0,
        "pass": False,
    }
    excel = None
    try:
        excel = win32com.client.Dispatch("Excel.Application")
        result["excel_version"] = excel.Version
        excel.Visible = False
        excel.DisplayAlerts = False
        excel.EnableEvents = False
        result["excel_opened"] = True
        start = time.time()
        wb = excel.Workbooks.Open(os.path.abspath(WORKBOOK_PATH), UpdateLinks=0, ReadOnly=True)
        result["open_time_seconds"] = round(time.time() - start, 3)
        result["workbook_opened"] = True
        result["sheet_count"] = wb.Sheets.Count
        result["active_sheet_name"] = wb.ActiveSheet.Name
        result["sheet_names"] = [wb.Sheets(i).Name for i in range(1, wb.Sheets.Count + 1)]
        wb.Close(SaveChanges=False)
        result["close_success"] = True
        result["pass"] = True
    except Exception as e:
        result["errors"] = [str(e)]
    finally:
        try:
            if excel:
                excel.DisplayAlerts = True
                excel.EnableEvents = True
                excel.Quit()
        except: pass
        pythoncom.CoUninitialize()
    out = os.path.join(OUTPUT_DIR, "desktop_excel_open_proof_checkpoint.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(f"Checkpoint proof: {'PASS' if result['pass'] else 'FAIL'}")
    print(f"  Sheets: {result.get('sheet_count', '?')}, Active: {result.get('active_sheet_name', '?')}")
    print(f"  Report: {out}")
    return 0 if result["pass"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
