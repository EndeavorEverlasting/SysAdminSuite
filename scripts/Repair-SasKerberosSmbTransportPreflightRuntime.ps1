#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$HardBoundedModuleSourcePath,
    [string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmRepair) {
    throw 'Kerberos SMB transport preflight runtime repair requires -ConfirmRepair.'
}

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$entrypointPath = Join-Path $RuntimeRoot 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
$runtimeModulePath = Join-Path $RuntimeRoot 'scripts\SasSoftwareDeploymentKerberosSmbHardBounded.psm1'
if ([string]::IsNullOrWhiteSpace($HardBoundedModuleSourcePath)) {
    $HardBoundedModuleSourcePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentKerberosSmbHardBounded.psm1'
}
$HardBoundedModuleSourcePath = [IO.Path]::GetFullPath($HardBoundedModuleSourcePath)

foreach ($required in @($entrypointPath,$HardBoundedModuleSourcePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required transport repair surface missing: $required"
    }
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $RuntimeRoot 'runs\field-repair'
    }
    else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes'
    }
    $EvidenceRoot = Join-Path $base ('kerberos-smb-hard-bounded-preflight-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null

$entrypointBackup = Join-Path $EvidenceRoot 'Test-SasSoftwareDeploymentTransport.before.ps1'
$moduleBackup = Join-Path $EvidenceRoot 'SasSoftwareDeploymentKerberosSmbHardBounded.before.psm1'
$resultPath = Join-Path $EvidenceRoot 'kerberos-smb-hard-bounded-preflight-repair-result.json'

function Get-SasRepairHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-SasRepairParseText {
    param([Parameter(Mandatory = $true)][string]$Text,[Parameter(Mandatory = $true)][string]$Label)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "$Label does not parse: $((@($errors | ForEach-Object { $_.Message })) -join '; ')"
    }
}

function Assert-SasRepairParseFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "PowerShell parse failed for $Path`: $((@($errors | ForEach-Object { $_.Message })) -join '; ')"
    }
}

function Test-SasHardBoundedModuleSemantics {
    param([Parameter(Mandatory = $true)][string]$Text)
    return (
        $Text.Contains('function Invoke-SasSoftwareDeploymentKerberosSmbHardBoundedObservation') -and
        $Text.Contains('$process.WaitForExit($TimeoutSeconds * 1000)') -and
        $Text.Contains('$process.Kill()') -and
        $Text.Contains("timeoutStage = 'admin_share'") -and
        $Text.Contains("timeoutStage = 'schedule_service'") -and
        $Text.Contains("timeoutStage = 'scheduled_task_query'") -and
        $Text.Contains('child_process_isolation = $true') -and
        $Text.Contains('target_mutation_performed = $false')
    )
}

function Test-SasEntrypointSemantics {
    param([Parameter(Mandatory = $true)][string]$Text)
    return (
        $Text.Contains("`$hardBoundedKerberosSmbModulePath = Join-Path `$PSScriptRoot 'SasSoftwareDeploymentKerberosSmbHardBounded.psm1'") -and
        $Text.Contains('Import-Module $hardBoundedKerberosSmbModulePath -Force') -and
        $Text.Contains("`$TransportIntent -eq 'kerberos_smb_task' -and `$null -eq `$Credential") -and
        $Text.Contains('Invoke-SasSoftwareDeploymentKerberosSmbHardBoundedObservation') -and
        $Text.Contains("reason_codes = @('observation_timeout','required_observation_missing')") -and
        $Text.Contains('Probe timeout stage:') -and
        $Text.Contains('probe_diagnostic = $probeDiagnostic')
    )
}

function Insert-SasAfterUniqueLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Literal,
        [Parameter(Mandatory = $true)][string]$Insertion
    )
    $first = $Text.IndexOf($Literal,[StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Repair anchor missing: $Literal" }
    if ($Text.IndexOf($Literal,$first + $Literal.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Repair anchor is ambiguous: $Literal"
    }
    return $Text.Insert($first + $Literal.Length,$Insertion)
}

function Replace-SasUniqueRange {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartLiteral,
        [Parameter(Mandatory = $true)][string]$EndLiteral,
        [Parameter(Mandatory = $true)][string]$Replacement
    )
    $start = $Text.IndexOf($StartLiteral,[StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Repair start anchor missing: $StartLiteral" }
    $end = $Text.IndexOf($EndLiteral,$start + $StartLiteral.Length,[StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Repair end anchor missing: $EndLiteral" }
    if ($Text.IndexOf($StartLiteral,$start + $StartLiteral.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Repair start anchor is ambiguous: $StartLiteral"
    }
    return $Text.Substring(0,$start) + $Replacement + $Text.Substring($end)
}

function Insert-SasAfterLiteralInUniqueRange {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartLiteral,
        [Parameter(Mandatory = $true)][string]$EndLiteral,
        [Parameter(Mandatory = $true)][string]$Literal,
        [Parameter(Mandatory = $true)][string]$Insertion
    )

    $start = $Text.IndexOf($StartLiteral,[StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Repair range start missing: $StartLiteral" }
    if ($Text.IndexOf($StartLiteral,$start + $StartLiteral.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Repair range start is ambiguous: $StartLiteral"
    }

    $end = $Text.IndexOf($EndLiteral,$start + $StartLiteral.Length,[StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Repair range end missing after $StartLiteral`: $EndLiteral" }

    $rangeLength = $end - $start
    $rangeText = $Text.Substring($start,$rangeLength)
    $relative = $rangeText.IndexOf($Literal,[StringComparison]::Ordinal)
    if ($relative -lt 0) { throw "Repair anchor missing inside $StartLiteral range: $Literal" }
    if ($rangeText.IndexOf($Literal,$relative + $Literal.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Repair anchor is ambiguous inside $StartLiteral range: $Literal"
    }

    $absolute = $start + $relative + $Literal.Length
    return $Text.Insert($absolute,$Insertion)
}

$sourceModuleText = [IO.File]::ReadAllText($HardBoundedModuleSourcePath)
Assert-SasRepairParseText -Text $sourceModuleText -Label 'Hard-bounded source module'
if (-not (Test-SasHardBoundedModuleSemantics -Text $sourceModuleText)) {
    throw 'Hard-bounded source module semantic verification failed.'
}

$originalEntrypoint = [IO.File]::ReadAllText($entrypointPath)
$entrypointBeforeSha = Get-SasRepairHash -Path $entrypointPath
$moduleBeforeSha = if (Test-Path -LiteralPath $runtimeModulePath -PathType Leaf) { Get-SasRepairHash -Path $runtimeModulePath } else { $null }
$changed = $false
$classification = 'KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_ALREADY_PRESENT'

if ((Test-SasEntrypointSemantics -Text $originalEntrypoint) -and
    (Test-Path -LiteralPath $runtimeModulePath -PathType Leaf) -and
    (Test-SasHardBoundedModuleSemantics -Text ([IO.File]::ReadAllText($runtimeModulePath)))) {
    Assert-SasRepairParseFile -Path $entrypointPath
    Assert-SasRepairParseFile -Path $runtimeModulePath
}
else {
    Copy-Item -LiteralPath $entrypointPath -Destination $entrypointBackup -Force
    if (Test-Path -LiteralPath $runtimeModulePath -PathType Leaf) {
        Copy-Item -LiteralPath $runtimeModulePath -Destination $moduleBackup -Force
    }

    try {
        $newLine = if ($originalEntrypoint.Contains("`r`n")) { "`r`n" } else { "`n" }
        $text = $originalEntrypoint.Replace("`r`n","`n").Replace("`r","`n")

        if (-not $text.Contains('$hardBoundedKerberosSmbModulePath')) {
            $text = Insert-SasAfterUniqueLiteral -Text $text `
                -Literal "`$lowNoiseTransportModulePath = Join-Path `$PSScriptRoot 'SasSoftwareDeploymentLowNoise.psm1'" `
                -Insertion "`n`$hardBoundedKerberosSmbModulePath = Join-Path `$PSScriptRoot 'SasSoftwareDeploymentKerberosSmbHardBounded.psm1'"
        }
        if (-not $text.Contains('Import-Module $hardBoundedKerberosSmbModulePath -Force')) {
            $text = Insert-SasAfterUniqueLiteral -Text $text `
                -Literal 'Import-Module $lowNoiseTransportModulePath -Force' `
                -Insertion "`nImport-Module `$hardBoundedKerberosSmbModulePath -Force"
        }

        $replacement = @'
$probeDiagnostic = [pscustomobject]@{
    engine = 'fixture'
    timeout_stage = ''
    per_operation_timeout_seconds = $TimeoutSeconds
    child_process_isolation = $false
    target_identifier_emitted = $false
    username_emitted = $false
    credential_emitted = $false
    target_mutation_performed = $false
}

if ($FixtureMode) {
    $fixture = Get-Content -LiteralPath $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($null -eq $fixture.observations) { throw 'Fixture must contain an observations object.' }
    $observations = $fixture.observations
    $evidenceClass = 'sanitized_fixture'
    $networkActivity = $false
}
else {
    $observationParameters = @{
        ComputerName = $ComputerName
        TimeoutSeconds = $TimeoutSeconds
    }
    if ($PSBoundParameters.ContainsKey('Credential')) { $observationParameters.Credential = $Credential }

    if ($TransportIntent -eq 'kerberos_smb_task' -and $null -eq $Credential) {
        $hardBounded = Invoke-SasSoftwareDeploymentKerberosSmbHardBoundedObservation `
            -ComputerName $ComputerName `
            -TimeoutSeconds $TimeoutSeconds
        $observations = $hardBounded.observations
        $probeDiagnostic = $hardBounded.diagnostic
    }
    elseif ($TransportIntent -eq 'auto') {
        $observations = Invoke-SasSoftwareDeploymentTransportObservation @observationParameters
        $probeDiagnostic.engine = 'explicit_broad_collector'
    }
    else {
        $observationParameters.TransportIntent = $TransportIntent
        $observations = Invoke-SasSoftwareDeploymentLowNoiseObservation @observationParameters
        $probeDiagnostic.engine = 'credential_or_winrm_low_noise'
    }
    $evidenceClass = 'operator_local_live'
    $networkActivity = $true
}

'@
        $observationStart = 'if ($FixtureMode) {' + "`n" + '    $fixture = Get-Content -LiteralPath $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json'
        $text = Replace-SasUniqueRange -Text $text `
            -StartLiteral $observationStart `
            -EndLiteral '$result = New-SasSoftwareDeploymentTransportResult' `
            -Replacement $replacement

        if (-not $text.Contains("reason_codes = @('observation_timeout','required_observation_missing')")) {
            # Replace the complete unique result region. The shorter
            # -NetworkActivityPerformed token is intentionally repeated later in the file.
            $resultRegion = @'
$result = New-SasSoftwareDeploymentTransportResult `
    -Observations $observations `
    -EvidenceClass $evidenceClass `
    -NetworkActivityPerformed $networkActivity

if (-not [string]::IsNullOrWhiteSpace([string]$probeDiagnostic.timeout_stage)) {
    $result.decision.classification = 'inconclusive'
    $result.decision.selected_transport = 'none'
    $result.decision.reason_codes = @('observation_timeout','required_observation_missing')
    $result.proof.preflight_complete = $false
    $result.proof.transport_authorization_proven = $false
}

'@
            $text = Replace-SasUniqueRange -Text $text `
                -StartLiteral '$result = New-SasSoftwareDeploymentTransportResult' `
                -EndLiteral '$testedPorts = @()' `
                -Replacement $resultRegion
        }

        $nextActionReplacement = @'
$nextAction = if (-not [string]::IsNullOrWhiteSpace([string]$probeDiagnostic.timeout_stage)) {
    "A hard-bounded transport read timed out at $($probeDiagnostic.timeout_stage). Keep the target unmodified and review the VPN/ACL path before another deployment attempt."
}
elseif ($result.decision.classification -in @('kerberos_smb_task_ready', 'winrm_ready')) {
    'Review the schema-valid result and obtain separate authorization before any target mutation.'
}
else {
    'Review the fail-closed classification; do not broaden ports or retry without a recorded reason.'
}
'@
        $text = Replace-SasUniqueRange -Text $text `
            -StartLiteral '$nextAction = if (' `
            -EndLiteral '$lowNoiseContext = New-SasLowNoiseContextObject' `
            -Replacement ($nextActionReplacement + "`n")

        if (-not $text.Contains('Probe timeout stage:')) {
            $text = Insert-SasAfterUniqueLiteral -Text $text `
                -Literal "    'Software deployment transport preflight'" `
                -Insertion "`n    `"Probe engine: `$(`$probeDiagnostic.engine)`"`n    `"Hard child-process isolation: `$(`$probeDiagnostic.child_process_isolation)`"`n    `"Probe timeout stage: `$(if ([string]::IsNullOrWhiteSpace([string]`$probeDiagnostic.timeout_stage)) { 'none' } else { [string]`$probeDiagnostic.timeout_stage })`""
        }
        if (-not $text.Contains('probe_diagnostic = $probeDiagnostic')) {
            $text = Insert-SasAfterLiteralInUniqueRange -Text $text `
                -StartLiteral '$output = [pscustomobject]@{' `
                -EndLiteral 'if ($PassThru) {' `
                -Literal '    artifact_registry_path = $context.artifact_registry_path' `
                -Insertion "`n    probe_diagnostic = `$probeDiagnostic"
        }

        if ($newLine -eq "`r`n") { $text = $text.Replace("`n","`r`n") }
        Assert-SasRepairParseText -Text $text -Label 'Repaired transport entrypoint'
        if (-not (Test-SasEntrypointSemantics -Text $text)) {
            throw 'Repaired transport entrypoint semantic verification failed.'
        }

        [IO.File]::WriteAllText($entrypointPath,$text,(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($runtimeModulePath,$sourceModuleText,(New-Object Text.UTF8Encoding($false)))
        Assert-SasRepairParseFile -Path $entrypointPath
        Assert-SasRepairParseFile -Path $runtimeModulePath
        $changed = $true
        $classification = 'KERBEROS_SMB_HARD_BOUNDED_RUNTIME_REPAIR_APPLIED'
    }
    catch {
        Copy-Item -LiteralPath $entrypointBackup -Destination $entrypointPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $moduleBackup -PathType Leaf) {
            Copy-Item -LiteralPath $moduleBackup -Destination $runtimeModulePath -Force -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $runtimeModulePath -PathType Leaf) {
            Remove-Item -LiteralPath $runtimeModulePath -Force -ErrorAction SilentlyContinue
        }
        throw "KERBEROS SMB HARD-BOUNDED PREFLIGHT REPAIR FAILED; ORIGINAL RESTORED. $($_.Exception.Message)"
    }
}

$finalEntrypoint = [IO.File]::ReadAllText($entrypointPath)
$finalModule = [IO.File]::ReadAllText($runtimeModulePath)
if (-not (Test-SasEntrypointSemantics -Text $finalEntrypoint) -or
    -not (Test-SasHardBoundedModuleSemantics -Text $finalModule)) {
    throw 'Hard-bounded transport repair markers are absent after repair.'
}
Assert-SasRepairParseFile -Path $entrypointPath
Assert-SasRepairParseFile -Path $runtimeModulePath

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-kerberos-smb-hard-bounded-preflight-runtime-repair/v1'
    status = 'COMPLETED'
    classification = $classification
    runtime_root = $RuntimeRoot
    entrypoint_path = $entrypointPath
    module_path = $runtimeModulePath
    changed = $changed
    entrypoint_before_sha256 = $entrypointBeforeSha
    entrypoint_after_sha256 = Get-SasRepairHash -Path $entrypointPath
    module_before_sha256 = $moduleBeforeSha
    module_after_sha256 = Get-SasRepairHash -Path $runtimeModulePath
    hard_process_bounded = $true
    default_no_credential_kerberos_smb_routed = $true
    timeout_stage_diagnostic_enabled = $true
    powershell_parse_passed = $true
    semantic_verification = $true
    git_performed = $false
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    evidence_path = $resultPath
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($PassThru) { return $result }
Write-Host $result.classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"