# Active Roster Log — Field Open Proof Report

**Sprint:** sprint/roster-excel-field-open-proof
**Date:** 2026-07-14
**Proof Level:** Movement or behavior observed proof

---

## Executive Summary

Both July Wave 3 roster workbooks were opened in desktop Microsoft Excel 16.0 via COM automation. Neither workbook triggered a repair prompt, corruption warning, or protected-view block. The workbooks can now be called **Excel-opened** at the movement-or-behavior-observed proof level.

Excel for Web verification requires manual operator confirmation after OneDrive sync completes. Both files have been staged in OneDrive for this purpose.

---

## Environment

| Item | Value |
|------|-------|
| OS | Windows (win32) |
| Excel | Microsoft Excel 16.0 (Build 20131) |
| Python | 3.12+ (Anaconda) |
| COM Automation | pywin32 (win32com.client) |
| openpyxl | 3.1.5 (structural validator) |

---

## Artifact 1: Final Workbook (Task Distribution v3)

| Property | Value |
|----------|-------|
| File | `Active_Roster_Log_ReviewQueue_CF_2026-07-12_Wave3_Task_Distribution_v3.xlsx` |
| Size | 5,226,029 bytes |
| Sheets | 89 |
| Active Sheet | July Wave3 Billing Detail |
| Formulas | 267,425 |
| Formula Errors | 0 |
| Forbidden Tokens | 0 |
| Private Sheets | 5 (`_Wave3 Task Rules`, `_Wave3 Event Log`, `_Wave3 Daily Narrative`, `_Wave3 Review Flags`, `_Wave3 Build Audit`) |
| Client-Facing Sheets | 84 |

### Desktop Excel COM Open Proof

| Check | Result |
|-------|--------|
| Excel launched | PASS |
| Workbook opened | PASS (8.401s) |
| Repair prompt detected | NO |
| Corruption warning | NO |
| Protected view | NO |
| Sheets loaded | 89/89 |
| Close clean | PASS |
| Quit clean | PASS |
| **Overall** | **PASS** |

### OneDrive Staging

| Property | Value |
|----------|-------|
| Staged to | `C:\Users\Cheex\OneDrive\Documents\Wave3_Field_Proof\` |
| OneDrive sync client | Running (PID 18512) |
| Excel for Web URL | `https://onedrive.live.com/edit.aspx?resid=...` (requires manual verification after sync) |

---

## Artifact 2: Attendance Checkpoint

| Property | Value |
|----------|-------|
| File | `Active_Roster_Log_ReviewQueue_CF_2026-07-12_Wave3_Attendance_Checkpoint.xlsx` |
| Size | 5,200,547 bytes |
| Sheets | 79 |
| Active Sheet | Live - July 2026 |

### Desktop Excel COM Open Proof

| Check | Result |
|-------|--------|
| Excel launched | PASS |
| Workbook opened | PASS |
| Repair prompt detected | NO |
| Corruption warning | NO |
| Protected view | NO |
| Sheets loaded | 79/79 |
| Close clean | PASS |
| Quit clean | PASS |
| **Overall** | **PASS** |

### OneDrive Staging

| Property | Value |
|----------|-------|
| Staged to | `C:\Users\Cheex\OneDrive\Documents\Wave3_Field_Proof\` |
| OneDrive sync client | Running |

---

## Structural Validator Baseline

Ran `tools/validate_workbook_structure.py` against both artifacts:

| Metric | Checkpoint | Final |
|--------|-----------|-------|
| openpyxl open | OK | OK |
| ZIP parts | 96 | 126 |
| Sheet count | 79 | 89 |
| Formula count | 267,425 | 267,425 |
| Error tokens | 0 | 0 |
| Forbidden tokens | 0 | 0 |
| calcChain | present | present |

### Diff: Final vs Checkpoint

| Metric | Value |
|--------|-------|
| New sheets added | 10 (5 client-facing Wave3 billing + 5 private `_Wave3` sheets) |
| ZIP parts added | 30 |
| Size increase | 25,482 bytes |
| Forbidden formula count diff | 0 |
| Private sheet count diff | +5 |

---

## Proof Classification

| Proof Type | Achieved | Notes |
|------------|----------|-------|
| Structural validator (openpyxl) | YES | Both artifacts pass openpyxl open, 0 errors |
| Desktop Excel COM open | YES | Both artifacts open without repair/corruption/protected-view |
| Excel for Web | STAGED | Files in OneDrive; manual browser verification required |
| Operator acceptance | PENDING | Requires manual operator confirmation |

**Proof level achieved:** Movement or behavior observed proof (desktop Excel COM).
**Proof ceiling:** Cannot claim Excel for Web proof or operator acceptance without manual verification.

---

## Known Gaps

| Gap | Impact | Mitigation |
|-----|--------|------------|
| Excel for Web not automated | Cannot claim Web-open proof programmatically | Files staged in OneDrive for manual verification |
| No repair-prompt injection test | Cannot prove workbook survives corrupt environment | Out of scope for this sprint |
| COM `DisplayAlerts=False` suppresses dialogs | May mask benign alerts | Standard COM practice; repair/corruption detection via exception handling |
| OneDrive sync latency | Web proof may lag | Documented sync status; manual check required |

---

## Files Produced

| File | Path | Committed |
|------|------|-----------|
| Desktop Excel proof (final) | `reports/field-open-proof/desktop_excel_open_proof.json` | Pending |
| Desktop Excel proof (checkpoint) | `reports/field-open-proof/desktop_excel_open_proof_checkpoint.json` | Pending |
| Structural baseline | `reports/field-open-proof/structural_baseline.json` | Pending |
| Structural baseline (MD) | `reports/field-open-proof/structural_baseline.md` | Pending |
| COM proof script (final) | `scripts/field-open-desktop-excel.py` | Pending |
| COM proof script (checkpoint) | `scripts/field-open-desktop-excel-checkpoint.py` | Pending |
| This report | `reports/field-open-proof/FIELD_OPEN_PROOF_REPORT.md` | Pending |
