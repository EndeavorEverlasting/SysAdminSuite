#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RunsRoot,

    [switch]$AllowNetworkActivity,

    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($RunsRoot)) { $RunsRoot = Join-Path $repoRoot 'runs' }
$RunsRoot = [IO.Path]::GetFullPath($RunsRoot)

if (-not (Test-Path -LiteralPath $RunsRoot -PathType Container)) {
    throw "Runs root not found: $RunsRoot"
}

$outer = Get-ChildItem -LiteralPath $RunsRoot -Directory -Filter 'autologon-s4u-deployment-*' -ErrorAction Stop |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $outer) { throw "No AutoLogon S4U deployment run found under $RunsRoot" }

$inner = Get-ChildItem -LiteralPath (Join-Path $outer.FullName 's4u') -Directory -Filter 'autologon-kerberos-s4u-*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $inner) { throw "Newest deployment run has no inner S4U run: $($outer.FullName)" }

$innerRunId = $inner.Name
$evidenceRoot = Join-Path $inner.FullName 'evidence'
$actionsRoot = Join-Path $inner.FullName 'actions'

function Read-JsonIfPresent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

$pilot = Read-JsonIfPresent -Path (Join-Path $inner.FullName 'autologon_kerberos_s4u_pilot_result.json')
$baseline = Read-JsonIfPresent -Path (Join-Path $evidenceRoot 'baseline_snapshot.json')
$after = Read-JsonIfPresent -Path (Join-Path $evidenceRoot 'after_snapshot.json')
$probeResult = Read-JsonIfPresent -Path (Join-Path $evidenceRoot 's4u_probe_result.json')
$installResult = Read-JsonIfPresent -Path (Join-Path $evidenceRoot 's4u_install_result.json')
$probeLifecycle = Read-JsonIfPresent -Path (Join-Path $evidenceRoot 's4u_probe_lifecycle.json')
$installLifecycle = Read-JsonIfPresent -Path (Join-Path $evidenceRoot 's4u_install_lifecycle.json')

$localActionNames = @()
if (Test-Path -LiteralPath $actionsRoot -PathType Container) {
    $localActionNames = @(Get-ChildItem -LiteralPath $actionsRoot -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}

$result = [ordered]@{
    schema_version = 'sas-interrupted-autologon-s4u-inspection/v1'
    target = $ComputerName
    outer_run = $outer.FullName
    inner_run = $inner.FullName
    inner_run_id = $innerRunId
    pilot_result_present = ($null -ne $pilot)
    pilot_classification = $(if ($pilot) { [string]$pilot.classification } else { $null })
    baseline_snapshot_present = ($null -ne $baseline)
    baseline_status = $(if ($baseline -and $baseline.autologon) { [string]$baseline.autologon.status } else { $null })
    after_snapshot_present = ($null -ne $after)
    after_status = $(if ($after -and $after.autologon) { [string]$after.autologon.status } else { $null })
    after_autologon_ready = $(if ($after -and $after.autologon) { [string]$after.autologon.status -eq 'autologon_ready' } else { $false })
    probe_result_present = ($null -ne $probeResult)
    probe_completed = $(if ($probeResult) { [bool]$probeResult.completed } else { $false })
    install_result_present = ($null -ne $installResult)
    install_completed = $(if ($installResult) { [bool]$installResult.completed } else { $false })
    installer_exit_code = $(if ($installResult) { $installResult.installer_exit_code } else { $null })
    probe_lifecycle_present = ($null -ne $probeLifecycle)
    install_lifecycle_present = ($null -ne $installLifecycle)
    local_action_files = $localActionNames
    network_inspected = $false
    remote_run_root = $null
    remote_run_root_present = $null
    remote_files = @()
    remote_probe_result_present = $null
    remote_install_result_present = $null
    matching_remote_tasks = @()
    target_mutation_performed_by_inspector = $false
}

if ($AllowNetworkActivity) {
    $remoteRoot = "\\$ComputerName\C$\ProgramData\SysAdminSuite\AutoLogonKerberosS4U\$innerRunId"
    $result.network_inspected = $true
    $result.remote_run_root = $remoteRoot
    $result.remote_run_root_present = Test-Path -LiteralPath $remoteRoot -PathType Container

    if ($result.remote_run_root_present) {
        $result.remote_files = @(Get-ChildItem -LiteralPath $remoteRoot -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        $result.remote_probe_result_present = Test-Path -LiteralPath (Join-Path $remoteRoot 's4u-probe-result.json') -PathType Leaf
        $result.remote_install_result_present = Test-Path -LiteralPath (Join-Path $remoteRoot 's4u-install-result.json') -PathType Leaf
    }
    else {
        $result.remote_probe_result_present = $false
        $result.remote_install_result_present = $false
    }

    $taskLines = @(& "$env:WINDIR\System32\schtasks.exe" /Query /S $ComputerName /FO CSV /NH 2>$null | ForEach-Object { [string]$_ })
    $result.matching_remote_tasks = @(
        $taskLines |
            Where-Object { $_ -match 'SysAdminSuite-AutoLogonS4U(?:Probe|Install)-' }
    )
}

$outDir = Join-Path $outer.FullName 'recovery'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$outPath = Join-Path $outDir ('interrupted_s4u_inspection_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
[pscustomobject]$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $outPath -Encoding UTF8

$summary = [pscustomobject]@{
    inner_run_id = $result.inner_run_id
    pilot_result_present = $result.pilot_result_present
    pilot_classification = $result.pilot_classification
    baseline_snapshot_present = $result.baseline_snapshot_present
    baseline_status = $result.baseline_status
    after_snapshot_present = $result.after_snapshot_present
    after_status = $result.after_status
    probe_result_present = $result.probe_result_present
    probe_completed = $result.probe_completed
    install_result_present = $result.install_result_present
    install_completed = $result.install_completed
    installer_exit_code = $result.installer_exit_code
    remote_run_root_present = $result.remote_run_root_present
    remote_probe_result_present = $result.remote_probe_result_present
    remote_install_result_present = $result.remote_install_result_present
    matching_remote_task_count = @($result.matching_remote_tasks).Count
    evidence_path = $outPath
}

if ($PassThru) { return [pscustomobject]@{ summary=$summary; result=[pscustomobject]$result; result_path=$outPath } }
$summary
