#Requires -Version 5.1
<#
.SYNOPSIS
Run a bounded AutoLogon technician runtime proof from the actual signed-in user session.

.DESCRIPTION
Loads a non-secret JSON config, verifies the current AutoLogon identity and required local/share
access through Invoke-SasAutoLogonSessionAccessProof.ps1, safely handles any pre-existing application
process, launches the configured executable without relying on terminal focus, waits for a bounded
ready signal, guides the technician through the approved disposable trigger, and writes a final JSON
and text artifact to an explicit evidence directory.

This runner does not accept credentials, automate personal/account/save mutation, create persistence,
or treat static/launcher/ACK evidence as proof of behavior. Live success is recorded only when the
actual session identity matches, current-token access succeeds, the target surface becomes ready,
and the technician records the expected behavior as observed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [switch]$FixtureMode,
    [switch]$NonInteractive,

    [string]$ObservedAck,
    [string]$ObservedBehavior,

    [ValidateSet('Pass', 'Fail')]
    [string]$ObservationResult
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function ConvertTo-SasBoolean {
    param([object]$Value, [bool]$Default = $false)

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes')) { return $true }
    if ($text -in @('false', '0', 'no')) { return $false }
    return $Default
}

function ConvertTo-SasAccountLeaf {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $leaf = $Value.Trim()
    if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
    if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
    return $leaf.TrimEnd('$').ToUpperInvariant()
}

function Assert-SasAbsolutePath {
    param(
        [string]$Value,
        [string]$Role
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Role is required." }
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Value)) {
        throw "$Role cannot contain wildcard characters: $Value"
    }
    if (@($Value -split '[\\/]') -contains '..') {
        throw "$Role cannot contain parent traversal segments: $Value"
    }
    if ($Value -notmatch '^[A-Za-z]:\\' -and $Value -notmatch '^\\\\[^\\]+\\[^\\]+') {
        throw "$Role must be drive-rooted or a complete UNC path: $Value"
    }
}

function Write-SasJson {
    param(
        [string]$Path,
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Set-SasStage {
    param(
        [hashtable]$State,
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )

    $State[$Name] = [ordered]@{
        status = $Status
        detail = $Detail
        recorded_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Wait-SasProcessAbsent {
    param(
        [string]$ProcessName,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count -eq 0) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Wait-SasApplicationReady {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Mode,
        [string]$WindowTitlePattern,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $Process.Refresh()
            if ($Process.HasExited) {
                return [pscustomobject]@{
                    ready = $false
                    detail = "Process exited with code $($Process.ExitCode) before target surface readiness."
                    window_title = ''
                }
            }

            $windowTitle = [string]$Process.MainWindowTitle
            $mainWindowPresent = $Process.MainWindowHandle -ne [IntPtr]::Zero
            $responding = $true
            try { $responding = [bool]$Process.Responding } catch { $responding = $true }

            $ready = switch ($Mode) {
                'ProcessAlive' { $true }
                'RespondingWindow' { $mainWindowPresent -and $responding }
                'WindowTitle' {
                    $mainWindowPresent -and $responding -and -not [string]::IsNullOrWhiteSpace($WindowTitlePattern) -and $windowTitle -match $WindowTitlePattern
                }
                default { $false }
            }

            if ($ready) {
                return [pscustomobject]@{
                    ready = $true
                    detail = "Target surface ready using mode $Mode."
                    window_title = $windowTitle
                }
            }
        }
        catch {
            return [pscustomobject]@{
                ready = $false
                detail = $_.Exception.Message
                window_title = ''
            }
        }

        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $deadline)

    return [pscustomobject]@{
        ready = $false
        detail = "Timed out after $TimeoutSeconds seconds waiting for target surface mode $Mode."
        window_title = ''
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Runtime proof config not found: $ConfigPath"
}

$rawConfig = Get-Content -LiteralPath $ConfigPath -Raw
if ($rawConfig -match '(?i)"[^"]*(password|secret|token|credential)[^"]*"\s*:') {
    throw 'Runtime proof config contains a forbidden secret/credential-like property name.'
}
$config = $rawConfig | ConvertFrom-Json

$schemaVersion = [string](Get-SasProperty -Object $config -Name 'schema_version' -Default '')
if ($schemaVersion -ne 'sas-autologon-technician-runtime-config/v1') {
    throw "Unsupported runtime proof config schema: $schemaVersion"
}

$expectedUserName = [string](Get-SasProperty -Object $config -Name 'expected_user_name' -Default $env:COMPUTERNAME)
$accessPaths = @((Get-SasProperty -Object $config -Name 'access_paths' -Default @()) | ForEach-Object { [string]$_ })
$evidenceDirectory = [string](Get-SasProperty -Object $config -Name 'evidence_directory' -Default '')
$applicationPath = [string](Get-SasProperty -Object $config -Name 'application_path' -Default '')
$applicationArguments = @((Get-SasProperty -Object $config -Name 'application_arguments' -Default @()) | ForEach-Object { [string]$_ })
$expectedProcessName = [string](Get-SasProperty -Object $config -Name 'expected_process_name' -Default '')
$surfaceReadyMode = [string](Get-SasProperty -Object $config -Name 'surface_ready_mode' -Default 'RespondingWindow')
$windowTitlePattern = [string](Get-SasProperty -Object $config -Name 'window_title_pattern' -Default '')
$stopExistingProcess = ConvertTo-SasBoolean -Value (Get-SasProperty -Object $config -Name 'stop_existing_process')
$safeToStopExistingProcess = ConvertTo-SasBoolean -Value (Get-SasProperty -Object $config -Name 'safe_to_stop_existing_process')
$stopTimeoutSeconds = [int](Get-SasProperty -Object $config -Name 'stop_timeout_seconds' -Default 15)
$readyTimeoutSeconds = [int](Get-SasProperty -Object $config -Name 'ready_timeout_seconds' -Default 60)
$retryCount = [int](Get-SasProperty -Object $config -Name 'access_retry_count' -Default 3)
$retryDelaySeconds = [int](Get-SasProperty -Object $config -Name 'access_retry_delay_seconds' -Default 5)
$allowWriteProbe = ConvertTo-SasBoolean -Value (Get-SasProperty -Object $config -Name 'allow_write_probe')
$disposableStateAcknowledged = ConvertTo-SasBoolean -Value (Get-SasProperty -Object $config -Name 'disposable_state_acknowledged')
$triggerDescription = [string](Get-SasProperty -Object $config -Name 'trigger_description' -Default '')
$expectedBehavior = [string](Get-SasProperty -Object $config -Name 'expected_behavior' -Default '')
$technicianLabel = [string](Get-SasProperty -Object $config -Name 'technician_label' -Default '')

if ($accessPaths.Count -eq 0) { throw 'Config must provide at least one access_paths entry.' }
if ($accessPaths.Count -gt 12) { throw 'Config access_paths exceeds the maximum of 12.' }
foreach ($accessPath in $accessPaths) { Assert-SasAbsolutePath -Value $accessPath -Role 'access path' }
Assert-SasAbsolutePath -Value $evidenceDirectory -Role 'evidence_directory'
Assert-SasAbsolutePath -Value $applicationPath -Role 'application_path'
if ($surfaceReadyMode -notin @('ProcessAlive', 'RespondingWindow', 'WindowTitle')) {
    throw "surface_ready_mode must be ProcessAlive, RespondingWindow, or WindowTitle: $surfaceReadyMode"
}
if ($surfaceReadyMode -eq 'WindowTitle' -and [string]::IsNullOrWhiteSpace($windowTitlePattern)) {
    throw 'window_title_pattern is required when surface_ready_mode is WindowTitle.'
}
if ($stopTimeoutSeconds -lt 1 -or $stopTimeoutSeconds -gt 120) { throw 'stop_timeout_seconds must be between 1 and 120.' }
if ($readyTimeoutSeconds -lt 1 -or $readyTimeoutSeconds -gt 180) { throw 'ready_timeout_seconds must be between 1 and 180.' }
if ($retryCount -lt 0 -or $retryCount -gt 5) { throw 'access_retry_count must be between 0 and 5.' }
if ($retryDelaySeconds -lt 1 -or $retryDelaySeconds -gt 30) { throw 'access_retry_delay_seconds must be between 1 and 30.' }
if (-not $disposableStateAcknowledged) {
    throw 'Config must explicitly set disposable_state_acknowledged to true.'
}
if ([string]::IsNullOrWhiteSpace($triggerDescription)) { throw 'trigger_description is required.' }
if ([string]::IsNullOrWhiteSpace($expectedBehavior)) { throw 'expected_behavior is required.' }

if ([string]::IsNullOrWhiteSpace($expectedProcessName)) {
    $expectedProcessName = [System.IO.Path]::GetFileNameWithoutExtension($applicationPath)
}
if ($expectedProcessName -notmatch '^[A-Za-z0-9._-]+$') {
    throw "expected_process_name contains unsupported characters: $expectedProcessName"
}

$sessionAccessScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasAutoLogonSessionAccessProof.ps1'
if (-not (Test-Path -LiteralPath $sessionAccessScript -PathType Leaf)) {
    throw "Missing repo-owned session access proof: $sessionAccessScript"
}

if ($FixtureMode) {
    if (-not (Test-Path -LiteralPath $evidenceDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
}
elseif (-not (Test-Path -LiteralPath $evidenceDirectory -PathType Container)) {
    throw "Evidence directory is unavailable from the current session: $evidenceDirectory"
}

$runId = 'autologon-runtime-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path -Path $evidenceDirectory -ChildPath $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$summaryPath = Join-Path -Path $runRoot -ChildPath 'runtime-proof-summary.json'
$logPath = Join-Path -Path $runRoot -ChildPath 'runtime-proof-chain.log'

$stages = [ordered]@{}
$summary = [ordered]@{
    schema_version = 'sas-autologon-technician-runtime-proof/v1'
    run_id = $runId
    started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    completed_at_utc = $null
    computer_name = $env:COMPUTERNAME
    expected_user_name = ConvertTo-SasAccountLeaf -Value $expectedUserName
    actual_identity = $null
    technician_label = $technicianLabel
    technician_identity_proven = $false
    fixture_mode = [bool]$FixtureMode
    disposable_state_acknowledged = $disposableStateAcknowledged
    personal_data_mutation_authorized = $false
    config_path = $ConfigPath
    application_path = $applicationPath
    application_argument_count = $applicationArguments.Count
    expected_process_name = $expectedProcessName
    surface_ready_mode = $surfaceReadyMode
    trigger_description = $triggerDescription
    expected_behavior = $expectedBehavior
    observed_ack = $null
    observed_behavior = $null
    observation_result = $null
    access_proof = $null
    process_id = $null
    window_title = $null
    proof_level = 'NOT_STARTED'
    runtime_proof = $false
    overall_success = $false
    failure_reason = $null
    artifact_directory = $runRoot
    stages = $stages
}

Write-SasJson -Path $summaryPath -Value $summary
$terminalError = $null
$launchedProcess = $null

try {
    Set-SasStage -State $stages -Name 'repo_floor' -Status 'PASS' -Detail 'Repo-owned session proof dependency and config schema are present.'

    if (-not $FixtureMode -and -not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
        throw "Application executable not found: $applicationPath"
    }

    $accessParams = @{
        Path = $accessPaths
        ExpectedUserName = $expectedUserName
        RetryCount = $retryCount
        RetryDelaySeconds = $retryDelaySeconds
        Confirm = $false
    }
    if ($allowWriteProbe) { $accessParams.AllowWriteProbe = $true }
    if ($FixtureMode) { $accessParams.FixtureMode = $true }

    $accessProof = & $sessionAccessScript @accessParams
    $summary.actual_identity = $accessProof.actual_identity
    $summary.access_proof = $accessProof
    if (-not $accessProof.overall_success) {
        Set-SasStage -State $stages -Name 'session_attach' -Status 'FAIL' -Detail "Session access proof decision: $($accessProof.decision)"
        throw "Current-session access proof failed with decision $($accessProof.decision)."
    }
    Set-SasStage -State $stages -Name 'session_attach' -Status 'PASS' -Detail "Identity matched and $($accessProof.confirmed_path_count) path(s) passed current-token access proof."

    if ($FixtureMode) {
        Set-SasStage -State $stages -Name 'safe_start' -Status 'PASS' -Detail 'Fixture simulated no pre-existing application process.'
        $summary.process_id = 4242
        Set-SasStage -State $stages -Name 'launcher_attach' -Status 'PASS' -Detail 'Fixture simulated Start-Process ACK with process id 4242.'
        $summary.window_title = 'Fixture target surface'
        Set-SasStage -State $stages -Name 'target_surface_ready' -Status 'PASS' -Detail "Fixture simulated target surface mode $surfaceReadyMode."
    }
    else {
        $existingProcesses = @(Get-Process -Name $expectedProcessName -ErrorAction SilentlyContinue)
        if ($existingProcesses.Count -gt 0) {
            if (-not $stopExistingProcess) {
                Set-SasStage -State $stages -Name 'safe_start' -Status 'FAIL' -Detail "Found $($existingProcesses.Count) pre-existing process(es); config did not authorize stopping them."
                throw "Pre-existing $expectedProcessName process blocks a clean runtime proof."
            }
            if (-not $safeToStopExistingProcess) {
                throw 'stop_existing_process requires safe_to_stop_existing_process=true.'
            }
            foreach ($existingProcess in $existingProcesses) {
                Stop-Process -Id $existingProcess.Id -Force -ErrorAction Stop
            }
            if (-not (Wait-SasProcessAbsent -ProcessName $expectedProcessName -TimeoutSeconds $stopTimeoutSeconds)) {
                throw "Timed out waiting for pre-existing $expectedProcessName process to stop."
            }
            Set-SasStage -State $stages -Name 'safe_start' -Status 'PASS' -Detail "Stopped $($existingProcesses.Count) explicitly authorized pre-existing process(es)."
        }
        else {
            Set-SasStage -State $stages -Name 'safe_start' -Status 'PASS' -Detail 'No pre-existing application process was present.'
        }

        if ($applicationArguments.Count -gt 0) {
            $launchedProcess = Start-Process -FilePath $applicationPath -ArgumentList $applicationArguments -PassThru
        }
        else {
            $launchedProcess = Start-Process -FilePath $applicationPath -PassThru
        }
        if ($null -eq $launchedProcess -or $launchedProcess.Id -le 0) {
            throw 'Start-Process did not return a valid process ACK.'
        }
        $summary.process_id = $launchedProcess.Id
        Set-SasStage -State $stages -Name 'launcher_attach' -Status 'PASS' -Detail "Start-Process ACK observed with process id $($launchedProcess.Id)."

        $readyResult = Wait-SasApplicationReady -Process $launchedProcess -Mode $surfaceReadyMode -WindowTitlePattern $windowTitlePattern -TimeoutSeconds $readyTimeoutSeconds
        $summary.window_title = $readyResult.window_title
        if (-not $readyResult.ready) {
            Set-SasStage -State $stages -Name 'target_surface_ready' -Status 'FAIL' -Detail $readyResult.detail
            throw $readyResult.detail
        }
        Set-SasStage -State $stages -Name 'target_surface_ready' -Status 'PASS' -Detail $readyResult.detail
    }

    Set-SasStage -State $stages -Name 'trigger_issued' -Status 'AWAITING_TECHNICIAN' -Detail $triggerDescription
    Write-Host ''
    Write-Host 'TARGET SURFACE READY' -ForegroundColor Green
    Write-Host "Trigger: $triggerDescription"
    Write-Host "Expected behavior: $expectedBehavior"
    Write-Host 'Perform only the approved disposable/non-persistent validation action. Do not use personal, patient, account, or production-save data.'
    Write-Host ''

    if ($FixtureMode) {
        if ([string]::IsNullOrWhiteSpace($ObservedAck)) { $ObservedAck = 'fixture-process-ack' }
        if ([string]::IsNullOrWhiteSpace($ObservedBehavior)) { $ObservedBehavior = 'Fixture observed the configured synthetic behavior.' }
        if ([string]::IsNullOrWhiteSpace($ObservationResult)) { $ObservationResult = 'Pass' }
    }
    elseif (-not $NonInteractive) {
        $ObservedAck = Read-Host 'Enter the command/route/application ACK observed, or N/A when not applicable'
        $ObservedBehavior = Read-Host 'Describe the behavior actually observed without personal data'
        do {
            $ObservationResult = Read-Host 'Enter Pass or Fail'
        } until ($ObservationResult -in @('Pass', 'Fail'))
    }

    if ([string]::IsNullOrWhiteSpace($ObservedAck)) {
        throw 'An ACK observation or explicit N/A is required.'
    }
    if ([string]::IsNullOrWhiteSpace($ObservedBehavior)) {
        throw 'A concrete observed-behavior description is required.'
    }
    if ($ObservationResult -notin @('Pass', 'Fail')) {
        throw 'ObservationResult must be Pass or Fail.'
    }

    $summary.observed_ack = $ObservedAck
    $summary.observed_behavior = $ObservedBehavior
    $summary.observation_result = $ObservationResult
    Set-SasStage -State $stages -Name 'command_ack' -Status 'OBSERVED' -Detail $ObservedAck

    if ($ObservationResult -eq 'Pass') {
        Set-SasStage -State $stages -Name 'behavior_observed' -Status 'PASS' -Detail $ObservedBehavior
        $summary.overall_success = $true
        $summary.runtime_proof = -not $FixtureMode
        $summary.proof_level = $(if ($FixtureMode) { 'FIXTURE_ONLY' } else { 'TECHNICIAN_OBSERVED_LIVE_RUNTIME' })
    }
    else {
        Set-SasStage -State $stages -Name 'behavior_observed' -Status 'FAIL' -Detail $ObservedBehavior
        $summary.proof_level = $(if ($FixtureMode) { 'FIXTURE_FAILED' } else { 'LIVE_RUNTIME_BEHAVIOR_FAILED' })
        throw "Technician observed behavior failure: $ObservedBehavior"
    }
}
catch {
    $terminalError = $_
    $summary.failure_reason = $_.Exception.Message
    if ($summary.proof_level -eq 'NOT_STARTED') {
        $summary.proof_level = $(if ($FixtureMode) { 'FIXTURE_FAILED' } else { 'LIVE_RUNTIME_INCOMPLETE' })
    }
}
finally {
    $summary.completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    Set-SasStage -State $stages -Name 'runtime_artifact' -Status 'PASS' -Detail "Final JSON and chain log written under $runRoot."
    Write-SasJson -Path $summaryPath -Value $summary

    @(
        "run_id=$runId",
        "proof_level=$($summary.proof_level)",
        "runtime_proof=$($summary.runtime_proof)",
        "overall_success=$($summary.overall_success)",
        "actual_identity=$($summary.actual_identity)",
        "process_id=$($summary.process_id)",
        "surface_ready_mode=$surfaceReadyMode",
        "observation_result=$($summary.observation_result)",
        "failure_reason=$($summary.failure_reason)",
        "summary_path=$summaryPath"
    ) | Set-Content -LiteralPath $logPath -Encoding UTF8
}

$result = [pscustomobject]$summary
Write-Output $result

if ($null -ne $terminalError) {
    throw $terminalError
}
