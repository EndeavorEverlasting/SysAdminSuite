@echo off
setlocal enabledelayedexpansion
title SysAdminSuite Dashboard

echo.
echo ==========================================
echo   SysAdminSuite Dashboard
echo ==========================================
echo.
echo Double-click launcher - no commands to memorize.
echo This opens the local dashboard and tutorial.
echo The first run may take a minute while Microsoft .NET dependencies
echo and the dashboard app are prepared.
echo No internet is required after the dashboard dependencies are installed.
echo.

set "ROOT=%~dp0"
cd /d "%ROOT%"
set "HEALTH_URL=http://127.0.0.1:5000/dashboard/"
set "UPDATE_HELPER=%ROOT%tools\update\Invoke-SysAdminSuiteUpdate.ps1"

if exist "%UPDATE_HELPER%" (
    set "SAS_UPDATE_STATE=current"
    set "SAS_UPDATE_MODE=check_only"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_HELPER%" -CheckOnly -Quiet
    set "UPDATE_RC=!errorlevel!"
    if "!UPDATE_RC!"=="10" (
        set "SAS_UPDATE_STATE=available"
        echo.
        echo A SysAdminSuite update is available.
        choice /C YN /N /M "Apply the update before opening the dashboard? [Y/N] "
        if "!errorlevel!"=="1" (
            set "SAS_UPDATE_MODE=applied"
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_HELPER%" -Apply -Approved
            if errorlevel 1 (
                echo.
                echo The update could not be applied automatically.
                echo Continuing with the current local copy.
                echo.
                set "SAS_UPDATE_MODE=apply_failed"
            ) else (
                echo.
                echo Update applied. Continuing with the dashboard.
                echo.
                set "SAS_UPDATE_STATE=current"
            )
        ) else (
            set "SAS_UPDATE_MODE=skipped"
            echo.
            echo Update skipped. Continuing with the current local copy.
            echo.
        )
    ) else if "!UPDATE_RC!"=="20" (
        set "SAS_UPDATE_STATE=manual_review"
        set "SAS_UPDATE_MODE=manual_review"
        echo.
        echo Update check needs manual review, so the dashboard will continue with the current local copy.
        echo.
    )
) else (
    set "SAS_UPDATE_STATE=unknown"
    set "SAS_UPDATE_MODE=unknown"
)

if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
    echo Packaged field release detected - dashboard app is already included.
    echo No build step is required on this machine.
    echo.
) else (
    echo Source checkout detected - the dashboard app may be prepared on first run.
    echo If Microsoft .NET 8 is missing, the launcher can download the official Microsoft installers
    echo and build the dashboard automatically.
    echo If downloads or administrator approval are blocked, ask for the packaged
    echo SysAdminSuite Dashboard field release instead.
    echo.
)

if not exist "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" (
    echo Could not find Launch-SysAdminSuiteDashboard.Host.bat.
    echo Make sure you are running this from the SysAdminSuite repo root.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Starting the dashboard host^.^.^.
echo If this is the first run, dependencies and the dashboard app will be prepared automatically now.
call "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" --no-browser
set "RC=%errorlevel%"

if "%RC%"=="2" (
    echo.
    echo The dashboard dependency download or verification could not complete.
    echo.
    echo The dashboard app could not be prepared on this machine.
    echo.
    echo This usually means Git Bash, curl, internet access, or Microsoft installer
    echo checksum verification was blocked.
    echo.
    echo Ask for the packaged SysAdminSuite Dashboard field release ^(pre-built host under app\bin^),
    echo or have IT/admin prepare this workstation.
    echo.
    echo Do not use CLI survey commands unless the dashboard or runbook gives you one.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

if not "%RC%"=="0" (
    echo.
    echo The dashboard app could not be prepared on this machine.
    echo.
    echo This usually means the Microsoft .NET install or dashboard build needs
    echo IT/admin approval, or the workstation blocks the required Microsoft download.
    echo.
    echo Ask for the packaged SysAdminSuite Dashboard field release ^(pre-built host under app\bin^),
    echo or have IT/admin prepare this workstation.
    echo.
    echo Do not use CLI survey commands unless the dashboard or runbook gives you one.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Waiting for the dashboard to be ready^.^.^.
set "HOST_UP=0"
for /L %%i in (1,1,20) do (
    if "!HOST_UP!"=="0" (
        curl.exe -s -o nul --max-time 2 "%HEALTH_URL%" >nul 2>nul && set "HOST_UP=1"
        if "!HOST_UP!"=="0" timeout /t 1 /nobreak >nul
    )
)

if not "!HOST_UP!"=="1" (
    echo.
    echo The dashboard host did not respond on http://127.0.0.1:5000 .
    echo.
    echo Ask for the packaged SysAdminSuite Dashboard release, or have IT/admin prepare this workstation.
    echo.
    echo Do not use CLI survey commands unless the dashboard or runbook gives you one.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Opening dashboard and Repo Setup tutorial in your browser...
start "" "http://127.0.0.1:5000/dashboard/?tutorial=setup"

echo.
echo If the page did not open, paste this into your browser:
echo   http://127.0.0.1:5000/dashboard/?tutorial=setup
echo.
echo A tray icon should appear. Right-click it for Open Dashboard, Copy URL, or Stop.
echo.
echo Press any key to close this window. The dashboard keeps running in the tray.
pause >nul
exit /b 0
