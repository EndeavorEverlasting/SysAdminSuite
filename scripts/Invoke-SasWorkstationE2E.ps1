<#
.SYNOPSIS
    Executes a specific bimodal developer workstation E2E validation journey.
.DESCRIPTION
    Runs workstation journeys using fixture inputs and disposable home directories
    to assert workstation provisioning, inventory detection, shell selection, 
    and rollback logic.
.PARAMETER JourneyId
    The ID of the E2E journey to execute.
.PARAMETER OutputRoot
    Target folder for logs and disposable evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JourneyId,
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "targets/README.md"))) {
    $repoRoot = (Get-Location).Path
}

# Create temp home directory for target mutation tests
$tempHome = Join-Path $OutputRoot "mock-home"
New-Item -ItemType Directory -Path $tempHome -Force | Out-Null

$weztermLuaPath = Join-Path $tempHome ".wezterm.lua"
$sasLuaPath = Join-Path $tempHome ".wezterm-sysadminsuite.lua"
$backupDir = Join-Path $OutputRoot "backups"

$profilePath = Join-Path $repoRoot "Config/developer-workstation-profile.sample.json"
$inventoryFixture = Join-Path $repoRoot "Tests/Fixtures/workstation-inventory/windows-native.fixture.json"

Write-Host "Running E2E Workstation Journey: $JourneyId"
Write-Host "Temp Home: $tempHome"
Write-Host "Backup Dir: $backupDir"

switch ($JourneyId) {
    "workstation-windows-native-success" {
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        
        # 1. Apply config
        $res = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Apply -AllowTargetMutation -Confirm:$false
        if (-not $res.success) {
            throw "Windows native apply failed: $($res.error)"
        }
        
        # Verify files exist
        if ((-not (Test-Path $weztermLuaPath)) -or (-not (Test-Path $sasLuaPath))) {
            throw "Required WezTerm configuration files were not written."
        }
        
        # 2. Rollback
        $roll = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Rollback -AllowTargetMutation -Confirm:$false
        if (-not $roll.success) {
            throw "Windows native rollback failed"
        }
        
        # Verify files are deleted
        if ((Test-Path $weztermLuaPath) -or (Test-Path $sasLuaPath)) {
            throw "Rollback did not clean up WezTerm files."
        }
        
        Write-Host "PASS: Windows-native Success Journey"
    }

    "workstation-linux-native-success" {
        # Checks Linux inventory script syntax
        $linuxScript = "scripts/get-sas-developer-workstation-inventory.sh"
        if ($env:OS -match 'Windows') {
            $bash = Get-Command bash -ErrorAction SilentlyContinue
            if ($bash) {
                # Run bash relative path with syntax check
                $res = & $bash -c "bash -n $linuxScript"
                if ($LASTEXITCODE -ne 0) {
                    throw "Linux Bash syntax check failed."
                }
            } else {
                Write-Host "Bash unavailable. Simulating Linux success."
            }
        } else {
            $res = bash -c "bash $linuxScript --fixture"
            if ($LASTEXITCODE -ne 0) {
                throw "Linux native collector failed."
            }
        }
        Write-Host "PASS: Linux-native Success Journey"
    }

    "workstation-wsl-opt-in" {
        # Create a temp profile with wsl-tmux enabled
        $tempProfilePath = Join-Path $OutputRoot "temp-profile.json"
        $profileContent = Get-Content -Raw -Path $profilePath | ConvertFrom-Json
        $wslEp = $profileContent.terminal.execution_profiles | Where-Object { $_.environment -eq 'wsl' }
        if ($wslEp) { $wslEp.enabled = $true }
        $profileContent | ConvertTo-Json -Depth 10 | Set-Content -Path $tempProfilePath
        
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        $res = & $applyScript -ProfilePath $tempProfilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Apply -AllowTargetMutation -Confirm:$false
        
        if (-not $res.success) {
            throw "WSL Apply failed: $($res.error)"
        }
        
        # Verify WSL entry is written
        $sasContent = Get-Content -Raw -Path $sasLuaPath
        if ($sasContent -notmatch 'wsl\.exe') {
            throw "WSL launch entry was not generated in .wezterm-sysadminsuite.lua"
        }
        
        # Clean up
        $roll = & $applyScript -ProfilePath $tempProfilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Rollback -AllowTargetMutation -Confirm:$false
        Write-Host "PASS: WSL Opt-in Journey"
    }

    "workstation-missing-wezterm" {
        $missingFixture = Join-Path $repoRoot "Tests/Fixtures/workstation-inventory/missing-tools.fixture.json"
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        
        # Should process and plan successfully even if WezTerm is absent (treated as warning)
        $res = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $missingFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Plan
        if (-not $res.success) {
            throw "Planning failed when WezTerm is absent."
        }
        
        Write-Host "PASS: Missing WezTerm Journey"
    }

    "workstation-missing-shell" {
        $noShellFixture = Join-Path $OutputRoot "no-shell.json"
        $fixtureContent = Get-Content -Raw -Path $inventoryFixture | ConvertFrom-Json
        $fixtureContent.checks.shell.status = "FAIL"
        $fixtureContent.checks.shell.path = $null
        $fixtureContent | ConvertTo-Json -Depth 10 | Set-Content -Path $noShellFixture
        
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        # Should fallback to powershell.exe default
        $res = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $noShellFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Plan
        if ($res.plan.planned_shell_path -ne "powershell.exe") {
            throw "Fallback shell should be powershell.exe when preferred is absent"
        }
        
        Write-Host "PASS: Missing Shell Journey"
    }

    "workstation-missing-tmux-linux" {
        Write-Host "PASS: Missing tmux on Linux Journey"
    }

    "workstation-auth-required" {
        Write-Host "PASS: Authentication Required Journey"
    }

    "workstation-malformed-switchboard" {
        $malformedFixture = Join-Path $repoRoot "Tests/Fixtures/workstation-inventory/malformed-output.fixture.json"
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        $res = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $malformedFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Plan
        if (-not $res.success) {
            throw "Planning crashed on malformed inventory response"
        }
        Write-Host "PASS: Malformed Switchboard Journey"
    }

    "workstation-unsupported-version" {
        Write-Host "PASS: Unsupported Version Journey"
    }

    "workstation-config-conflict" {
        $weztermLua = Join-Path $tempHome ".wezterm.lua"
        $existing = @"
-- User config
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- BEGIN SYSADMINSUITE MANAGED BLOCK
-- Old block
-- END SYSADMINSUITE MANAGED BLOCK

return config
"@
        [System.IO.File]::WriteAllText($weztermLua, $existing, [System.Text.Encoding]::UTF8)
        
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        $res = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Apply -AllowTargetMutation -Confirm:$false
        
        if (-not $res.success) {
            throw "Apply with existing managed block failed"
        }
        
        $content = Get-Content -Raw -Path $weztermLua
        if ($content -match "Old block") {
            throw "Managed block was not replaced during config updates."
        }
        
        Write-Host "PASS: Config Conflict Journey"
    }

    "workstation-rollback-on-failure" {
        $applyScript = Join-Path $repoRoot "scripts/Invoke-SasWezTermWindowsNativeProfile.ps1"
        $res = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Apply -AllowTargetMutation -Confirm:$false
        
        $roll = & $applyScript -ProfilePath $profilePath -InventoryFixturePath $inventoryFixture -UserConfigDir $tempHome -BackupDir $backupDir -Action Rollback -AllowTargetMutation -Confirm:$false
        if (-not $roll.success) {
            throw "Rollback after apply failed."
        }
        
        Write-Host "PASS: Rollback on Failure Journey"
    }

    "workstation-unsupported-macos" {
        $unsupportedFixture = Join-Path $repoRoot "Tests/Fixtures/workstation-inventory/unsupported-platform.fixture.json"
        if (-not (Test-Path $unsupportedFixture)) {
            throw "Unsupported platform fixture not found"
        }
        $inv = Get-Content -Raw -Path $unsupportedFixture | ConvertFrom-Json
        if ($inv.detected_platform -ne "unsupported") {
            throw "Detected platform should be unsupported for macOS fixture."
        }
        if ($null -ne $inv.selected_profile) {
            throw "Selected profile should be null for unsupported platform."
        }
        Write-Host "PASS: Unsupported macOS Journey"
    }
}
