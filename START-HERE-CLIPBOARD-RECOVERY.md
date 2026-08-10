# START HERE — Clipboard Recovery

Use the tracked root launcher **`Repair-Clipboard.cmd`** when copy/paste or clipboard history appears stuck on a Windows workstation.

## Technician action

1. Double-click `Repair-Clipboard.cmd`.
2. Allow it to finish.
3. A `PASS` means SysAdminSuite restarted the current user's Clipboard User Service, cleared the clipboard, and successfully wrote/read a verification value.
4. A `FAIL` means the clipboard did not return round-trip proof. Preserve the displayed evidence path for escalation.

## Evidence captured before reset

The PowerShell engine records lightweight local evidence under:

`%LOCALAPPDATA%\SysAdminSuite\field-runs\clipboard\<timestamp>\`

The summary includes the clipboard sequence number, the current `cbdhsvc_*` service instance(s), and—when Windows reports an open clipboard window—the HWND, PID, process name, and window title associated with it.

Runtime evidence is local diagnostic output and must not be committed to the repository.

## Scope

This workflow repairs the clipboard for the current interactive Windows user. It does not reboot the workstation, terminate arbitrary applications, change policy, or modify unrelated SysAdminSuite deployment settings.
