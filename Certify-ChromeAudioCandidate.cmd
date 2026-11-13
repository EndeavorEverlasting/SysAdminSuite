@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem P08 candidate-only lane: pinned immutable branch/worktree, not a production launcher.
if "%~1"=="" goto usage
set "APPROVED_COMMIT=%~1"
set "ACTION=Inspect"
if /I "%~2"=="Repair" set "ACTION=Repair"
if not "%~2"=="" if /I not "%~2"=="Inspect" if /I not "%~2"=="Repair" goto usage
if not "%~3"=="" goto usage

powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\Confirm-SasChromeAudioCandidate.ps1" -ApprovedCommit "%APPROVED_COMMIT%"
if errorlevel 1 (
  echo CANDIDATE_AUDIO_CERT_BLOCKED: candidate worktree/commit is not approved.
  exit /b 2
)
if /I "%ACTION%"=="Repair" echo Candidate Repair requires explicit operator approval; changes only existing ACTIVE Chrome sessions.
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasChromeAudioRecovery.ps1" -Action "%ACTION%"
exit /b %ERRORLEVEL%

:usage
echo Usage: Certify-ChromeAudioCandidate.cmd APPROVED_40_HEX_SHA [Inspect^|Repair]
exit /b 2
