#Requires -Version 5.1
<#
.SYNOPSIS
Plan or deploy the approved five-package Cybernet clinical core without AutoLogon.

.DESCRIPTION
This is the field-safe software deployment lane for an explicitly authorized Cybernet target.
It validates the tracked `cybernet-clinical-core` package set, runs the current PowerShell Northwell
network gate, performs the package-set dry run, and then continues into live deployment in the same
invocation when Mode=Deploy and mutation confirmation switches are present.

AutoLogon is intentionally excluded. Its current live lane remains the separate Kerberos/S4U
`sas autologon Remote HOST` workflow after clinical-core acceptance. No reboot is performed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Plan','Deploy')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [ValidateRange(10,7200)]
    [int]$SoftwareWaitTimeout = 1800,

    [string]$BashPath,
    [string]$OutputRoot,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmDeployment,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$target = $ComputerName.Trim()
if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Invalid Cybernet hostname or FQDN: $target"
}
if ($Mode -eq 'Deploy' -and (-not $AllowTargetMutation -or -not $ConfirmDeployment)) {
    throw 'Deploy requires both -AllowTargetMutation and -ConfirmDeployment. Use the repo-owned Deploy-CybernetClinicalCore.cmd or sas cybernet Deploy HOST surface.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $repoRoot 'configs\software-packages\windows-native-package-sets.json'
$controllerPath = Join-Path $repoRoot 'bash\apps\sas-install-apps.sh'
$networkGatePath = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
foreach ($requiredPath in @($catalogPath,$controllerPath,$networkGatePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing clinical-core deployment dependency: $requiredPath"
    }
}

$packageSetId = 'cybernet-clinical-core'
$expectedPackageIds = @(
    'allscripts-eehr-shortcut-uai-2-2',
    'epic-downtime-guide-shortcut-1-0',
    'nuance-dragon-medical-one-2025',
    'hyland-fos-epic-integration-23-1-33-1000',
    'bca'
)
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$catalog.schema_version -ne 'sas-windows-native-package-sets/v1') {
    throw "Unsupported Windows-native package-set catalog: $($catalog.schema_version)"
}
$coreMatches = @($catalog.package_sets | Where-Object { [string]$_.id -eq $packageSetId })
if ($coreMatches.Count -ne 1) { throw "Approved package set not found or ambiguous: $packageSetId" }
$coreIds = @($coreMatches[0].package_ids | ForEach-Object { [string]$_ })
if (($coreIds -join '|') -ne ($expectedPackageIds -join '|')) {
    throw 'Tracked cybernet-clinical-core membership/order drifted. Stop before deployment.'
}
if ($coreIds -contains 'autologon') {
    throw 'AutoLogon must not be part of the clinical-core deployment lane.'
}
$autoSet = @($catalog.package_sets | Where-Object { [string]$_.id -eq 'cybernet-autologon-only' })
if ($autoSet.Count -ne 1 -or @($autoSet[0].package_ids).Count -ne 1 -or [string]$autoSet[0].package_ids[0] -ne 'autologon') {
    throw 'The separate cybernet-autologon-only package-set contract is missing or malformed.'
}
$packageById = @{}
foreach ($package in @($catalog.packages)) { $packageById[[string]$package.id] = $package }
foreach ($packageId in $expectedPackageIds) {
    if (-not $packageById.ContainsKey($packageId)) { throw "Clinical-core package definition missing: $packageId" }
    if (-not [bool]$packageById[$packageId].install_enabled) { throw "Clinical-core package is disabled: $packageId" }
}
$autoPackage = $packageById['autologon']
if ($null -eq $autoPackage -or [bool]$autoPackage.canonical_system_install_enabled) {
    throw 'AutoLogon catalog disposition changed unexpectedly; re-evaluate the separate AutoLogon lane before proceeding.'
}

function Get-SasGitBashPath {
    if (-not [string]::IsNullOrWhiteSpace($BashPath)) {
        if (-not (Test-Path -LiteralPath $BashPath -PathType Leaf)) { throw "Git Bash not found: $BashPath" }
        return (Resolve-Path -LiteralPath $BashPath).Path
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitBin = Split-Path -Parent $gitCommand.Source
        $gitRoot = Split-Path -Parent $gitBin
        foreach ($candidate in @((Join-Path $gitRoot 'bin\bash.exe'),(Join-Path $gitRoot 'usr\bin\bash.exe'))) {
            if (-not $candidates.Contains($candidate)) { [void]$candidates.Add($candidate) }
        }
    }
    if ($env:ProgramFiles) {
        foreach ($candidate in @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),(Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe'))) {
            if (-not $candidates.Contains($candidate)) { [void]$candidates.Add($candidate) }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Git Bash could not be located. Install/repair Git for Windows before deployment.'
}

$bash = Get-SasGitBashPath
& $bash -lc 'command -v python3 >/dev/null 2>&1'
if ($LASTEXITCODE -ne 0) {
    throw 'Git Bash cannot resolve python3, which the approved package-set controller requires.'
}

$runId = 'cybernet-clinical-core-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\runs\cybernet-clinical-core'
}
$runRoot = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $runId
$controllerRelative = ('survey/output/runs/cybernet-clinical-core/{0}/controller' -f $runId)
if (-not ([IO.Path]::GetFullPath($OutputRoot)).StartsWith((Join-Path $repoRoot 'survey\output\runs\cybernet-clinical-core'), [StringComparison]::OrdinalIgnoreCase)) {
    $controllerRelative = 'bash/apps/output'
}
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$summaryPath = Join-Path $runRoot 'cybernet_clinical_core_deployment_summary.json'
$dryLog = Join-Path $runRoot 'dry-run.console.log'
$deployLog = Join-Path $runRoot 'deploy.console.log'

$result = [ordered]@{
    schema_version = 'sas-cybernet-clinical-core-deployment-summary/v1'
    run_id = $runId
    mode = $Mode
    target = $target
    package_set_id = $packageSetId
    package_ids = $expectedPackageIds
    autologon_included = $false
    autologon_next_command = "sas autologon Remote $target"
    network_gate_passed = $false
    dry_run_exit_code = $null
    deploy_exit_code = $null
    deployment_attempted = $false
    automatic_reboot_performed = $false
    controller_result_csv = $null
    status = 'STARTED'
    reason = $null
    summary_path = $summaryPath
}

function Save-SasClinicalCoreSummary {
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
}

try {
    if ($Mode -eq 'Deploy') {
        & powershell.exe -NoLogo -NoProfile -File $networkGatePath -Purpose "Cybernet clinical-core software deployment to $target" -NoOpenWifiSettings
        $gateExit = $LASTEXITCODE
        if ($gateExit -ne 0) { throw "Network gate stopped deployment with exit code $gateExit." }
        $result.network_gate_passed = $true
    }

    $baseArguments = @(
        'bash/apps/sas-install-apps.sh',
        '--targets', $target,
        '--package-set', $packageSetId,
        '--allow-legacy',
        '--wait-timeout', [string]$SoftwareWaitTimeout,
        '--log-dir', $controllerRelative
    )

    Push-Location -LiteralPath $repoRoot
    try {
        Write-Host "`n=== CLINICAL CORE DRY RUN: $target ===" -ForegroundColor Cyan
        $dryConsole = @(& $bash @($baseArguments + '--dry-run') 2>&1 | ForEach-Object { $_.ToString() })
        $result.dry_run_exit_code = [int]$LASTEXITCODE
        $dryConsole | Tee-Object -FilePath $dryLog | Write-Host
        if ($result.dry_run_exit_code -ne 0) {
            throw "Clinical-core dry run failed with exit code $($result.dry_run_exit_code). Live deployment was not started."
        }

        if ($Mode -eq 'Plan') {
            $result.status = 'CLINICAL_CORE_PLAN_READY'
            Save-SasClinicalCoreSummary
            Write-Host "`nCLINICAL CORE PLAN READY." -ForegroundColor Green
            Write-Host "Evidence: $summaryPath"
            if ($PassThru) { return [pscustomobject]$result }
            exit 0
        }

        # The PowerShell network gate above is the current source of truth. The legacy Bash
        # detector can be blind to enterprise WLAN posture, so suppress only that duplicate
        # detector after the current gate has passed. All package/target/task/cleanup gates remain active.
        $previousSkipNmap = $env:SKIP_NMAP
        $env:SKIP_NMAP = '1'
        try {
            $result.deployment_attempted = $true
            Write-Host "`n=== LIVE CLINICAL CORE DEPLOYMENT: $target ===" -ForegroundColor Cyan
            $deployConsole = @(& $bash @baseArguments 2>&1 | ForEach-Object { $_.ToString() })
            $result.deploy_exit_code = [int]$LASTEXITCODE
            $deployConsole | Tee-Object -FilePath $deployLog | Write-Host
        }
        finally {
            if ($null -eq $previousSkipNmap) { Remove-Item Env:SKIP_NMAP -ErrorAction SilentlyContinue }
            else { $env:SKIP_NMAP = $previousSkipNmap }
        }
    }
    finally {
        Pop-Location
    }

    $controllerRoot = if ($controllerRelative -eq 'bash/apps/output') { Join-Path $repoRoot 'bash\apps\output' } else { Join-Path $repoRoot ($controllerRelative -replace '/', '\') }
    $resultCsv = Get-ChildItem -LiteralPath $controllerRoot -Filter '*.results.csv' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($resultCsv) { $result.controller_result_csv = $resultCsv.FullName }

    if ($result.deploy_exit_code -ne 0) {
        throw "Clinical-core deployment finished with exit code $($result.deploy_exit_code). Preserve the run evidence and do not blindly rerun."
    }

    $result.status = 'CLINICAL_CORE_DEPLOYMENT_COMPLETED'
    Save-SasClinicalCoreSummary
    Write-Host "`nCLINICAL CORE DEPLOYMENT COMPLETED." -ForegroundColor Green
    Write-Host 'Packages: 5 approved clinical-core applications' -ForegroundColor Green
    Write-Host 'AutoLogon: NOT INCLUDED; remains separate and last.' -ForegroundColor Yellow
    Write-Host "Evidence: $summaryPath"
    if ($result.controller_result_csv) { Write-Host "Controller results: $($result.controller_result_csv)" }
}
catch {
    $result.status = 'ACTION_REQUIRED'
    $result.reason = $_.Exception.Message
    Save-SasClinicalCoreSummary
    Write-Host "`nACTION REQUIRED: $($result.reason)" -ForegroundColor Yellow
    Write-Host "Evidence: $summaryPath"
    throw
}

if ($PassThru) { return [pscustomobject]$result }
exit 0
