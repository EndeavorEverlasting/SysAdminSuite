@echo off
setlocal
rem Technician support workstation: show the reviewed QR; never reboot this support PC.
set "ROOT=%~dp0"
if not exist "%ROOT%configs\hotfix-commands\windows-setup-uefi-bios.json" (
  echo [ERROR] Windows Setup BIOS manifest missing from this SysAdminSuite checkout.
  exit /b 2
)
if not exist "%ROOT%Run-FieldHotfixesGui.cmd" (
  echo [ERROR] Canonical Field Hotfixes launcher unavailable.
  exit /b 2
)
call "%ROOT%Run-FieldHotfixesGui.cmd" -ManifestPath "%ROOT%configs\hotfix-commands\windows-setup-uefi-bios.json"
exit /b %ERRORLEVEL%
