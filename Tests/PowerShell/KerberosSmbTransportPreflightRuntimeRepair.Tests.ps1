#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repairScript = Join-Path $repoRoot 'scripts\Repair-SasKerberosSmbTransportPreflightRuntime.ps1'
$hardBoundedModule = Join-Path $repoRoot 'scripts\SasSoftwareDeploymentKerberosSmbHardBounded.psm1'
foreach ($required in @($repairScript,$hardBoundedModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing repair test dependency: $required" }
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Parse {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $errors | Format-List * | Out-Host
        throw "PowerShell parse failed: $Path"
    }
}

function New-TransportFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$NewLine
    )

    $scripts = Join-Path $Root 'scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    $lines = @(
        '#Requires -Version 5.1',
        '[CmdletBinding(DefaultParameterSetName = ''Live'')]',
        'param([string]$ComputerName,[switch]$AllowNetworkActivity,[string]$TransportIntent=''kerberos_smb_task'',[System.Management.Automation.PSCredential]$Credential,[switch]$FixtureMode,[string]$FixturePath,[int]$TimeoutSeconds=5,[string]$OutputRoot,[switch]$PassThru)',
        '$repoRoot = Split-Path -Parent $PSScriptRoot',
        '$lowNoiseTransportModulePath = Join-Path $PSScriptRoot ''SasSoftwareDeploymentLowNoise.psm1''',
        '$lowNoisePolicyModulePath = Join-Path $PSScriptRoot ''SasLowNoisePolicy.psm1''',
        'Import-Module $lowNoiseTransportModulePath -Force',
        'Import-Module $lowNoisePolicyModulePath -Force',
        '$transportWindowsPathBudget = 240',
        'Write-Warning ''TRANSPORT_OUTPUT_ROOT_COMPACTED: fixture sentinel''',
        '$requestSummary = if ($FixtureMode) {',
        '    ''fixture request''',
        '}',
        'else {',
        '    ''live request''',
        '}',
        '$context = [pscustomobject]@{ run_root=''fixture''; artifact_registry_path=''fixture-registry''; directories=[pscustomobject]@{ artifacts=''.''; evidence=''.''; reports=''.'' }; operator_handoff_path=''fixture-handoff'' }',
        'if ($FixtureMode) {',
        '    $fixture = Get-Content -LiteralPath $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json',
        '    if ($null -eq $fixture.observations) { throw ''Fixture must contain an observations object.'' }',
        '    $observations = $fixture.observations',
        '    $evidenceClass = ''sanitized_fixture''',
        '    $networkActivity = $false',
        '}',
        'else {',
        '    $observationParameters = @{ ComputerName=$ComputerName; TimeoutSeconds=$TimeoutSeconds }',
        '    if ($PSBoundParameters.ContainsKey(''Credential'')) { $observationParameters.Credential = $Credential }',
        '    if ($TransportIntent -eq ''auto'') { $observations = Invoke-SasSoftwareDeploymentTransportObservation @observationParameters }',
        '    else { $observationParameters.TransportIntent=$TransportIntent; $observations=Invoke-SasSoftwareDeploymentLowNoiseObservation @observationParameters }',
        '    $evidenceClass = ''operator_local_live''',
        '    $networkActivity = $true',
        '}',
        '$result = New-SasSoftwareDeploymentTransportResult `',
        '    -Observations $observations `',
        '    -EvidenceClass $evidenceClass `',
        '    -NetworkActivityPerformed $networkActivity',
        '$testedPorts = @()',
        '$nextAction = if ($result.decision.classification -in @(''kerberos_smb_task_ready'',''winrm_ready'')) {',
        '    ''ready''',
        '}',
        'else {',
        '    ''blocked''',
        '}',
        '$lowNoiseContext = New-SasLowNoiseContextObject -ProfileId ''admin_surface_reachability'' -ProfileSource ''explicit_subset_override'' -EvidenceSource ''fixture'' -Disposition ''fixture'' -Reason ''fixture'' -NetworkActivityPerformed $networkActivity -TargetMutationPerformed $false -NextAction $nextAction -EffectivePorts @()',
        '$resultPath = ''fixture-result''',
        '$observationPath = ''fixture-observations''',
        '$lowNoisePath = ''fixture-low-noise''',
        '$summaryPath = ''fixture-summary''',
        '$englishSummary = @(',
        '    ''Software deployment transport preflight''',
        '    ''Transport intent: fixture''',
        ')',
        '$networkDescription = ''fixture''',
        '$output = [pscustomobject]@{',
        '    run_root = $context.run_root',
        '    result_path = $resultPath',
        '    observations_path = $observationPath',
        '    low_noise_context_path = $lowNoisePath',
        '    english_summary_path = $summaryPath',
        '    artifact_registry_path = $context.artifact_registry_path',
        '    result = $result',
        '}',
        '$output'
    )
    [IO.File]::WriteAllText(
        (Join-Path $scripts 'Test-SasSoftwareDeploymentTransport.ps1'),
        ($lines -join $NewLine) + $NewLine,
        (New-Object Text.UTF8Encoding($false))
    )
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-hard-bounded-transport-repair-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    foreach ($case in @(
        [pscustomobject]@{ name='crlf'; newline="`r`n" },
        [pscustomobject]@{ name='lf'; newline="`n" }
    )) {
        $runtime = Join-Path $tempRoot $case.name
        New-TransportFixture -Root $runtime -NewLine $case.newline
        $entrypointBefore = Join-Path $runtime 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
        $fixtureText = [IO.File]::ReadAllText($entrypointBefore)

        $duplicateNetworkTokenCount = [regex]::Matches(
            $fixtureText,
            [regex]::Escape('-NetworkActivityPerformed $networkActivity')
        ).Count
        Assert-True ($duplicateNetworkTokenCount -eq 2) `
            "Fixture did not reproduce the real duplicate network-activity token for $($case.name): $duplicateNetworkTokenCount"

        $fixtureModeBranchCount = [regex]::Matches(
            $fixtureText,
            [regex]::Escape('if ($FixtureMode) {')
        ).Count
        Assert-True ($fixtureModeBranchCount -eq 2) `
            "Fixture did not reproduce both real fixture-mode branches for $($case.name): $fixtureModeBranchCount"

        $evidence = Join-Path $runtime 'evidence'
        $first = & $repairScript `
            -RuntimeRoot $runtime `
            -HardBoundedModuleSourcePath $hardBoundedModule `
            -EvidenceRoot $evidence `
            -ConfirmRepair `
            -PassThru

        Assert-True ([string]$first.classification -eq 'KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_APPLIED') `
            "Unexpected first repair classification for $($case.name): $($first.classification)"
        Assert-True ([bool]$first.hard_process_bounded) 'Hard process bound was not proven.'
        Assert-True ([bool]$first.default_no_credential_kerberos_smb_routed) 'Default SMB routing was not proven.'
        Assert-True ([bool]$first.timeout_stage_diagnostic_enabled) 'Timeout-stage diagnostic was not proven.'
        Assert-True (-not [bool]$first.git_performed) 'Repair must not invoke Git.'
        Assert-True (-not [bool]$first.network_activity_performed) 'Repair itself must not perform network activity.'
        Assert-True (-not [bool]$first.target_contact_performed) 'Repair itself must not contact a target.'
        Assert-True (-not [bool]$first.target_mutation_performed) 'Repair itself must not mutate a target.'

        $entrypoint = Join-Path $runtime 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
        $module = Join-Path $runtime 'scripts\SasSoftwareDeploymentKerberosSmbHardBounded.psm1'
        $text = [IO.File]::ReadAllText($entrypoint)
        foreach ($marker in @(
            'TRANSPORT_OUTPUT_ROOT_COMPACTED',
            '$transportWindowsPathBudget = 240',
            'SasSoftwareDeploymentKerberosSmbHardBounded.psm1',
            'Invoke-SasSoftwareDeploymentKerberosSmbHardBoundedObservation',
            "reason_codes = @('observation_timeout','required_observation_missing')",
            'Probe timeout stage:',
            'probe_diagnostic = $probeDiagnostic'
        )) {
            Assert-True ($text.Contains($marker)) "Missing repaired entrypoint marker for $($case.name): $marker"
        }
        Assert-Parse -Path $entrypoint
        Assert-Parse -Path $module

        $second = & $repairScript `
            -RuntimeRoot $runtime `
            -HardBoundedModuleSourcePath $hardBoundedModule `
            -EvidenceRoot (Join-Path $runtime 'evidence-second') `
            -ConfirmRepair `
            -PassThru
        Assert-True ([string]$second.classification -eq 'KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_ALREADY_PRESENT') `
            "Repair is not idempotent for $($case.name): $($second.classification)"

        Write-Host "PASS: $($case.name) hard-bounded transport runtime repair"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host 'PASS: Kerberos SMB hard-bounded transport runtime repair contracts'
