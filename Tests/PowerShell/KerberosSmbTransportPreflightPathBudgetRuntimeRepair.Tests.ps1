#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repairScript = Join-Path $repoRoot 'scripts\Repair-SasKerberosSmbTransportPreflightRuntime.ps1'
$hardBoundedModule = Join-Path $repoRoot 'scripts\SasSoftwareDeploymentKerberosSmbHardBounded.psm1'
foreach ($required in @($repairScript,$hardBoundedModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing path-budget repair test dependency: $required"
    }
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Parse {
    param([Parameter(Mandatory = $true)][string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $errors | Format-List * | Out-Host
        throw "PowerShell parse failed: $Path"
    }
}

function New-PathBudgetTransportRuntimeFixture {
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
        '$transportOwnerLinkPath = $null',
        'Write-Warning ''TRANSPORT_OUTPUT_ROOT_COMPACTED: path-budget fixture sentinel''',
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
        'if (-not [string]::IsNullOrWhiteSpace([string]$transportOwnerLinkPath)) {',
        '    [pscustomobject][ordered]@{',
        '        schema_version = ''sas-software-deployment-transport-link/v1''',
        '        transport_run_root = $context.run_root',
        '        result_path = $resultPath',
        '        artifact_registry_path = $context.artifact_registry_path',
        '        network_activity_performed = $networkActivity',
        '        target_mutation_performed = $false',
        '    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $transportOwnerLinkPath -Encoding UTF8',
        '}',
        '$output = [pscustomobject]@{',
        '    run_root = $context.run_root',
        '    result_path = $resultPath',
        '    observations_path = $observationPath',
        '    low_noise_context_path = $lowNoisePath',
        '    english_summary_path = $summaryPath',
        '    artifact_registry_path = $context.artifact_registry_path',
        '    owner_link_path = $transportOwnerLinkPath',
        '    result = $result',
        '}',
        'if ($PassThru) {',
        '    return $output',
        '}',
        '$englishSummary'
    )

    $path = Join-Path $scripts 'Test-SasSoftwareDeploymentTransport.ps1'
    [IO.File]::WriteAllText(
        $path,
        ($lines -join $NewLine) + $NewLine,
        (New-Object Text.UTF8Encoding($false))
    )
    return $path
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-path-budget-transport-repair-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    foreach ($case in @(
        [pscustomobject]@{ name='crlf'; newline="`r`n" },
        [pscustomobject]@{ name='lf'; newline="`n" }
    )) {
        $runtime = Join-Path $tempRoot $case.name
        $entrypoint = New-PathBudgetTransportRuntimeFixture -Root $runtime -NewLine $case.newline
        $before = [IO.File]::ReadAllText($entrypoint)
        $artifactLine = '    artifact_registry_path = $context.artifact_registry_path'
        Assert-True (([regex]::Matches($before,[regex]::Escape($artifactLine))).Count -eq 2) `
            "Fixture must reproduce two artifact-registry assignments for $($case.name)."
        Assert-True ($before.Contains('TRANSPORT_OUTPUT_ROOT_COMPACTED')) 'Path-budget sentinel missing before repair.'
        Assert-True ($before.Contains('owner_link_path = $transportOwnerLinkPath')) 'Owner-link output field missing before repair.'

        $first = & $repairScript `
            -RuntimeRoot $runtime `
            -HardBoundedModuleSourcePath $hardBoundedModule `
            -EvidenceRoot (Join-Path $runtime 'evidence') `
            -ConfirmRepair `
            -PassThru

        Assert-True ([string]$first.classification -eq 'KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_APPLIED') `
            "Unexpected first repair classification for $($case.name): $($first.classification)"
        Assert-True ([bool]$first.hard_process_bounded) 'Hard process bound was not proven.'
        Assert-True (-not [bool]$first.network_activity_performed) 'Repair itself must not perform network activity.'
        Assert-True (-not [bool]$first.target_contact_performed) 'Repair itself must not contact a target.'
        Assert-True (-not [bool]$first.target_mutation_performed) 'Repair itself must not mutate a target.'

        $after = [IO.File]::ReadAllText($entrypoint)
        Assert-True (([regex]::Matches($after,[regex]::Escape($artifactLine))).Count -eq 2) `
            "Repair changed owner/output artifact-registry assignment count for $($case.name)."
        Assert-True (([regex]::Matches($after,[regex]::Escape('    probe_diagnostic = $probeDiagnostic'))).Count -eq 1) `
            "Repair must add exactly one PassThru probe diagnostic for $($case.name)."
        Assert-True ($after.Contains('TRANSPORT_OUTPUT_ROOT_COMPACTED')) 'Path-budget repair marker was not preserved.'
        Assert-True ($after.Contains('$transportWindowsPathBudget = 240')) 'Path-budget constant was not preserved.'
        Assert-True ($after.Contains('owner_link_path = $transportOwnerLinkPath')) 'Owner-link output field was not preserved.'

        $ownerStart = $after.IndexOf('if (-not [string]::IsNullOrWhiteSpace([string]$transportOwnerLinkPath)) {',[StringComparison]::Ordinal)
        $outputStart = $after.IndexOf('$output = [pscustomobject]@{',[StringComparison]::Ordinal)
        $probeField = $after.IndexOf('    probe_diagnostic = $probeDiagnostic',[StringComparison]::Ordinal)
        Assert-True ($ownerStart -ge 0 -and $outputStart -gt $ownerStart) 'Owner-link/output ordering was not preserved.'
        Assert-True ($probeField -gt $outputStart) 'Probe diagnostic was not scoped to the PassThru output object.'
        $ownerRegion = $after.Substring($ownerStart,$outputStart - $ownerStart)
        Assert-True (-not $ownerRegion.Contains('probe_diagnostic = $probeDiagnostic')) `
            'Probe diagnostic leaked into the path-budget owner-link object.'

        Assert-Parse -Path $entrypoint
        Assert-Parse -Path (Join-Path $runtime 'scripts\SasSoftwareDeploymentKerberosSmbHardBounded.psm1')

        $second = & $repairScript `
            -RuntimeRoot $runtime `
            -HardBoundedModuleSourcePath $hardBoundedModule `
            -EvidenceRoot (Join-Path $runtime 'evidence-second') `
            -ConfirmRepair `
            -PassThru
        Assert-True ([string]$second.classification -eq 'KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_ALREADY_PRESENT') `
            "Path-budget repair is not idempotent for $($case.name): $($second.classification)"

        Write-Host "PASS: $($case.name) path-budget owner-link runtime repair"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'PASS: path-budget owner-link hard-bounded transport runtime repair contracts'
