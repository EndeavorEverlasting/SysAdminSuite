
$repoGuess = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $repoGuess 'scripts/SasNetworkGuard.psm1'))) {
    $repoGuess = Split-Path -Parent $repoGuess
}
$networkGuardModule = Join-Path $repoGuess 'scripts/SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $networkGuardModule)) {
    throw "Missing shared network guard module: $networkGuardModule"
}
Import-Module $networkGuardModule -Force
$skipNetworkGuard = $false
if ((Get-Variable -Name AllowFixtures -Scope Local -ErrorAction SilentlyContinue) -and $AllowFixtures) { $skipNetworkGuard = $true }
if ((Get-Variable -Name DryRun -Scope Local -ErrorAction SilentlyContinue) -and $DryRun) { $skipNetworkGuard = $true }
if (-not $skipNetworkGuard) { Assert-SasNorthwellWifi }
#
# .SYNOPSIS
# Runs a tracked installer in dry-run or local execution mode for evidence-oriented install workflows.
#
# .DESCRIPTION
# Invoke-TrackedInstall resolves installer metadata from Config/sources.yaml when possible and/or
# explicit parameter overrides, builds the command, and optionally executes it locally.
#
# This command is designed for Registry Install Diff pipeline orchestration where installer activity
# must be tracked and exported as structured evidence. This script does not edit registry values,
# does not capture registry snapshots, and does not perform registry diffs.
#>
[CmdletBinding()]
param(
    [string]$SoftwareId,
    [string]$SourceConfigPath = 'Config/sources.yaml',
    [string]$Target = 'localhost',
    [switch]$DryRun,
    [string]$InstallerPath,
    [ValidateSet('exe','msi','msix','batch','powershell','unknown')]
    [string]$InstallerType,
    [string]$SilentArgs,
    [string]$OutputPath,
    [string]$LogPath
)

function Write-TrackedInstallLog {
    param([string]$Message)
    if (-not $script:LogPath) { return }
    $dir = Split-Path -Path $script:LogPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    "$(Get-Date -Format o) $Message" | Add-Content -Path $script:LogPath
}

function Read-SourcesYaml {
    param([string]$Path)

    $result = [ordered]@{
        Success = $false
        Reason = $null
        Entry = $null
        Key = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Reason = 'SOURCE_CONFIG_NOT_FOUND'
        return $result
    }

    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        $result.Reason = 'YAML_PARSER_UNAVAILABLE'
        return $result
    }

    try {
        $yamlData = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml
    } catch {
        $result.Reason = 'SOURCE_CONFIG_PARSE_FAILED'
        return $result
    }

    $apps = @()
    if ($yamlData -and $yamlData.apps) { $apps = @($yamlData.apps) }

    if (-not $apps -or $apps.Count -eq 0) {
        $result.Reason = 'SOURCE_CONFIG_SHAPE_UNSUPPORTED'
        return $result
    }

    $match = $apps | Where-Object {
        ($_.software_id -eq $SoftwareId) -or
        ($_.id -eq $SoftwareId) -or
        ($_.name -eq $SoftwareId) -or
        ($_.display_name -eq $SoftwareId)
    } | Select-Object -First 1

    if (-not $match) {
        $result.Reason = 'SOFTWARE_ID_NOT_FOUND'
        return $result
    }

    $result.Success = $true
    $result.Entry = $match
    $result.Key = if ($match.software_id) { $match.software_id } elseif ($match.id) { $match.id } elseif ($match.name) { $match.name } else { $SoftwareId }
    return $result
}

$runId = [guid]::NewGuid().Guid
$startedAt = Get-Date
$status = 'NotStarted'
$errors = New-Object System.Collections.Generic.List[string]
$mode = if ($DryRun) { 'DryRun' } else { 'Execute' }

$installer = [ordered]@{
    installer_path = $InstallerPath
    installer_type = $InstallerType
    silent_args = $SilentArgs
    source_config_path = $SourceConfigPath
    source_config_key = $null
    resolved_from_sources_yaml = $false
    expected_registry_keys = @()
    expected_files = @()
    requires_reboot = $false
    command = $null
    command_args = $null
}

if ($SoftwareId) {
    $sourceResult = Read-SourcesYaml -Path $SourceConfigPath
    if ($sourceResult.Success) {
        $entry = $sourceResult.Entry
        $installer.source_config_key = $sourceResult.Key
        $installer.resolved_from_sources_yaml = $true

        if (-not $installer.installer_path) { $installer.installer_path = if ($entry.installer_path) { $entry.installer_path } else { $entry.path } }
        if (-not $installer.installer_type) { $installer.installer_type = if ($entry.installer_type) { $entry.installer_type } else { $entry.type } }
        if (-not $installer.silent_args) { $installer.silent_args = if ($entry.silent_args) { $entry.silent_args } else { $entry.arguments } }

        if ($entry.expected_registry_keys) { $installer.expected_registry_keys = @($entry.expected_registry_keys) }
        elseif ($entry.detect_type -eq 'regkey' -and $entry.detect_value) { $installer.expected_registry_keys = @($entry.detect_value) }

        if ($entry.expected_files) { $installer.expected_files = @($entry.expected_files) }
        elseif ($entry.detect_type -eq 'file' -and $entry.detect_value) { $installer.expected_files = @($entry.detect_value) }

        if ($null -ne $entry.requires_reboot) { $installer.requires_reboot = [bool]$entry.requires_reboot }
    } else {
        $errors.Add($sourceResult.Reason)
    }
}

if (-not $installer.installer_type) {
    if ($installer.installer_path) {
        switch -Regex ($installer.installer_path.ToLowerInvariant()) {
            '\.msi$' { $installer.installer_type = 'msi'; break }
            '\.msix$' { $installer.installer_type = 'msix'; break }
            '\.ps1$' { $installer.installer_type = 'powershell'; break }
            '\.(bat|cmd)$' { $installer.installer_type = 'batch'; break }
            '\.exe$' { $installer.installer_type = 'exe'; break }
            default { $installer.installer_type = 'unknown' }
        }
    } else {
        $installer.installer_type = 'unknown'
    }
}

$targetNormalized = $Target.ToLowerInvariant()
if ($targetNormalized -notin @('localhost','127.0.0.1','::1',$env:COMPUTERNAME.ToLowerInvariant())) {
    $status = 'Unsupported'
    $errors.Add('RemoteInstallNotImplemented')
}

switch ($installer.installer_type) {
    'msi' {
        $installer.command = 'msiexec.exe'
        $installer.command_args = "/i `"$($installer.installer_path)`" $($installer.silent_args)".Trim()
    }
    'powershell' {
        $installer.command = 'powershell.exe'
        $installer.command_args = "-NoProfile -ExecutionPolicy Bypass -File `"$($installer.installer_path)`" $($installer.silent_args)".Trim()
    }
    'batch' {
        $installer.command = 'cmd.exe'
        $installer.command_args = "/c `"$($installer.installer_path)`" $($installer.silent_args)".Trim()
    }
    default {
        $installer.command = $installer.installer_path
        $installer.command_args = $installer.silent_args
    }
}

if ($DryRun -and $status -eq 'NotStarted') {
    $status = 'DryRun'
}

$exitCode = $null
if (-not $DryRun -and $status -eq 'NotStarted') {
    if (-not $installer.installer_path) {
        $status = 'Failed'
        $errors.Add('INSTALLER_PATH_REQUIRED_FOR_EXECUTION')
    } elseif (-not (Test-Path -LiteralPath $installer.installer_path)) {
        $status = 'Failed'
        $errors.Add('INSTALLER_PATH_NOT_FOUND')
    } elseif ($installer.installer_type -eq 'unknown') {
        $status = 'Unsupported'
        $errors.Add('UNKNOWN_INSTALLER_TYPE_EXECUTION_NOT_ALLOWED')
    } else {
        $status = 'Started'
        Write-TrackedInstallLog "Starting installer command: $($installer.command) $($installer.command_args)"
        try {
            $proc = Start-Process -FilePath $installer.command -ArgumentList $installer.command_args -Wait -PassThru -NoNewWindow -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -RedirectStandardError ([System.IO.Path]::GetTempFileName())
            $exitCode = $proc.ExitCode
            if ($exitCode -eq 0) {
                $status = 'Succeeded'
            } else {
                $status = 'Failed'
                $errors.Add("INSTALLER_EXIT_CODE_$exitCode")
            }
        } catch {
            $status = 'Failed'
            $errors.Add('INSTALLER_EXECUTION_ERROR')
            $errors.Add($_.Exception.Message)
        }
    }
}

$endedAt = Get-Date
$duration = [int][Math]::Round((New-TimeSpan -Start $startedAt -End $endedAt).TotalMilliseconds)
Write-TrackedInstallLog "Finished with status=$status exit_code=$exitCode duration_ms=$duration"

$result = [ordered]@{
    schema_version = '1.0.0'
    run_id = $runId
    software_id = $SoftwareId
    target = $Target
    mode = $mode
    dry_run = [bool]$DryRun
    installer = $installer
    started_at = $startedAt.ToString('o')
    ended_at = $endedAt.ToString('o')
    duration_ms = $duration
    exit_code = $exitCode
    status = $status
    log_path = $LogPath
    errors = @($errors)
    output_path = $OutputPath
}

if ($OutputPath) {
    $outDir = Split-Path -Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath
}

$result
