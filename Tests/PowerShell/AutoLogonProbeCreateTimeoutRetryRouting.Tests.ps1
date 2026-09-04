#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$stateModule = Join-Path $repoRoot 'scripts\SasAutoLogonOperatorState.psm1'
$fieldScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
$recoveryScript = Join-Path $repoRoot 'scripts\Recover-SasLatestInterruptedAutoLogonS4U.ps1'
foreach ($path in @($stateModule,$fieldScript,$recoveryScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing one-shot routing dependency: $path" }
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

Import-Module $stateModule -Force

function New-ProbeTimeoutFixture {
    param([hashtable]$Override = @{})
    $value = [ordered]@{
        status = 'ACTION_REQUIRED'
        classification = 'AUTOLOGON_FIELD_POST_APPLY_REVIEW_REQUIRED'
        deployment_classification = 'S4U_PROBE_CREATE_TIMEOUT'
        autologon_deployment_started = $true
        autologon_deployment_completed = $false
        autologon_applied = $false
        pre_reboot_autologon_ready = $false
        automatic_reboot_performed = $false
        restart_offline_observed = $false
        restart_online_observed = $false
        # Staging/hash preparation is a target mutation in the wrapper result. That must not by
        # itself turn a probe-create timeout into install/reboot ambiguity.
        target_mutation_performed = $true
    }
    foreach ($key in $Override.Keys) { $value[$key] = $Override[$key] }
    return [pscustomobject]$value
}

$safe = New-ProbeTimeoutFixture
Assert-True ([bool](Test-SasAutoLogonProbeCreateTimeoutRecoveryCandidate -Value $safe)) 'Exact probe-create timeout was not admitted to recovery-first retry routing.'

foreach ($case in @(
    @{ name='wrong inner classification'; values=@{ deployment_classification='S4U_INSTALL_CREATE_TIMEOUT' } },
    @{ name='AutoLogon applied'; values=@{ autologon_applied=$true } },
    @{ name='pre-reboot ready'; values=@{ pre_reboot_autologon_ready=$true } },
    @{ name='reboot performed'; values=@{ automatic_reboot_performed=$true } },
    @{ name='restart offline observed'; values=@{ restart_offline_observed=$true } },
    @{ name='restart online observed'; values=@{ restart_online_observed=$true } },
    @{ name='deployment completed'; values=@{ autologon_deployment_completed=$true } },
    @{ name='not started'; values=@{ autologon_deployment_started=$false } },
    @{ name='wrong wrapper classification'; values=@{ classification='AUTOLOGON_FIELD_PRE_APPLY_ENGINE_BLOCKED' } },
    @{ name='wrong wrapper status'; values=@{ status='STARTED' } }
)) {
    $candidate = New-ProbeTimeoutFixture -Override $case.values
    Assert-True (-not [bool](Test-SasAutoLogonProbeCreateTimeoutRecoveryCandidate -Value $candidate)) "Unsafe evidence shape was admitted: $($case.name)"
}

$field = [IO.File]::ReadAllText($fieldScript)
$helperUse = '$priorRecoverableProbeCreateTimeout = [bool](Test-SasAutoLogonProbeCreateTimeoutRecoveryCandidate -Value $priorValue)'
$unsafeGate = '$priorPostApply = (-not $priorRecoverableProbeCreateTimeout -and ('
$recoveryGate = '=== INTERRUPTED PROBE RECOVERY GATE ==='
Assert-True ($field.Contains($helperUse)) 'Field runner does not classify prior exact probe-create timeout evidence.'
Assert-True ($field.Contains($unsafeGate)) 'Field runner does not preserve fail-closed prior post-apply gating around the narrow exception.'
Assert-True ($field.IndexOf($helperUse, [StringComparison]::Ordinal) -lt $field.IndexOf($unsafeGate, [StringComparison]::Ordinal)) 'Recovery candidate must be classified before the prior post-apply blocker.'
Assert-True ($field.IndexOf($unsafeGate, [StringComparison]::Ordinal) -lt $field.IndexOf($recoveryGate, [StringComparison]::Ordinal)) 'Prior evidence gate must remain before target recovery.'
Assert-True ($field.Contains('Test-SasAutoLogonProbeCreateTimeoutRecoveryCandidate -Value ([pscustomobject]$result)')) 'Catch path does not reuse the same persisted evidence predicate.'
Assert-True ($field.Contains('elseif ($recoverableProbeCreateTimeout)')) 'Catch path does not route the exact recoverable failure to one Remote continuation.'
Assert-True ($field.Contains('"sas autologon Remote $requestedTarget"')) 'Recoverable failure does not advertise the canonical Remote continuation.'

# The recovery predicate consumes deployment_classification. Prove that a real inner deployment
# failure is copied into that outer persisted field before the catch-path predicate evaluates it.
$classificationMap = "'classification' { `$Destination.deployment_classification = `$value }"
$innerRead = '$inner = Get-SasLatestInnerDeploymentResult'
$innerCopy = 'Copy-SasDeploymentState -Destination $result -Source $inner.value'
$catchPredicate = '$recoverableProbeCreateTimeout = [bool](Test-SasAutoLogonProbeCreateTimeoutRecoveryCandidate -Value ([pscustomobject]$result))'
Assert-True ($field.Contains('deployment_classification = $null')) 'Outer field result no longer owns deployment_classification.'
Assert-True ($field.Contains($classificationMap)) 'Inner deployment classification is not mapped to the outer persisted field.'
Assert-True ($field.Contains($innerRead) -and $field.Contains($innerCopy) -and $field.Contains($catchPredicate)) 'Catch path lost inner-result classification propagation.'
Assert-True ($field.IndexOf($innerRead, [StringComparison]::Ordinal) -lt $field.IndexOf($innerCopy, [StringComparison]::Ordinal)) 'Inner result must be read before deployment state is copied.'
Assert-True ($field.IndexOf($innerCopy, [StringComparison]::Ordinal) -lt $field.IndexOf($catchPredicate, [StringComparison]::Ordinal)) 'Inner deployment classification must be copied before recoverability is classified.'

# Assert the recovery authority by semantic gates rather than error-message wording. It must admit
# only the exact v2 terminal Probe timeout, reject any Install/after-state/reboot/sign-in evidence,
# and use the exact cleanup authority rather than broad task discovery/removal.
$recovery = [IO.File]::ReadAllText($recoveryScript)
foreach ($marker in @(
    "'sas-autologon-kerberos-s4u-pilot-result/v2'",
    "'S4U_PROBE_CREATE_TIMEOUT'",
    '$null -eq $installProperty -or $null -ne $installProperty.Value',
    '$null -eq $installerExitProperty -or $null -ne $installerExitProperty.Value',
    '$null -eq $afterPathProperty -or -not [string]::IsNullOrWhiteSpace([string]$afterPathProperty.Value)',
    '$null -eq $preRebootProperty -or [bool]$preRebootProperty.Value',
    '$null -eq $rebootProperty -or [bool]$rebootProperty.Value',
    '$null -eq $signInProperty -or [bool]$signInProperty.Value',
    'install_or_after_evidence_present',
    'Complete-SasInterruptedAutoLogonS4URecovery.ps1'
)) {
    Assert-True ($recovery.Contains($marker)) "Recovery authority lost fail-closed semantic gate: $marker"
}
Assert-True ($recovery.Contains("throw \"Interrupted AutoLogon evidence includes install/after-state activity.")) 'Recovery authority no longer fails closed when install/after-state evidence is discovered.'
Assert-True (-not $recovery.Contains("Get-ScheduledTask")) 'Recovery authority must not broaden into local/global task discovery.'

Write-Host 'PASS: exact probe-create timeout routes through bounded recovery before one new AutoLogon apply'
