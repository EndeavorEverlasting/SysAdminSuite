<#
.SYNOPSIS
    Orchestrates the Windows WezTerm configuration for the SysAdminSuite developer workstation.
.DESCRIPTION
    Renders, plans, applies, or rolls back the Windows-native WezTerm profile configuration.
    Fails closed: requires -AllowTargetMutation to make changes.
.PARAMETER ProfilePath
    Path to the workstation profile sample JSON file.
.PARAMETER InventoryFixturePath
    Optional path to a mock inventory JSON file (for testing and CI).
.PARAMETER UserConfigDir
    Target directory for the WezTerm configuration files (defaults to $env:USERPROFILE).
.PARAMETER Action
    The action to perform: Plan (default), Apply, or Rollback.
.PARAMETER AllowTargetMutation
    Switch authorizing mutations on the target file system. Required for Apply and Rollback actions.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $false)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $false)]
    [string]$InventoryFixturePath,

    [Parameter(Mandatory = $false)]
    [string]$UserConfigDir,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Plan', 'Apply', 'Rollback')]
    [string]$Action = 'Plan',

    [Parameter(Mandatory = $false)]
    [switch]$AllowTargetMutation
)

$ErrorActionPreference = "Stop"

# Get repository root
$script:repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $script:repoRoot "targets/README.md"))) {
    # Fallback if PSScriptRoot is not scripts/ directory
    $script:repoRoot = (Get-Location).Path
}

# Defaults
$resolvedProfilePath = if ($ProfilePath) { $ProfilePath } else { Join-Path $script:repoRoot "Config/developer-workstation-profile.sample.json" }
$resolvedUserConfigDir = if ($UserConfigDir) { $UserConfigDir } else { $env:USERPROFILE }
$weztermLuaPath = Join-Path $resolvedUserConfigDir ".wezterm.lua"
$sasLuaPath = Join-Path $resolvedUserConfigDir ".wezterm-sysadminsuite.lua"
$backupDir = Join-Path $script:repoRoot "logs/wezterm-backups"

$managedBlockStart = "-- BEGIN SYSADMINSUITE MANAGED BLOCK"
$managedBlockEnd = "-- END SYSADMINSUITE MANAGED BLOCK"

# Helper for file hashes
function Get-SafeFileHash {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    }
    return $null
}

# Helper to load profile
function Load-Profile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -Raw -Path $Path | ConvertFrom-Json
    }
    return $null
}

# Helper to load inventory
function Load-Inventory {
    param([string]$FixturePath)
    if ($FixturePath) {
        if (Test-Path -LiteralPath $FixturePath) {
            return Get-Content -Raw -Path $FixturePath | ConvertFrom-Json
        }
        throw "Inventory fixture path not found: $FixturePath"
    }
    # Live execution check
    $invScript = Join-Path $PSScriptRoot "Get-SasDeveloperWorkstationInventory.ps1"
    if (Test-Path $invScript) {
        $invResult = & $invScript
        return $invResult.inventory
    }
    return $null
}

# Helper to compute Lua include block
function Get-IncludeBlock {
    return @"
$managedBlockStart
local sas_path = (os.getenv('USERPROFILE') or os.getenv('HOME')) .. '/.wezterm-sysadminsuite.lua'
local sas_file = io.open(sas_path, 'r')
if sas_file then
    sas_file:close()
    local sas_func = dofile(sas_path)
    if type(sas_func) == 'function' then
        if not config then config = {} end
        sas_func(config)
    end
end
$managedBlockEnd
"@
}

# Helper to update Lua content safely
function Update-LuaContent {
    param(
        [string]$Content,
        [string]$IncludeBlock
    )
    $hasBlock = $Content.Contains($managedBlockStart)
    if ($hasBlock) {
        $pattern = "(?s)" + [regex]::Escape($managedBlockStart) + ".*?" + [regex]::Escape($managedBlockEnd)
        return [regex]::Replace($Content, $pattern, $IncludeBlock)
    }

    # Find the position of 'return'
    $matches = [regex]::Matches($Content, '(?m)^\s*return\s+\w+\s*$')
    if ($matches.Count -gt 0) {
        $lastMatch = $matches[$matches.Count - 1]
        $index = $lastMatch.Index
        return $Content.Substring(0, $index) + $IncludeBlock + "`n`n" + $Content.Substring($index)
    }

    $matches = [regex]::Matches($Content, '(?m)^\s*return\s*')
    if ($matches.Count -gt 0) {
        $lastMatch = $matches[$matches.Count - 1]
        $index = $lastMatch.Index
        return $Content.Substring(0, $index) + $IncludeBlock + "`n`n" + $Content.Substring($index)
    }

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return @"
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

$IncludeBlock

return config
"@
    }

    return $Content + "`n`n" + $IncludeBlock
}

# Render dynamic configuration
$profile = Load-Profile -Path $resolvedProfilePath
$inventory = Load-Inventory -FixturePath $InventoryFixturePath

# Shell resolution (PowerShell 7 vs Windows PowerShell)
$shellPath = "powershell.exe"
if ($inventory -and $inventory.checks -and $inventory.checks.shell) {
    if ($inventory.checks.shell.path -match 'pwsh') {
        $shellPath = "pwsh.exe"
    }
} else {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        $shellPath = "pwsh.exe"
    }
}

# OpenCode/AGY/Goose detection
$launchMenuEntries = @()
$reqAgents = @("opencode", "agy", "goose")
if ($profile -and $profile.agent_switchboard -and $profile.agent_switchboard.required_agents) {
    $reqAgents = $profile.agent_switchboard.required_agents
}

foreach ($agent in $reqAgents) {
    $isAvailable = $false
    if ($inventory -and $inventory.checks -and $inventory.checks.agent_commands) {
        $agentCheck = $inventory.checks.agent_commands | Where-Object { $_.agent_id -eq $agent }
        if ($agentCheck -and $agentCheck.status -eq 'PASS') {
            $isAvailable = $true
        }
    } else {
        if (Get-Command $agent -ErrorAction SilentlyContinue) {
            $isAvailable = $true
        }
    }

    if ($isAvailable) {
        $launchMenuEntries += "    table.insert(launch_menu, {`n        name = '$agent',`n        args = { '$shellPath', '-NoExit', '-Command', '$agent' },`n    })"
    }
}

# WSL detection & enabled check
$isWslProfileEnabled = $false
if ($profile -and $profile.terminal -and $profile.terminal.execution_profiles) {
    $wslEp = $profile.terminal.execution_profiles | Where-Object { $_.environment -eq 'wsl' }
    if ($wslEp -and $wslEp.enabled) {
        $isWslProfileEnabled = $true
    }
}

$isWslDetected = $false
$wslDistros = @()
if ($inventory -and $inventory.checks -and $inventory.checks.wsl) {
    if ($inventory.checks.wsl.status -eq 'PASS') {
        $isWslDetected = $true
        if ($inventory.checks.wsl.distributions) {
            $wslDistros = $inventory.checks.wsl.distributions
        }
    }
} else {
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $isWslDetected = $true
        $wslOutput = wsl --list --verbose 2>$null
        if ($wslOutput) {
            foreach ($line in $wslOutput) {
                $trimmed = "$line".Trim() -replace '[\x00-\x1F]', ''
                if ($trimmed -match '^\*?\s*(\S+)') {
                    $distName = $Matches[1]
                    if ($distName -and $distName -ne "NAME" -and $distName -ne "---") {
                        $wslDistros += @{ name = $distName; status = "PASS" }
                    }
                }
            }
        }
    }
}

if ($isWslProfileEnabled -and $isWslDetected -and $wslDistros.Count -gt 0) {
    foreach ($dist in $wslDistros) {
        $distName = $dist.name
        $launchMenuEntries += "    table.insert(launch_menu, {`n        name = 'wsl-$distName',`n        args = { 'wsl.exe', '-d', '$distName', '-e', 'tmux' },`n    })"
    }
}

# Load template
$templatePath = Join-Path $script:repoRoot "Config/wezterm-windows.lua.template"
if (-not (Test-Path $templatePath)) {
    throw "WezTerm Windows Lua template not found at $templatePath"
}
$templateContent = Get-Content -Raw -Path $templatePath
$renderedSasLua = $templateContent.Replace('@SHELL_PATH@', $shellPath)
$renderedSasLua = $renderedSasLua.Replace('@LAUNCH_MENU_ENTRIES@', ($launchMenuEntries -join "`n`n"))

# Generate plan
$origSasHash = Get-SafeFileHash -Path $sasLuaPath
$origWeztermHash = Get-SafeFileHash -Path $weztermLuaPath

$origWeztermContent = ""
if (Test-Path $weztermLuaPath) {
    $origWeztermContent = Get-Content -Raw -Path $weztermLuaPath
}

$includeBlock = Get-IncludeBlock
$plannedWeztermContent = Update-LuaContent -Content $origWeztermContent -IncludeBlock $includeBlock

$plan = [pscustomobject]@{
    action                = $Action
    allow_target_mutation = $AllowTargetMutation
    wezterm_lua_path      = $weztermLuaPath
    wezterm_lua_exists    = Test-Path $weztermLuaPath
    sas_lua_path          = $sasLuaPath
    sas_lua_exists        = Test-Path $sasLuaPath
    original_wezterm_hash = $origWeztermHash
    original_sas_hash     = $origSasHash
    planned_shell_path    = $shellPath
    planned_agent_count   = $launchMenuEntries.Count
}

# Render planned changes to stdout in Plan mode
if ($Action -eq 'Plan') {
    Write-Output "SYSADMINSUITE WEZTERM CONFIGURATION PLAN"
    Write-Output "========================================"
    Write-Output "Action: Plan (WhatIf)"
    Write-Output "WezTerm path: $weztermLuaPath (Exists: $($plan.wezterm_lua_exists))"
    Write-Output "SysAdminSuite include: $sasLuaPath (Exists: $($plan.sas_lua_exists))"
    Write-Output "Preferred Shell: $shellPath"
    Write-Output "Agent profiles registered: $($launchMenuEntries.Count)"
    Write-Output "WSL integrations enabled: $isWslProfileEnabled (Detected: $isWslDetected)"
    Write-Output ""
    Write-Output "--- Planned .wezterm-sysadminsuite.lua ---"
    Write-Output $renderedSasLua
    Write-Output ""
    Write-Output "--- Planned .wezterm.lua ---"
    Write-Output $plannedWeztermContent
    return @{ plan = $plan; success = $true }
}

# Verify apply validation
if ($Action -eq 'Apply') {
    if (-not $AllowTargetMutation) {
        Write-Warning "Apply action requires -AllowTargetMutation. Fails closed: running Plan instead."
        return @{ plan = $plan; success = $false; error = "AllowTargetMutation not authorized" }
    }

    if (-not $PSCmdlet.ShouldProcess($weztermLuaPath, "Apply managed WezTerm Windows configuration")) {
        Write-Warning "Apply skipped by user."
        return @{ plan = $plan; success = $false; error = "User skipped" }
    }

    # Execute Backup
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $backupWeztermPath = Join-Path $backupDir "wezterm.lua.$timestamp.bak"
    $backupSasPath = Join-Path $backupDir "wezterm-sysadminsuite.lua.$timestamp.bak"

    if (Test-Path $weztermLuaPath) {
        Copy-Item -LiteralPath $weztermLuaPath -Destination $backupWeztermPath -Force
    }
    if (Test-Path $sasLuaPath) {
        Copy-Item -LiteralPath $sasLuaPath -Destination $backupSasPath -Force
    }

    # Write target files
    [System.IO.File]::WriteAllText($sasLuaPath, $renderedSasLua, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($weztermLuaPath, $plannedWeztermContent, [System.Text.Encoding]::UTF8)

    # Perform Lua syntax validation if wezterm is present
    $weztermVerified = $false
    if (Get-Command wezterm -ErrorAction SilentlyContinue) {
        # Since wezterm show-config parses the live user config, we can check its exit code
        $checkCmd = "wezterm show-config"
        $validateOutput = Invoke-Expression "$checkCmd 2>&1"
        if ($LASTEXITCODE -eq 0) {
            $weztermVerified = $true
        }
    }

    $finalWeztermHash = Get-SafeFileHash -Path $weztermLuaPath
    $finalSasHash = Get-SafeFileHash -Path $sasLuaPath

    Write-Output "SYSADMINSUITE WEZTERM CONFIGURATION APPLIED"
    Write-Output "Backup saved to: $backupWeztermPath"
    Write-Output "WezTerm Config Hash: $finalWeztermHash"
    Write-Output "Sas Config Hash: $finalSasHash"

    return @{
        success = $true
        original_wezterm_hash = $origWeztermHash
        final_wezterm_hash = $finalWeztermHash
        backup_path = $backupWeztermPath
    }
}

# Verify rollback validation
if ($Action -eq 'Rollback') {
    if (-not $AllowTargetMutation) {
        Write-Warning "Rollback action requires -AllowTargetMutation. Fails closed."
        return @{ plan = $plan; success = $false; error = "AllowTargetMutation not authorized" }
    }

    if (-not $PSCmdlet.ShouldProcess($weztermLuaPath, "Rollback WezTerm Windows configuration to last backup or default")) {
        Write-Warning "Rollback skipped by user."
        return @{ plan = $plan; success = $false; error = "User skipped" }
    }

    # Find latest backup
    $latestWeztermBak = Get-ChildItem -Path $backupDir -Filter "wezterm.lua.*.bak" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $latestSasBak = Get-ChildItem -Path $backupDir -Filter "wezterm-sysadminsuite.lua.*.bak" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestWeztermBak) {
        Copy-Item -LiteralPath $latestWeztermBak.FullName -Destination $weztermLuaPath -Force
        Write-Output "Restored .wezterm.lua from backup: $($latestWeztermBak.Name)"
    } else {
        # Cleanly remove managed block if no backup is available
        if (Test-Path $weztermLuaPath) {
            $currentContent = Get-Content -Raw -Path $weztermLuaPath
            if ($currentContent.Contains($managedBlockStart)) {
                $pattern = "(?s)" + [regex]::Escape($managedBlockStart) + ".*?" + [regex]::Escape($managedBlockEnd)
                $cleanedContent = [regex]::Replace($currentContent, $pattern, "").Trim()
                if ([string]::IsNullOrWhiteSpace($cleanedContent)) {
                    Remove-Item -LiteralPath $weztermLuaPath -Force
                    Write-Output "Removed empty .wezterm.lua"
                } else {
                    [System.IO.File]::WriteAllText($weztermLuaPath, $cleanedContent, [System.Text.Encoding]::UTF8)
                    Write-Output "Cleaned SysAdminSuite block from .wezterm.lua"
                }
            }
        }
    }

    if ($latestSasBak) {
        Copy-Item -LiteralPath $latestSasBak.FullName -Destination $sasLuaPath -Force
        Write-Output "Restored .wezterm-sysadminsuite.lua from backup: $($latestSasBak.Name)"
    } else {
        if (Test-Path $sasLuaPath) {
            Remove-Item -LiteralPath $sasLuaPath -Force
            Write-Output "Removed .wezterm-sysadminsuite.lua"
        }
    }

    return @{
        success = $true
        restored_from_backup = [bool]($latestWeztermBak)
    }
}
