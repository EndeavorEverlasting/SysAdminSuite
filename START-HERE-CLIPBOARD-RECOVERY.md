# START HERE — Clipboard Recovery

Use the tracked root launcher **`Repair-Clipboard.cmd`** when copy/paste or clipboard history appears stuck on a Windows workstation.

This recovery is also registered as `windows.clipboard.repair` in [`Config/operator-recipes.json`](Config/operator-recipes.json), so the command remains discoverable without duplicating its implementation in notes or chat history.

## Technician action

1. Double-click `Repair-Clipboard.cmd`.
2. Allow it to finish.
3. A `PASS` means SysAdminSuite identified exactly one Clipboard User Service owned by the current Windows identity, restarted that service, cleared the clipboard, and successfully wrote/read a verification value.
4. A `FAIL` means one or more required recovery steps were not proven. Preserve the displayed evidence path for escalation.

The launcher prefers PowerShell 7 (`pwsh`) and falls back to Windows PowerShell (`powershell.exe`).

## Evidence captured before reset

The PowerShell engine records lightweight local evidence under:

`%LOCALAPPDATA%\SysAdminSuite\field-runs\clipboard\<timestamp>\`

The summary includes the clipboard sequence number, visible `cbdhsvc_*` service metadata, the selected current-user service, and—when Windows reports an open clipboard window—the HWND, PID, process name, and window title associated with it.

Optional process/service evidence collection is non-fatal; `summary.json` is written from a finalization path so a diagnostic collection problem does not silently erase the recovery result.

Runtime evidence is local diagnostic output and must not be committed to the repository.

## Scope

This workflow repairs the clipboard for the current interactive Windows user. It fails closed when it cannot identify exactly one `cbdhsvc_*` instance owned by that identity. It does not reboot the workstation, terminate arbitrary applications, change policy, or modify unrelated SysAdminSuite deployment settings.
