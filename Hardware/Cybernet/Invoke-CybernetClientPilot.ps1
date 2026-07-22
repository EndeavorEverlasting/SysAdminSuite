#Requires -Version 5.1
<#
.SYNOPSIS
Runs the bounded one-target Cybernet pilot from short hostname through live certification and production validation.

.DESCRIPTION
Accepts one authorized Cybernet short hostname or FQDN. The pilot verifies approved controller network posture,
resolves exactly one canonical FQDN from the controller DNS context, runs the zero-contact deployment Plan,
then bounded read-only transport preflight and harmless live certification. Production configuration is not
attempted unless every earlier gate passes and the operator accepts the high-impact confirmation. The production
stage applies the tracked hardware profile, installs the approved package set with AutoLogon last, and performs
read-only post-validation. The pilot writes one local handoff and can open the result automatically. It never
reboots the target.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,
    [switch]$OpenResults
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configurationScript = Join-Path $PSScriptRoot 'Invoke-CybernetClientConfiguration.ps1'
$preflightScript = Join-Path $repoRoot 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
$liveCertScript = Join-Path $repoRoot 'scripts\Invoke-SasSoftwareDeploymentTransportLiveCert.ps1'
$nameResolutionModule = Join-Path $repoRoot 'scripts\SasTargetNameResolution.psm1'
$networkGuardModule = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'

foreach ($requiredPath in @($configurationScript, $preflightScript, $liveCertScript, $nameResolutionModule, $networkGuardModule)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing Cybernet pilot dependency: $requiredPath"
    }
}

Import-Module $nameResolutionModule -Force
Import-Module $networkGuardModule -Force

$runId = 'cybernet-live-cert-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $repoRoot (Join-Path 'survey\output\cybernet_live_cert' $runId)
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$summaryPath = Join-Path $runRoot 'cybernet_live_cert_summary.json'
$handoffPath = Join-Path $runRoot 'OPEN-ME-CYBERNET-LIVE-CERT.txt'
$resolutionPath = Join-Path $runRoot 'target_name_resolution.json'
$consoleRoot = Join-Path $runRoot 'console'
New-Item -ItemType Directory -Path $consoleRoot -Force | Out-Null

$state = [ordered]@{
    schema_version = 'sas-cybernet-live-cert-summary/v1'
    run_id = $runId
    status = 'STARTED'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    input_name = $ComputerName.Trim()
    resolved_fqdn = $null
    target_resolution_path = $resolutionPath
    stages = @()
    production_attempted = $false
    automatic_reboot_performed = $false
    autologon_position = 'last'
    technician_acceptance_path = $null
    failure = $null
    run_root = $runRoot
    handoff_path = $handoffPath
}

function Save-SasPilotArtifacts {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$State)

    $State['generated_at_utc'] = (Get-Date).ToUniversalTime().ToString('o')
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $lines = @(
        'Cybernet live certification and production pilot'
        "Status: $($State['status'])"
        "Run: $($State['run_id'])"
        "Input hostname: $($State['input_name'])"
        "Resolved FQDN: $($State['resolved_fqdn'])"
        ''
        'Gate order:'
        '1. Approved controller network posture'
        '2. Unique canonical FQDN resolution'
        '3. Zero-contact deployment Plan/dry run'
        '4. Read-only live transport preflight'
        '5. Harmless one-target live certification and teardown proof'
        '6. Separate production confirmation'
        '7. Cybernet hardware configuration and software deployment with AutoLogon last'
        '8. Read-only post-validation'
        ''
        "Production attempted: $($State['production_attempted'])"
        'Automatic reboot performed: False'
        "Technician acceptance: $($State['technician_acceptance_path'])"
        "Summary: $summaryPath"
        "Run folder: $runRoot"
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$State['failure'])) {
        $lines += ''
        $lines += "ACTION REQUIRED: $($State['failure'])"
        $lines += 'Stop. Preserve this run folder and do not bypass or blindly retry the failed gate.'
    }
    elseif ([string]$State['status'] -eq 'PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED') {
        $lines += ''
        $lines += 'NEXT: Complete the generated technician software acceptance checklist.'
        $lines += 'AutoLogon is installed only; post-reboot automatic sign-in requires separately authorized direct observation.'
    }
    elseif ([string]$State['status'] -eq 'LIVE_CERT_PASS_PRODUCTION_NOT_RUN') {
        $lines += ''
        $lines += 'The harmless live certificate passed. Production was not approved or was declined.'
    }
    $lines | Set-Content -LiteralPath $handoffPath -Encoding UTF8
}

function Open-SasPilotResults {
    if (-not $OpenResults -or $env:OS -ne 'Windows_NT') { return }
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $handoffPath) | Out-Null } catch { }
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $handoffPath) | Out-Null } catch { }
}

function Get-SasPilotPowerShellEngine {
    $process = Get-Process -Id $PID -ErrorAction SilentlyContinue
    if ($process -and -not [string]::IsNullOrWhiteSpace($process.Path)) { return $process.Path }
    foreach ($candidate in @('pwsh.exe', 'powershell.exe', 'pwsh', 'powershell')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'No PowerShell engine is available for the Cybernet pilot.'
}

function Invoke-SasPilotConfigurationMode {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Plan', 'Apply', 'Validate')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$ResolvedFqdn
    )

    $stageOutputRoot = Join-Path $runRoot ("configuration-{0}" -f $Mode.ToLowerInvariant())
    New-Item -ItemType Directory -Path $stageOutputRoot -Force | Out-Null
    $consolePath = Join-Path $consoleRoot ("configuration-{0}.log" -f $Mode.ToLowerInvariant())
    $arguments = @(
        '-NoProfile', '-File', $configurationScript,
        '-Mode', $Mode,
        '-ComputerName', $ResolvedFqdn,
        '-OutputRoot', $stageOutputRoot
    )
    if ($Mode -eq 'Apply') {
        $arguments += '-AllowTargetMutation'
        $arguments += '-Confirm:$false'
    }

    Write-Host "`n=== Cybernet live-cert stage: $Mode ==="
    $engine = Get-SasPilotPowerShellEngine
    $console = @(& $engine @arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $console | Set-Content -LiteralPath $consolePath -Encoding UTF8
    $console | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) {
        throw "Cybernet client configuration $Mode stage failed with exit code $exitCode."
    }

    $stageSummaryPath = Get-ChildItem -LiteralPath $stageOutputRoot -Filter 'cybernet_client_configuration_summary.json' -File -Recurse |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $stageSummaryPath) { throw "Cybernet client configuration $Mode did not emit its summary." }
    $stageSummary = Get-Content -LiteralPath $stageSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expectedStatus = @{
        Plan = 'PLAN_READY'
        Apply = 'APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED'
        Validate = 'HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED'
    }[$Mode]
    if ([string]$stageSummary.status -ne $expectedStatus) {
        throw "Cybernet client configuration $Mode returned $($stageSummary.status), expected $expectedStatus."
    }

    return [pscustomobject][ordered]@{
        name = "configuration-$($Mode.ToLowerInvariant())"
        status = [string]$stageSummary.status
        summary_path = $stageSummaryPath
        console_path = $consolePath
        technician_acceptance_path = [string]$stageSummary.software_acceptance_path
    }
}

function Invoke-SasPilotPowerShellStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$ResultProperty
    )

    $consolePath = Join-Path $consoleRoot ("{0}.log" -f $Name)
    $items = @(& $Action 2>&1)
    $items | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath $consolePath -Encoding UTF8
    $items | ForEach-Object { Write-Host $_ }
    $result = @($items | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties[$ResultProperty] } | Select-Object -Last 1)
    if ($result.Count -ne 1) { throw "$Name did not return one structured result." }
    return [pscustomobject]@{ result = $result[0]; console_path = $consolePath }
}

try {
    Write-Host 'Cybernet clickable live certification'
    Write-Host "Input hostname: $ComputerName"
    Write-Host 'The script resolves the FQDN, runs dry proof before live proof, and stops at every failed gate.'

    Assert-SasNorthwellWifi
    $state['stages'] += [pscustomobject]@{ name = 'controller-network-posture'; status = 'PASS' }

    $resolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
    $resolution | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolutionPath -Encoding UTF8
    $resolvedFqdn = [string]$resolution.fqdn
    $state['resolved_fqdn'] = $resolvedFqdn
    $state['stages'] += [pscustomobject]@{
        name = 'canonical-fqdn-resolution'
        status = [string]$resolution.disposition
        evidence_path = $resolutionPath
    }
    Write-Host "Resolved canonical FQDN: $resolvedFqdn"

    $plan = Invoke-SasPilotConfigurationMode -Mode Plan -ResolvedFqdn $resolvedFqdn
    $state['stages'] += $plan

    Write-Host "`n=== Cybernet live-cert stage: read-only transport preflight ==="
    $preflightStage = Invoke-SasPilotPowerShellStage -Name 'transport-preflight' -ResultProperty 'result_path' -Action {
        & $preflightScript `
            -ComputerName $resolvedFqdn `
            -TransportIntent kerberos_smb_task `
            -AllowNetworkActivity `
            -OutputRoot (Join-Path $runRoot 'transport-preflight') `
            -PassThru
    }
    $preflight = $preflightStage.result
    if ([string]$preflight.result.decision.classification -ne 'kerberos_smb_task_ready' -or
        [string]$preflight.result.decision.selected_transport -ne 'kerberos_smb_task') {
        throw 'Transport preflight did not prove kerberos_smb_task_ready.'
    }
    $state['stages'] += [pscustomobject]@{
        name = 'transport-preflight'
        status = [string]$preflight.result.decision.classification
        result_path = [string]$preflight.result_path
        console_path = $preflightStage.console_path
    }

    Write-Host "`n=== Cybernet live-cert stage: harmless transport certification ==="
    $liveCertStage = Invoke-SasPilotPowerShellStage -Name 'transport-live-cert' -ResultProperty 'result_path' -Action {
        & $liveCertScript `
            -ComputerName $resolvedFqdn `
            -PreflightResultPath $preflight.result_path `
            -AllowNetworkActivity `
            -AllowTargetMutation `
            -OutputRoot (Join-Path $runRoot 'transport-live-cert') `
            -PassThru
    }
    $liveCert = $liveCertStage.result
    if ([string]$liveCert.disposition -ne 'LIVE CERT PASS') {
        throw 'Harmless transport live certification did not pass.'
    }
    $state['stages'] += [pscustomobject]@{
        name = 'transport-live-cert'
        status = [string]$liveCert.disposition
        result_path = [string]$liveCert.result_path
        handoff_path = [string]$liveCert.operator_handoff_path
        console_path = $liveCertStage.console_path
    }

    $productionAction = 'Apply the Cybernet hardware profile, install the six-package clinical set with AutoLogon last, and run post-validation'
    if (-not $PSCmdlet.ShouldProcess($resolvedFqdn, $productionAction)) {
        $state['status'] = 'LIVE_CERT_PASS_PRODUCTION_NOT_RUN'
        Save-SasPilotArtifacts -State $state
        Open-SasPilotResults
        Write-Output ([pscustomobject]$state)
        exit 0
    }

    $state['production_attempted'] = $true
    $apply = Invoke-SasPilotConfigurationMode -Mode Apply -ResolvedFqdn $resolvedFqdn
    $state['stages'] += $apply
    $state['technician_acceptance_path'] = $apply.technician_acceptance_path

    $validate = Invoke-SasPilotConfigurationMode -Mode Validate -ResolvedFqdn $resolvedFqdn
    $state['stages'] += $validate
    $state['status'] = 'PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED'
    Save-SasPilotArtifacts -State $state
    Open-SasPilotResults
    Write-Output ([pscustomobject]$state)
    exit 0
}
catch {
    $state['status'] = 'ACTION_REQUIRED'
    $state['failure'] = $_.Exception.Message
    Save-SasPilotArtifacts -State $state
    Open-SasPilotResults
    Write-Error $_.Exception.Message
    exit 1
}
