#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [AllowEmptyString()]
    [string[]]$Arguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-SasMachineInfoCore {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in @($env:SAS_RUNTIME_ROOT,$env:SAS_REPO_ROOT)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$root)) {
            [void]$candidates.Add((Join-Path $root 'GetInfo\Get-MachineInfo.ps1'))
        }
    }

    # Direct invocation of the installed runner must still resolve only machine-local trusted
    # controller/runtime authorities; it must not depend on the caller's working directory.
    [void]$candidates.Add('C:\SASAL\GetInfo\Get-MachineInfo.ps1')
    $programDataRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:ProgramData)) { $env:ProgramData } else { 'C:\ProgramData' }
    $controllerCache = Join-Path $programDataRoot 'SysAdminSuite\repo-root.txt'
    if (Test-Path -LiteralPath $controllerCache -PathType Leaf) {
        try {
            $cachedRoot = ([string](Get-Content -LiteralPath $controllerCache -Raw -ErrorAction Stop)).Trim()
            if (-not [string]::IsNullOrWhiteSpace($cachedRoot)) {
                [void]$candidates.Add((Join-Path $cachedRoot 'GetInfo\Get-MachineInfo.ps1'))
            }
        } catch { }
    }
    try {
        [void]$candidates.Add((Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path 'GetInfo\Get-MachineInfo.ps1'))
    } catch { }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Canonical GetInfo\Get-MachineInfo.ps1 was not found in the active SysAdminSuite runtime/controller. Run sas refresh on Guest/Internet before retrying.'
}

function Assert-SasMachineTarget {
    param([Parameter(Mandatory=$true)][string]$Target)
    $value = $Target.Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$') {
        throw "Invalid machine target: $Target"
    }
    return $value
}

$actualArgs = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($actualArgs.Count -eq 0) {
    Write-Host 'Usage: sas machineinfo HOST01 [HOST02 ...]  OR  sas machineinfo file C:\Path\hosts.txt' -ForegroundColor Red
    exit 2
}

$sourceMode = 'DIRECT'
$targets = @()
if (([string]$actualArgs[0]).Trim().ToLowerInvariant() -eq 'file') {
    if ($actualArgs.Count -ne 2) {
        Write-Host 'Usage: sas machineinfo file C:\Path\hosts.txt' -ForegroundColor Red
        exit 2
    }
    $sourceMode = 'FILE'
    $inputPath = [IO.Path]::GetFullPath([string]$actualArgs[1])
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Machine-info target file not found: $inputPath"
    }
    $targets = @(Get-Content -LiteralPath $inputPath -ErrorAction Stop |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { Assert-SasMachineTarget -Target ([string]$_) })
}
else {
    if ($actualArgs.Count -gt 100) { throw 'Direct machine-info mode is limited to 100 explicit targets; use file mode for larger approved lists.' }
    $targets = @($actualArgs | ForEach-Object { Assert-SasMachineTarget -Target ([string]$_) })
}

$targets = @($targets | Sort-Object -Unique)
if ($targets.Count -eq 0) { throw 'No valid machine-info targets remain after normalization.' }
if ($targets.Count -gt 500) { throw 'Machine-info target files are limited to 500 hosts per bounded run.' }

$programData = if (-not [string]::IsNullOrWhiteSpace([string]$env:ProgramData)) { $env:ProgramData } else { 'C:\ProgramData' }
$jobsRoot = Join-Path $programData 'SysAdminSuite\jobs\MachineInfo'
$runId = '{0}-{1}' -f (Get-Date).ToString('yyyyMMdd-HHmmss-fff'),([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $jobsRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$targetManifest = Join-Path $runRoot 'targets.txt'
$csvPath = Join-Path $runRoot 'MachineInfo.csv'
$htmlPath = [IO.Path]::ChangeExtension($csvPath,'.html')
$summaryPath = Join-Path $runRoot 'Summary.json'
$targets | Set-Content -LiteralPath $targetManifest -Encoding ASCII

$startedUtc = (Get-Date).ToUniversalTime().ToString('o')
$core = Resolve-SasMachineInfoCore
Write-Host "Machine-info run: $runId" -ForegroundColor Cyan
Write-Host "Targets: $($targets.Count)"
Write-Host "Run root: $runRoot"
Write-Host 'Target mutation: NONE (read-only WMI/ICMP inventory).' -ForegroundColor Green

& $core -ListPath $targetManifest -OutputPath $csvPath
if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "Canonical machine-info collector did not produce its CSV: $csvPath"
}

$rows = @(Import-Csv -LiteralPath $csvPath)
$actualHosts = @($rows | ForEach-Object { ([string]$_.HostName).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
$targetDiff = @(Compare-Object -ReferenceObject $targets -DifferenceObject $actualHosts)
if ($targetDiff.Count -ne 0 -or $actualHosts.Count -ne $targets.Count) {
    $differenceText = ($targetDiff | ForEach-Object { "$($_.SideIndicator)$($_.InputObject)" }) -join ', '
    throw "MACHINE_INFO_TARGET_SET_MISMATCH: requested=$($targets.Count) observed=$($actualHosts.Count) diff=[$differenceText]"
}

$statusCounts = [ordered]@{}
foreach ($group in @($rows | Group-Object -Property Status)) {
    $statusCounts[[string]$group.Name] = [int]$group.Count
}

$summary = [pscustomobject][ordered]@{
    schema_version = 'sas-machine-info-run/v1'
    run_id = $runId
    started_utc = $startedUtc
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_mode = $sourceMode
    requested_target_count = [int]$targets.Count
    observed_target_count = [int]$actualHosts.Count
    exact_target_set_validated = $true
    target_mutation_performed = $false
    target_manifest = $targetManifest
    csv_path = $csvPath
    html_path = if (Test-Path -LiteralPath $htmlPath -PathType Leaf) { $htmlPath } else { $null }
    status_counts = $statusCounts
    proof_ceiling = 'Controller-observed read-only WMI/ICMP inventory for this run; repository or controller proof does not replace field acceptance of device identity or network reachability.'
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ''
Write-Host 'MACHINE_INFO_COMPLETED' -ForegroundColor Green
Write-Host "CSV: $csvPath"
if (Test-Path -LiteralPath $htmlPath -PathType Leaf) { Write-Host "HTML: $htmlPath" }
Write-Host "Summary: $summaryPath"
Write-Host "Exact target set: PASS ($($targets.Count)/$($targets.Count))" -ForegroundColor Green

if ([string]$env:SAS_MACHINEINFO_OPEN_OUTPUT -eq '1') {
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList @($runRoot) | Out-Null }
    catch { Write-Warning "Could not open the output folder automatically: $($_.Exception.Message)" }
}
exit 0
