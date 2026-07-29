#Requires -Version 5.1
<#
.SYNOPSIS
Deploy the complete Cybernet clinical software profile and restart after AutoLogon.

.DESCRIPTION
The current full field deployment sequence is intentionally split across proven engines:
  1. run the one-target Kerberos SMB plus Task Scheduler low-noise readiness chain;
  2. deploy the five-package cybernet-clinical-core set;
  3. apply AutoLogon last through the Kerberos/S4U lane;
  4. restart the same target and wait for the restart cycle to complete.

The historical six-package LocalSystem package-set controller is not used because canonical SYSTEM
AutoLogon remains blocked by failed runtime qualification. This orchestrator preserves that truth
while still delivering the complete requested workstation software state.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [ValidateRange(10,7200)]
    [int]$SoftwareWaitTimeout = 1800,

    [ValidateRange(5,120)]
    [int]$RestartDelaySeconds = 15,

    [ValidateRange(60,900)]
    [int]$RestartTimeoutSeconds = 300,

    [ValidateRange(1,30)]
    [int]$ReadinessTimeoutSeconds = 5,

    [string]$OutputRoot,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmDeployment,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $AllowTargetMutation -or -not $ConfirmDeployment) {
    throw 'Cybernet software deployment requires both -AllowTargetMutation and -ConfirmDeployment. Use sas cybernet Deploy HOST.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$readinessScript = Join-Path $PSScriptRoot 'Invoke-SasCybernetDeploymentReadiness.ps1'
$coreScript = Join-Path $PSScriptRoot 'Invoke-SasCybernetClinicalCoreDeployment.ps1'
$autoScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonS4URestartDeployment.ps1'
$catalogPath = Join-Path $repoRoot 'configs\software-packages\windows-native-package-sets.json'
foreach ($required in @($readinessScript,$coreScript,$autoScript,$catalogPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing full Cybernet deployment dependency: $required" }
}

$target = $ComputerName.Trim().TrimEnd('.')
if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Invalid Cybernet hostname or FQDN: $target"
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$full = @($catalog.package_sets | Where-Object { [string]$_.id -eq 'cybernet-clinical-workstation' })
$core = @($catalog.package_sets | Where-Object { [string]$_.id -eq 'cybernet-clinical-core' })
if ($full.Count -ne 1 -or $core.Count -ne 1) { throw 'Cybernet full/core package-set catalog is missing or ambiguous.' }
$fullIds = @($full[0].package_ids | ForEach-Object { [string]$_ })
$coreIds = @($core[0].package_ids | ForEach-Object { [string]$_ })
if ($fullIds.Count -ne ($coreIds.Count + 1) -or $fullIds[-1] -ne 'autologon') {
    throw 'Cybernet full-profile package order is invalid: AutoLogon must be the final software step.'
}
if (($fullIds[0..($fullIds.Count - 2)] -join '|') -ne ($coreIds -join '|')) {
    throw 'Cybernet full-profile order drifted from the approved clinical-core sequence before AutoLogon.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\runs\cybernet-software-deployment'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$runId = 'cybernet-software-deployment-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'cybernet_software_deployment_result.json'

$result = [ordered]@{
    schema_version = 'sas-cybernet-software-deployment-result/v1'
    run_id = $runId
    target = $target
    execution_target = $null
    package_set_id = 'cybernet-clinical-workstation'
    package_ids = $fullIds
    autologon_included = $true
    autologon_was_last_software_step = $true
    low_noise_transport_preflight_required = $true
    readiness_result_path = $null
    readiness_status = $null
    readiness_transport_classification = $null
    readiness_tested_ports = @()
    clinical_core_result_path = $null
    clinical_core_status = $null
    autologon_result_path = $null
    autologon_classification = $null
    automatic_reboot_performed = $false
    restart_offline_observed = $false
    restart_online_observed = $false
    runtime_proof_required_for_deployment_completion = $false
    status = 'STARTED'
    reason = $null
    result_path = $resultPath
}

function Save-SasCybernetSoftwareDeploymentResult {
    $result | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
Save-SasCybernetSoftwareDeploymentResult

try {
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host " CYBERNET SOFTWARE DEPLOYMENT: $target" -ForegroundColor Cyan
    Write-Host ' Low-noise readiness first; clinical applications next; AutoLogon last; restart included.' -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    Write-Host "`n=== LOW-NOISE DEPLOYMENT READINESS ===" -ForegroundColor Cyan
    $readiness = & $readinessScript -ComputerName $target -AllowNetworkActivity `
        -TimeoutSeconds $ReadinessTimeoutSeconds -OutputRoot (Join-Path $runRoot 'readiness') -PassThru
    $result.readiness_result_path = [string]$readiness.result_path
    $result.readiness_status = [string]$readiness.status
    $result.readiness_transport_classification = [string]$readiness.transport_classification
    $result.readiness_tested_ports = @($readiness.tested_ports)
    $result.execution_target = [string]$readiness.resolved_fqdn
    Save-SasCybernetSoftwareDeploymentResult

    if ([string]$readiness.status -ne 'CYBERNET_DEPLOYMENT_READINESS_READY' -or -not [bool]$readiness.ready_for_deployment) {
        throw "Low-noise deployment readiness did not pass: $($readiness.status)"
    }
    if (@($readiness.tested_ports | Where-Object { $_ -in @(5985,5986) }).Count -gt 0) {
        throw 'Low-noise readiness unexpectedly tested WinRM ports. Live deployment was not started.'
    }

    $executionTarget = [string]$readiness.resolved_fqdn
    if ([string]::IsNullOrWhiteSpace($executionTarget)) {
        throw 'Low-noise readiness did not return the authorized target FQDN. Live deployment was not started.'
    }

    $coreResult = & $coreScript -Mode Deploy -ComputerName $executionTarget -SoftwareWaitTimeout $SoftwareWaitTimeout `
        -OutputRoot (Join-Path $runRoot 'clinical-core') -AllowTargetMutation -ConfirmDeployment -PassThru
    $result.clinical_core_result_path = [string]$coreResult.summary_path
    $result.clinical_core_status = [string]$coreResult.status
    Save-SasCybernetSoftwareDeploymentResult
    if ([string]$coreResult.status -ne 'CLINICAL_CORE_DEPLOYMENT_COMPLETED') {
        throw "Clinical-core stage did not complete: $($coreResult.status)"
    }

    Write-Host "`n=== FINAL SOFTWARE STEP: AUTOLOGON ===" -ForegroundColor Cyan
    $autoResult = & $autoScript -ComputerName $executionTarget -RestartDelaySeconds $RestartDelaySeconds `
        -RestartTimeoutSeconds $RestartTimeoutSeconds -OutputRoot (Join-Path $runRoot 'autologon') `
        -AllowTargetMutation -ConfirmDeployment -PassThru

    $result.autologon_result_path = [string]$autoResult.result_path
    $result.autologon_classification = [string]$autoResult.classification
    $result.automatic_reboot_performed = [bool]$autoResult.automatic_reboot_performed
    $result.restart_offline_observed = [bool]$autoResult.restart_offline_observed
    $result.restart_online_observed = [bool]$autoResult.restart_online_observed
    Save-SasCybernetSoftwareDeploymentResult

    if ([string]$autoResult.classification -ne 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED' -or
        -not [bool]$autoResult.automatic_reboot_performed -or
        -not [bool]$autoResult.restart_offline_observed -or
        -not [bool]$autoResult.restart_online_observed) {
        throw "AutoLogon/restart stage did not complete: $($autoResult.classification)"
    }

    $result.status = 'CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED'
    $result.reason = $null
    Save-SasCybernetSoftwareDeploymentResult

    Write-Host "`nCYBERNET SOFTWARE DEPLOYMENT COMPLETED." -ForegroundColor Green
    Write-Host 'Low-noise Kerberos SMB plus Task Scheduler readiness passed.' -ForegroundColor Green
    Write-Host 'Five clinical applications deployed.' -ForegroundColor Green
    Write-Host 'AutoLogon deployed last.' -ForegroundColor Green
    Write-Host 'Target restart cycle completed.' -ForegroundColor Green
    Write-Host "Evidence: $resultPath"
    Write-Host 'No additional live-cert/test loop is required to call deployment complete.' -ForegroundColor Cyan
}
catch {
    $result.status = 'ACTION_REQUIRED'
    $result.reason = $_.Exception.Message
    Save-SasCybernetSoftwareDeploymentResult
    Write-Host "`nACTION REQUIRED: $($result.reason)" -ForegroundColor Yellow
    Write-Host "Evidence: $resultPath"
    Write-Host 'Run sas evidence before any retry if the console output is incomplete.' -ForegroundColor Yellow
    throw
}

if ($PassThru) { return [pscustomobject]$result }
exit 0
