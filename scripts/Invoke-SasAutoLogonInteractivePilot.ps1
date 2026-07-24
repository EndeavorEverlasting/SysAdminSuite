#Requires -Version 5.1
<#
.SYNOPSIS
Run one bounded AutoLogon pilot in the already logged-on administrator's interactive session.

.DESCRIPTION
The approved no-argument AutoLogon EXE is not qualified for LocalSystem because a live SYSTEM
execution returned 0 without establishing AutoAdminLogon=1. This separate lane does not weaken or
promote that SYSTEM result. Instead it:

  network/preflight -> read-only SYSTEM baseline -> final-step gate -> exact pinned package staging
  -> InteractiveToken + HighestAvailable probe -> interactive installer execution
  -> read-only SYSTEM After capture -> task/staging cleanup -> pre-reboot state classification

No password is accepted or stored. The target user must already be logged on. The installer task
uses that existing interactive token and is required to prove that it is running elevated before
the installer starts. The workflow never reboots and never claims automatic sign-in proof.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$AuthorizedBy = 'field-authorized operator',
    [string]$RequestReference = 'field deployment',
    [string]$ChangeReference = 'field deployment',
    [string]$TicketReference = 'field deployment',
    [string]$TechnicianLabel = 'AutoLogon interactive-token pilot',

    [ValidateRange(1,1440)]
    [int]$PreflightMaxAgeMinutes = 15,
    [ValidateRange(30,3600)]
    [int]$InteractiveResultTimeoutSeconds = 900,
    [ValidateRange(10,600)]
    [int]$StateResultTimeoutSeconds = 120,

    [string]$OutputRoot,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmInteractive,
    [switch]$FixtureMode,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasInteractiveProperty {
    param($Value, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Value) { return $Default }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Write-SasInteractiveJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-SasInteractiveCaptureComplete {
    param($Lifecycle)
    return ($null -ne $Lifecycle -and [string]$Lifecycle.status -eq 'completed' -and
        [bool]$Lifecycle.worker.executed_as_system -and [bool]$Lifecycle.worker.hash_verified -and
        [bool]$Lifecycle.result_retrieval.succeeded -and [bool]$Lifecycle.cleanup.task_deletion_succeeded -and
        [bool]$Lifecycle.cleanup.run_root_deletion_succeeded -and -not [bool]$Lifecycle.cleanup.task_remaining -and
        -not [bool]$Lifecycle.cleanup.run_root_remaining)
}

function Test-SasInteractiveCleanBaseline {
    param($Snapshot)
    if ($null -eq $Snapshot -or [string]$Snapshot.autologon.status -ne 'not_configured') { return $false }
    $existing = @($Snapshot.installed_software | Where-Object { [string]$_.name -match '(?i)NW\s+AutoLogon\s+Setup' })
    return ($existing.Count -eq 0)
}

function Get-SasInteractiveAutoLogonPackage {
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$HarnessApiPath
    )
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') { throw 'Approved software catalog schema is unsupported.' }
    $matches = @($catalog.packages | Where-Object { [string]$_.id -eq 'autologon' })
    if ($matches.Count -ne 1) { throw 'Approved AutoLogon package is missing or ambiguous.' }
    $package = $matches[0]
    if (-not [bool]$package.install_enabled) { throw 'Approved AutoLogon package is disabled.' }
    if ([string]::IsNullOrWhiteSpace([string]$package.installer_file)) { throw 'Approved AutoLogon installer filename is not pinned.' }
    if ([string]$package.default_install_mode -ne 'CopyThenInstall') { throw 'AutoLogon interactive lane requires the approved CopyThenInstall package.' }
    if (@($package.default_installer_arguments).Count -ne 0) { throw 'AutoLogon interactive lane currently permits only the approved empty argument set.' }
    if ([string]$package.installer_arguments_policy -ne 'approved_empty') { throw 'AutoLogon catalog does not record the approved-empty argument policy.' }

    $root = ([string]$catalog.software_share_root).Trim().Replace('/', '\').TrimEnd('\') + '\'
    $api = Get-Content -LiteralPath $HarnessApiPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $approvedRoots = @($api.posture.approved_software_sources | ForEach-Object {
        ([string]$_).Trim().Replace('/', '\').TrimEnd('\') + '\'
    })
    if (@($approvedRoots | Where-Object { $_.Equals($root, [StringComparison]::OrdinalIgnoreCase) }).Count -ne 1) {
        throw 'AutoLogon software share root is not approved by the harness API.'
    }

    $relativeFolder = ([string]$package.source_folder_relative_path).Trim().Trim('\/').Replace('/', '\')
    $installer = ([string]$package.installer_file).Trim()
    if (-not $relativeFolder -or -not $installer -or $relativeFolder -match '(^|\)\.\.(\|$)' -or
        [IO.Path]::GetFileName($installer) -ne $installer) {
        throw 'AutoLogon catalog contains an unsafe package path.'
    }

    return [pscustomobject][ordered]@{
        id = 'autologon'
        display_name = [string]$package.display_name
        source_root = $root
        installer_relative_path = "$relativeFolder\$installer"
        installer_file = $installer
        installer_arguments = @()
        canonical_system_install_enabled = $(if ($null -ne $package.PSObject.Properties['canonical_system_install_enabled']) { [bool]$package.canonical_system_install_enabled } else { $true })
    }
}

function New-SasInteractiveWorker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Probe','Install')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$ExpectedUser,
        [Parameter(Mandatory = $true)][string]$ResultPath,
        [string]$InstallerPath,
        [string]$InstallerSha256
    )

    $config = [ordered]@{
        mode = $Mode
        expected_user = $ExpectedUser
        result_path = $ResultPath
        installer_path = $InstallerPath
        installer_sha256 = $InstallerSha256
    }
    $configJson = $config | ConvertTo-Json -Depth 8 -Compress
    $configBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configJson))

    $worker = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG_BASE64__'))) | ConvertFrom-Json
$result = [ordered]@{
    schema_version = 'sas-autologon-interactive-worker-result/v1'
    mode = [string]$config.mode
    started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    completed_at_utc = $null
    execution_identity_name = $null
    execution_identity_sid = $null
    user_interactive = $false
    session_id = -1
    is_administrator = $false
    identity_matches_expected = $false
    installer_sha256_verified = $false
    installer_exit_code = $null
    completed = $false
    error = $null
    default_password_value_collected = $false
}
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $result.execution_identity_name = [string]$identity.Name
    $result.execution_identity_sid = [string]$identity.User.Value
    $result.user_interactive = [Environment]::UserInteractive
    $result.session_id = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $result.is_administrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $result.identity_matches_expected = ([string]$identity.Name).Equals([string]$config.expected_user, [StringComparison]::OrdinalIgnoreCase)

    if (-not $result.user_interactive -or $result.session_id -le 0) { throw 'Task did not run in an interactive user session.' }
    if (-not $result.identity_matches_expected) { throw 'Interactive task identity does not match the logged-on user captured at baseline.' }
    if (-not $result.is_administrator) { throw 'Interactive task did not receive an elevated administrator token.' }

    if ([string]$config.mode -eq 'Install') {
        if (-not (Test-Path -LiteralPath ([string]$config.installer_path) -PathType Leaf)) { throw 'Staged AutoLogon installer is missing.' }
        $hash = (Get-FileHash -LiteralPath ([string]$config.installer_path) -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.installer_sha256_verified = $hash -eq ([string]$config.installer_sha256).ToLowerInvariant()
        if (-not $result.installer_sha256_verified) { throw 'Staged AutoLogon installer SHA-256 changed before execution.' }
        $process = Start-Process -FilePath ([string]$config.installer_path) -ArgumentList @() -Wait -PassThru
        $result.installer_exit_code = [int]$process.ExitCode
    }
    else {
        $result.installer_sha256_verified = $true
    }
    $result.completed = $true
}
catch {
    $result.error = $_.Exception.Message
}
finally {
    $result.completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    $parent = Split-Path -Parent ([string]$config.result_path)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = [string]$config.result_path + '.tmp'
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination ([string]$config.result_path) -Force
}
'@
    $worker.Replace('__CONFIG_BASE64__', $configBase64) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-SasInteractiveTask {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$WorkerPath,
        [Parameter(Mandatory = $true)][string]$RemoteResultUnc,
        [Parameter(Mandatory = $true)][string]$LocalResultPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $lifecycle = [ordered]@{
        task_name = $TaskName
        user_id = $UserId
        logon_type = 'InteractiveToken'
        run_level = 'HighestAvailable'
        created = $false
        started = $false
        result_retrieved = $false
        deleted = $false
        absent_verified = $false
        result = $null
        error = $null
    }
    $service = $null
    $folder = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect($Target)
        $folder = $service.GetFolder('\')
        $definition = $service.NewTask(0)
        $definition.RegistrationInfo.Description = 'SysAdminSuite one-time AutoLogon interactive-token pilot task'
        $definition.Settings.Enabled = $true
        $definition.Settings.AllowDemandStart = $true
        $definition.Settings.StartWhenAvailable = $true
        $definition.Settings.DisallowStartIfOnBatteries = $false
        $definition.Settings.StopIfGoingOnBatteries = $false
        $definition.Settings.ExecutionTimeLimit = 'PT45M'
        $definition.Principal.UserId = $UserId
        $definition.Principal.LogonType = 3
        $definition.Principal.RunLevel = 1
        $action = $definition.Actions.Create(0)
        $action.Path = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $action.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$WorkerPath`""
        $registered = $folder.RegisterTaskDefinition($TaskName, $definition, 6, $null, $null, 3, $null)
        $lifecycle.created = $true
        $null = $registered.Run($null)
        $lifecycle.started = $true

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (Test-Path -LiteralPath $RemoteResultUnc -PathType Leaf)) {
            if ((Get-Date) -ge $deadline) { throw "Timed out after $TimeoutSeconds seconds waiting for interactive task result." }
            Start-Sleep -Seconds 2
        }
        Copy-Item -LiteralPath $RemoteResultUnc -Destination $LocalResultPath -Force -ErrorAction Stop
        $result = Get-Content -LiteralPath $LocalResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$result.schema_version -ne 'sas-autologon-interactive-worker-result/v1') { throw 'Interactive worker returned an unsupported result schema.' }
        if ([bool]$result.default_password_value_collected) { throw 'Interactive worker violated the DefaultPassword non-collection contract.' }
        $lifecycle.result_retrieved = $true
        $lifecycle.result = $result
    }
    catch {
        $lifecycle.error = $_.Exception.Message
    }
    finally {
        try {
            if ($null -eq $service) {
                $service = New-Object -ComObject 'Schedule.Service'
                $service.Connect($Target)
            }
            if ($null -eq $folder) { $folder = $service.GetFolder('\') }
            try { $folder.DeleteTask($TaskName, 0); $lifecycle.deleted = $true }
            catch {
                try { $null = $folder.GetTask($TaskName) }
                catch { $lifecycle.deleted = $true }
            }
            try { $null = $folder.GetTask($TaskName); $lifecycle.absent_verified = $false }
            catch { $lifecycle.absent_verified = $true }
        }
        catch {
            if ($lifecycle.error) { $lifecycle.error = "$($lifecycle.error); task cleanup verification failed: $($_.Exception.Message)" }
            else { $lifecycle.error = "Task cleanup verification failed: $($_.Exception.Message)" }
        }
    }
    return [pscustomobject]$lifecycle
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $repoRoot 'configs\software-packages\approved-apps.json'
$harnessApiPath = Join-Path $repoRoot 'harness\api\sas-harness-api.json'
$preflightScript = Join-Path $PSScriptRoot 'Test-SasSoftwareDeploymentTransport.ps1'
$finalGateScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonFinalStepGate.ps1'
$stateModulePath = Join-Path $PSScriptRoot 'SasAutoLogonSmbStateRecovery.psm1'
$networkGuardModule = Join-Path $PSScriptRoot 'SasNetworkGuard.psm1'
$targetResolutionModule = Join-Path $PSScriptRoot 'SasTargetNameResolution.psm1'
foreach ($required in @($catalogPath,$harnessApiPath,$preflightScript,$finalGateScript,$stateModulePath,$networkGuardModule,$targetResolutionModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing interactive AutoLogon dependency: $required" }
}
Import-Module $stateModulePath -Force
Import-Module $targetResolutionModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\runs\autologon-interactive-token'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

if ($FixtureMode) {
    $fixtureRoot = Join-Path $OutputRoot 'fixture-autologon-interactive-token'
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $fixture = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-interactive-token-pilot-result/v1'
        classification = 'INTERACTIVE_TOKEN_FIXTURE_READY'
        fixture_mode = $true
        target_mutation_performed = $false
        network_activity_performed = $false
        task_logon_type = 'InteractiveToken'
        task_run_level = 'HighestAvailable'
        password_supplied_or_stored = $false
        default_password_value_collected = $false
        automatic_reboot_performed = $false
        automatic_sign_in_observed = $false
        proof_level = 'sanitized_fixture_contract'
        proof_ceiling = 'Fixture only; no live interactive token, installer execution, registry state, reboot, or automatic sign-in is proven.'
    }
    $fixturePath = Join-Path $fixtureRoot 'autologon_interactive_token_pilot_result.json'
    Write-SasInteractiveJson -Path $fixturePath -Value $fixture
    if ($PassThru) { return [pscustomobject]@{ classification=$fixture.classification; result_path=$fixturePath; result=$fixture } }
    Write-Host $fixture.classification -ForegroundColor Green
    return
}

$package = Get-SasInteractiveAutoLogonPackage -CatalogPath $catalogPath -HarnessApiPath $harnessApiPath
$runId = 'autologon-interactive-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$stateRunId = 'autologon-recovery-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$gateRunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $OutputRoot $runId
$evidenceRoot = Join-Path $runRoot 'evidence'
$actionsRoot = Join-Path $runRoot 'actions'
New-Item -ItemType Directory -Path $runRoot,$evidenceRoot,$actionsRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'autologon_interactive_token_pilot_result.json'

$classification = 'INTERACTIVE_TOKEN_PILOT_FAILED'
$errorMessage = $null
$preflightPath = $null
$baseline = $null
$after = $null
$gate = $null
$probeLifecycle = $null
$installLifecycle = $null
$sourceHash = $null
$targetHash = $null
$targetResolution = $null
$resolvedTarget = $null
$loggedOnUser = $null
$stagingCleanupVerified = $false
$installerExitCode = $null
$sourceHashVerified = $false
$afterReady = $false
$targetMutationPerformed = $false

try {
    Import-Module $networkGuardModule -Force
    Assert-SasNorthwellWifi

    $targetResolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
    if (@($targetResolution.addresses).Count -lt 1) { throw 'Target resolution returned no address.' }
    $resolvedTarget = [string]$targetResolution.fqdn
    Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'target_resolution.json') -Value $targetResolution

    Write-Host "Target: $resolvedTarget" -ForegroundColor Cyan
    Write-Host 'Mode: logged-on administrator InteractiveToken / HighestAvailable' -ForegroundColor Cyan
    Write-Host "Package: $($package.display_name)"
    Write-Host 'Canonical SYSTEM qualification remains blocked and is not being bypassed.' -ForegroundColor Yellow

    if (-not $AllowTargetMutation -or -not $ConfirmInteractive) {
        $ack = (Read-Host "Type INTERACTIVE $($targetResolution.short_name) to run the one-target AutoLogon pilot").Trim()
        if ($ack -cne "INTERACTIVE $($targetResolution.short_name)") { throw 'Interactive AutoLogon acknowledgement was not supplied.' }
        $AllowTargetMutation = $true
        $ConfirmInteractive = $true
    }

    $preflight = & $preflightScript -ComputerName $resolvedTarget -AllowNetworkActivity -TransportIntent kerberos_smb_task `
        -OutputRoot (Join-Path $runRoot 'preflight') -PassThru
    $preflightPath = [string]$preflight.result_path
    if ([string]$preflight.result.decision.classification -ne 'kerberos_smb_task_ready') {
        $classification = 'INTERACTIVE_TOKEN_TRANSPORT_BLOCKED'
        throw "Kerberos SMB/task preflight did not pass: $($preflight.result.decision.classification)"
    }

    $baseline = Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase baseline `
        -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path $evidenceRoot 'baseline') `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -ResultTimeoutSeconds $StateResultTimeoutSeconds
    Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'baseline_lifecycle.json') -Value $baseline
    if ($baseline.snapshot) { Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'baseline_snapshot.json') -Value $baseline.snapshot }
    if (-not (Test-SasInteractiveCaptureComplete -Lifecycle $baseline)) {
        $classification = 'INTERACTIVE_TOKEN_BASELINE_BLOCKED'
        throw "Baseline collection or cleanup failed: $($baseline.status). $($baseline.error)"
    }
    if (-not ([string]$baseline.snapshot.computer_name).Equals([string]$targetResolution.short_name, [StringComparison]::OrdinalIgnoreCase)) {
        $classification = 'INTERACTIVE_TOKEN_IDENTITY_BLOCKED'
        throw 'Baseline endpoint identity does not match the resolved target.'
    }
    if (-not (Test-SasInteractiveCleanBaseline -Snapshot $baseline.snapshot)) {
        $classification = 'INTERACTIVE_TOKEN_DIRTY_BASELINE'
        throw 'Target is not a clean AutoLogon baseline. Do not reinstall blindly.'
    }
    $loggedOnUser = [string]$baseline.snapshot.identity.logged_on_user
    if ([string]::IsNullOrWhiteSpace($loggedOnUser)) {
        $classification = 'INTERACTIVE_TOKEN_NO_LOGGED_ON_USER'
        throw 'No logged-on user session was captured. InteractiveToken execution cannot proceed.'
    }

    $beforeManifest = [pscustomobject][ordered]@{
        run_id = $gateRunId
        phase = 'before_complete'
        targets = @([pscustomobject]@{ computer_name=$resolvedTarget; hostname=$resolvedTarget })
        source_snapshot = (Join-Path $evidenceRoot 'baseline_snapshot.json')
    }
    $beforeManifestPath = Join-Path $actionsRoot 'interactive_before_manifest.json'
    Write-SasInteractiveJson -Path $beforeManifestPath -Value $beforeManifest
    $gateRoot = Join-Path $evidenceRoot 'final-gate'
    $gate = & $finalGateScript -Target $resolvedTarget -RunId $gateRunId -BeforeSnapshotPath $beforeManifestPath `
        -ApprovedAppsPath $catalogPath -OutputRoot $gateRoot -ExecContext remote -TechnicianLabel $TechnicianLabel
    if (-not [bool]$gate.overall_pass) {
        $classification = 'INTERACTIVE_TOKEN_FINAL_GATE_BLOCKED'
        throw "AutoLogon final-step gate blocked execution: $($gate.blocked_reason)"
    }

    $sourcePath = $package.source_root + $package.installer_relative_path
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $classification = 'INTERACTIVE_TOKEN_SOURCE_BLOCKED'
        throw "Approved AutoLogon installer is unavailable: $sourcePath"
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $cRoot = "\\$resolvedTarget\C$"
    if (-not (Test-Path -LiteralPath $cRoot -PathType Container)) {
        $classification = 'INTERACTIVE_TOKEN_TRANSPORT_BLOCKED'
        throw 'Target C$ administrative share is unavailable.'
    }
    $remoteWindowsRoot = "C:\ProgramData\SysAdminSuite\AutoLogonInteractive\$runId"
    $remoteUncRoot = Join-Path $cRoot "ProgramData\SysAdminSuite\AutoLogonInteractive\$runId"
    New-Item -ItemType Directory -Path $remoteUncRoot -Force | Out-Null
    $targetMutationPerformed = $true
    $remoteInstaller = Join-Path $remoteWindowsRoot $package.installer_file
    $remoteInstallerUnc = Join-Path $remoteUncRoot $package.installer_file
    Copy-Item -LiteralPath $sourcePath -Destination $remoteInstallerUnc -Force -ErrorAction Stop
    $targetHash = (Get-FileHash -LiteralPath $remoteInstallerUnc -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceHashVerified = $sourceHash -eq $targetHash
    if (-not $sourceHashVerified) {
        $classification = 'INTERACTIVE_TOKEN_STAGE_HASH_BLOCKED'
        throw 'Staged AutoLogon installer SHA-256 does not match the approved source copy.'
    }

    $probeWorkerLocal = Join-Path $actionsRoot 'interactive-probe-worker.ps1'
    $probeWorkerRemote = Join-Path $remoteWindowsRoot 'interactive-probe-worker.ps1'
    $probeWorkerRemoteUnc = Join-Path $remoteUncRoot 'interactive-probe-worker.ps1'
    $probeResultRemote = Join-Path $remoteWindowsRoot 'interactive-probe-result.json'
    $probeResultRemoteUnc = Join-Path $remoteUncRoot 'interactive-probe-result.json'
    $probeResultLocal = Join-Path $evidenceRoot 'interactive_probe_result.json'
    New-SasInteractiveWorker -Path $probeWorkerLocal -Mode Probe -ExpectedUser $loggedOnUser -ResultPath $probeResultRemote
    Copy-Item -LiteralPath $probeWorkerLocal -Destination $probeWorkerRemoteUnc -Force -ErrorAction Stop
    $probeTask = 'SysAdminSuite-AutoLogonInteractiveProbe-{0}' -f ([guid]::NewGuid().ToString('N'))
    $probeLifecycle = Invoke-SasInteractiveTask -Target $resolvedTarget -TaskName $probeTask -UserId $loggedOnUser `
        -WorkerPath $probeWorkerRemote -RemoteResultUnc $probeResultRemoteUnc -LocalResultPath $probeResultLocal `
        -TimeoutSeconds 120
    Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'interactive_probe_lifecycle.json') -Value $probeLifecycle
    if (-not $probeLifecycle.result_retrieved -or -not $probeLifecycle.deleted -or -not $probeLifecycle.absent_verified) {
        $classification = 'INTERACTIVE_TOKEN_PROBE_FAILED'
        throw "Interactive-token probe failed or cleanup was not verified: $($probeLifecycle.error)"
    }
    if (-not [bool]$probeLifecycle.result.completed -or -not [bool]$probeLifecycle.result.user_interactive -or
        -not [bool]$probeLifecycle.result.is_administrator -or -not [bool]$probeLifecycle.result.identity_matches_expected) {
        $classification = 'INTERACTIVE_TOKEN_NOT_ELEVATED'
        throw "Logged-on session is not a usable elevated interactive administrator token: $($probeLifecycle.result.error)"
    }

    $installWorkerLocal = Join-Path $actionsRoot 'interactive-install-worker.ps1'
    $installWorkerRemote = Join-Path $remoteWindowsRoot 'interactive-install-worker.ps1'
    $installWorkerRemoteUnc = Join-Path $remoteUncRoot 'interactive-install-worker.ps1'
    $installResultRemote = Join-Path $remoteWindowsRoot 'interactive-install-result.json'
    $installResultRemoteUnc = Join-Path $remoteUncRoot 'interactive-install-result.json'
    $installResultLocal = Join-Path $evidenceRoot 'interactive_install_result.json'
    New-SasInteractiveWorker -Path $installWorkerLocal -Mode Install -ExpectedUser $loggedOnUser -ResultPath $installResultRemote `
        -InstallerPath $remoteInstaller -InstallerSha256 $sourceHash
    Copy-Item -LiteralPath $installWorkerLocal -Destination $installWorkerRemoteUnc -Force -ErrorAction Stop
    $installTask = 'SysAdminSuite-AutoLogonInteractiveInstall-{0}' -f ([guid]::NewGuid().ToString('N'))

    Write-Host ''
    Write-Host "Starting AutoLogon in the logged-on elevated session: $loggedOnUser" -ForegroundColor Cyan
    Write-Host 'An installer window may appear on the target. Complete only the approved AutoLogon installer interaction if prompted.' -ForegroundColor Yellow
    $installLifecycle = Invoke-SasInteractiveTask -Target $resolvedTarget -TaskName $installTask -UserId $loggedOnUser `
        -WorkerPath $installWorkerRemote -RemoteResultUnc $installResultRemoteUnc -LocalResultPath $installResultLocal `
        -TimeoutSeconds $InteractiveResultTimeoutSeconds
    Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'interactive_install_lifecycle.json') -Value $installLifecycle
    if (-not $installLifecycle.result_retrieved -or -not $installLifecycle.deleted -or -not $installLifecycle.absent_verified) {
        $classification = 'INTERACTIVE_TOKEN_INSTALL_TASK_FAILED'
        throw "Interactive installer task failed or cleanup was not verified: $($installLifecycle.error)"
    }
    if (-not [bool]$installLifecycle.result.completed -or -not [bool]$installLifecycle.result.installer_sha256_verified) {
        $classification = 'INTERACTIVE_TOKEN_INSTALLER_FAILED'
        throw "Interactive installer worker failed: $($installLifecycle.result.error)"
    }
    $installerExitCode = [int]$installLifecycle.result.installer_exit_code
    if ($installerExitCode -notin @(0,3010)) {
        $classification = 'INTERACTIVE_TOKEN_INSTALLER_FAILED'
        throw "AutoLogon installer returned unsupported exit code $installerExitCode."
    }

    $after = Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase after `
        -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path $evidenceRoot 'after') `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -ResultTimeoutSeconds $StateResultTimeoutSeconds
    Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'after_lifecycle.json') -Value $after
    if ($after.snapshot) { Write-SasInteractiveJson -Path (Join-Path $evidenceRoot 'after_snapshot.json') -Value $after.snapshot }
    if (-not (Test-SasInteractiveCaptureComplete -Lifecycle $after)) {
        $classification = 'INTERACTIVE_TOKEN_AFTER_CAPTURE_FAILED'
        throw "After collection or cleanup failed: $($after.status). $($after.error)"
    }
    if (-not ([string]$after.snapshot.computer_name).Equals([string]$targetResolution.short_name, [StringComparison]::OrdinalIgnoreCase)) {
        $classification = 'INTERACTIVE_TOKEN_IDENTITY_BLOCKED'
        throw 'After endpoint identity does not match the resolved target.'
    }

    $post = $after.snapshot.autologon
    $afterReady = ([string]$post.postinstall_set_autologon -eq 'Autologon_YES' -and
        [string]$post.auto_admin_logon -eq '1' -and [bool]$post.default_password_present -and
        [bool]$post.expected_user_match -and [string]$post.status -eq 'autologon_ready')
    if (-not $afterReady) {
        $classification = 'INTERACTIVE_TOKEN_POSTCONDITION_FAILED'
        throw 'Interactive installer completed, but required pre-reboot AutoLogon registry postconditions were not established.'
    }

    $classification = 'INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING'
}
catch {
    $errorMessage = $_.Exception.Message
}
finally {
    if ($resolvedTarget -and $runId) {
        $remoteUncRoot = "\\$resolvedTarget\C$\ProgramData\SysAdminSuite\AutoLogonInteractive\$runId"
        try {
            if (Test-Path -LiteralPath $remoteUncRoot) { Remove-Item -LiteralPath $remoteUncRoot -Recurse -Force -ErrorAction Stop }
            $stagingCleanupVerified = -not (Test-Path -LiteralPath $remoteUncRoot)
        }
        catch {
            $stagingCleanupVerified = $false
            if ($errorMessage) { $errorMessage = "$errorMessage; interactive staging cleanup failed: $($_.Exception.Message)" }
            else { $errorMessage = "Interactive staging cleanup failed: $($_.Exception.Message)" }
        }
    }
}

if ($classification -eq 'INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING' -and -not $stagingCleanupVerified) {
    $classification = 'INTERACTIVE_TOKEN_CLEANUP_REVIEW_REQUIRED'
}

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-interactive-token-pilot-result/v1'
    run_id = $runId
    classification = $classification
    reason = $errorMessage
    fixture_mode = $false
    target = $resolvedTarget
    target_resolution = $targetResolution
    authorization = [pscustomobject][ordered]@{
        authorized_by = $AuthorizedBy
        request_reference = $RequestReference
        change_reference = $ChangeReference
        ticket_reference = $TicketReference
    }
    package = [pscustomobject][ordered]@{
        id = $package.id
        display_name = $package.display_name
        installer_file = $package.installer_file
        installer_arguments = @()
        source_sha256 = $sourceHash
        staged_sha256 = $targetHash
        source_target_hash_match = $sourceHashVerified
        canonical_system_install_enabled = $package.canonical_system_install_enabled
        canonical_system_qualification_changed = $false
    }
    logged_on_user = $loggedOnUser
    task_logon_type = 'InteractiveToken'
    task_run_level = 'HighestAvailable'
    password_supplied_or_stored = $false
    probe = $probeLifecycle
    install = $installLifecycle
    installer_exit_code = $installerExitCode
    preflight_result_path = $preflightPath
    final_step_gate_passed = ($gate -and [bool]$gate.overall_pass)
    before_snapshot_path = $(if ($baseline -and $baseline.snapshot) { Join-Path $evidenceRoot 'baseline_snapshot.json' } else { $null })
    after_snapshot_path = $(if ($after -and $after.snapshot) { Join-Path $evidenceRoot 'after_snapshot.json' } else { $null })
    pre_reboot_autologon_ready = $afterReady
    staging_cleanup_verified = $stagingCleanupVerified
    target_mutation_performed = $targetMutationPerformed
    network_activity_performed = $true
    default_password_value_collected = $false
    automatic_reboot_performed = $false
    automatic_sign_in_observed = $false
    proof_level = $(if ($classification -eq 'INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') { 'live_interactive_install_pre_reboot_state' } else { 'insufficient' })
    proof_ceiling = 'This lane can prove elevated InteractiveToken execution and required pre-reboot AutoLogon registry posture. It does not prove reboot completion, automatic sign-in, current-session identity after reboot, application behavior, or canonical LocalSystem compatibility.'
}
Write-SasInteractiveJson -Path $resultPath -Value $result

Write-Host ''
$color = if ($classification -eq 'INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') { 'Green' } else { 'Yellow' }
Write-Host "AutoLogon interactive pilot: $classification" -ForegroundColor $color
Write-Host "Evidence: $resultPath"
if ($classification -eq 'INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') {
    Write-Host 'Pre-reboot AutoLogon state is configured. Do not expand until an attended reboot proves automatic sign-in.' -ForegroundColor Green
}
else {
    Write-Host "Reason: $errorMessage" -ForegroundColor Yellow
}

if ($PassThru) { return [pscustomobject]@{ classification=$classification; result_path=$resultPath; result=$result } }
if ($classification -ne 'INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING') {
    throw "AutoLogon interactive-token pilot did not pass: $classification. $errorMessage"
}
