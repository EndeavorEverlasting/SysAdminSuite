@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Windows interactive-user launcher. No service restart or cross-app audio mutation.
set "ACTION=Inspect"
set "PAUSE_ON_EXIT=0"
if "%~1"=="" set "PAUSE_ON_EXIT=1"
if /I "%~1"=="Inspect" set "ACTION=Inspect"
if /I "%~1"=="Repair" set "ACTION=Repair"
if not "%~1"=="" if /I not "%~1"=="Inspect" if /I not "%~1"=="Repair" goto usage
if not "%~2"=="" goto usage

if not exist "%~dp0scripts\Confirm-SasChromeAudioCheckout.ps1" (
    echo CHROME_AUDIO_LAUNCH_BLOCKED: freshness guard is missing.
    set "EXIT_CODE=2"
    goto finish
)
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\Confirm-SasChromeAudioCheckout.ps1"
if errorlevel 1 (
    echo CHROME_AUDIO_LAUNCH_BLOCKED: canonical repository or network freshness unproved.
    set "EXIT_CODE=2"
    goto finish
)
if /I "%ACTION%"=="Repair" echo Explicit Repair: only existing ACTIVE chrome.exe sessions may be unmuted or restored from zero to 25 percent.
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasChromeAudioRecovery.ps1" -Action "%ACTION%"
set "EXIT_CODE=%ERRORLEVEL%"
goto finish

:usage
echo Usage: Recover-ChromeAudio.cmd [Inspect^|Repair]
set "EXIT_CODE=2"
:finish
if "%PAUSE_ON_EXIT%"=="1" pause
exit /b %EXIT_CODE%
