#Requires -Version 5.1
<#
.SYNOPSIS
Runs the bounded one-target Cybernet pilot from dry run through live certification and production validation.

.DESCRIPTION
Provides one operator surface for an explicitly authorized Cybernet FQDN. The pilot runs the
zero-contact client-configuration Plan first, then a bounded read-only Kerberos SMB/Task Scheduler
preflight, then the harmless one-target transport live certification. Production configuration is
not attempted unless every earlier gate passes and the operator accepts the high-impact confirmation.
The production stage applies the tracked hardware profile, installs the approved package set with
AutoLogon last, and performs read-only post-validation. No stage reboots the target.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configurationScript = Join-Path $PSScriptRoot 'Invoke-CybernetClientConfiguration.ps1'
$preflightScript = Join-Path $repoRoot 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
$liveCertScript = Join-Path $repoRoot 'scripts\Invoke-SasSoftwareDeploymentTransportLiveCert.ps1'

foreach ($requiredPath in @($configurationScript, $preflightScript, $liveCertScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing Cybernet pilot dependency: $requiredPath"
    }
}

if ($ComputerName -notmatch '\.' -or [System.Uri]::CheckHostName($ComputerName) -ne [System.UriHostNameType]::Dns) {
    throw 'Pilot requires one explicitly authorized fully qualified DNS name.'
}

function Get-SasPilotPowerShellEngine {
    $process = Get-Process -Id $PID -ErrorAction SilentlyContinue
    if ($process -and -not [string]::IsNullOrWhiteSpace($process.Path)) {
        return $process.Path
    }
    foreach ($candidate in @('pwsh.exe', 'powershell.exe', 'pwsh', 'powershell')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'No PowerShell engine is available for the Cybernet pilot.'
}

function Invoke-SasPilotConfigurationMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Plan', 'Apply', 'Validate')]
        [string]$Mode
    )

    $arguments = @(
        '-NoProfile'
        '-File'
        $configurationScript
        '-Mode'
        $Mode
        '-ComputerName'
        $ComputerName
    )
    if ($Mode -eq 'Apply') {
        $arguments += '-AllowTargetMutation'
        $arguments += '-Confirm:$false'
    }

    Write-Host "`n=== Cybernet pilot stage: $Mode ==="
    $engine = Get-SasPilotPowerShellEngine
    & $engine @arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Cybernet client configuration $Mode stage failed with exit code $exitCode. Stop; do not bypass or blindly retry the failed gate."
    }
}

Write-Host 'Cybernet one-target pilot'
Write-Host "Target: $ComputerName"
Write-Host 'Gate order: deployment dry run -> read-only live preflight -> harmless live cert -> production confirmation -> apply -> validate.'
Write-Host 'This workflow is Cybernet-only, installs AutoLogon last, and never reboots the target.'

Invoke-SasPilotConfigurationMode -Mode Plan

Write-Host "`n=== Cybernet pilot stage: read-only transport preflight ==="
$preflight = & $preflightScript `
    -ComputerName $ComputerName `
    -TransportIntent kerberos_smb_task `
    -AllowNetworkActivity `
    -PassThru
if ($null -eq $preflight -or
    [string]$preflight.result.decision.classification -ne 'kerberos_smb_task_ready' -or
    [string]$preflight.result.decision.selected_transport -ne 'kerberos_smb_task') {
    throw 'Transport preflight did not prove kerberos_smb_task_ready. Stop before target mutation or production deployment.'
}

Write-Host "`n=== Cybernet pilot stage: harmless live certification ==="
$liveCert = & $liveCertScript `
    -ComputerName $ComputerName `
    -PreflightResultPath $preflight.result_path `
    -AllowNetworkActivity `
    -AllowTargetMutation `
    -PassThru
if ($null -eq $liveCert -or [string]$liveCert.disposition -ne 'LIVE CERT PASS') {
    throw 'Harmless transport live certification did not pass. Stop before production deployment.'
}

$productionAction = 'Apply the Cybernet hardware profile, install the six-package clinical set with AutoLogon last, and run post-validation'
if (-not $PSCmdlet.ShouldProcess($ComputerName, $productionAction)) {
    Write-Output ([pscustomobject][ordered]@{
        status = 'LIVE_CERT_PASS_PRODUCTION_NOT_RUN'
        computer_name = $ComputerName
        preflight_result_path = $preflight.result_path
        live_cert_result_path = $liveCert.result_path
        live_cert_handoff_path = $liveCert.operator_handoff_path
        target_mutation_performed_by_production = $false
    })
    return
}

Invoke-SasPilotConfigurationMode -Mode Apply
Invoke-SasPilotConfigurationMode -Mode Validate

Write-Output ([pscustomobject][ordered]@{
    status = 'PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED'
    computer_name = $ComputerName
    preflight_result_path = $preflight.result_path
    live_cert_result_path = $liveCert.result_path
    live_cert_handoff_path = $liveCert.operator_handoff_path
    production_profile = 'cybernet-clinical-workstation-default'
    package_set = 'cybernet-clinical-workstation'
    autologon_position = 'last'
    automatic_reboot_performed = $false
    next_action = 'Complete generated technician software acceptance and perform any separately authorized reboot observation.'
})
