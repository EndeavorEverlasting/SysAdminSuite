#Requires -Version 5.1
<#
.SYNOPSIS
Executes one authorized package only inside a disconnected disposable Hyper-V guest.

.DESCRIPTION
Validates a READY_FOR_VM package qualification profile, re-verifies the package hash,
restores a clean Hyper-V checkpoint, uses PowerShell Direct to execute the package in
the guest, runs an approved acceptance script, exports ignored local evidence, and
restores the checkpoint. Package code never executes on the admin box.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][string]$QualificationProfilePath,
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$VmName,
    [Parameter(Mandatory = $true)][string]$CheckpointName,
    [Parameter(Mandatory = $true)][string]$AcceptanceScriptPath,
    [Parameter(Mandatory = $false)][System.Management.Automation.PSCredential]$Credential,
    [Parameter(Mandatory = $false)][string]$OutputRoot,
    [Parameter(Mandatory = $false)][switch]$AllowVmMutation,
    [Parameter(Mandatory = $false)][switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasUtcNow { (Get-Date).ToUniversalTime().ToString('o') }
function Write-SasVmEvent {
    param([string]$Path, [hashtable]$Value)
    $Value.timestamp_utc = Get-SasUtcNow
    $Value | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}
function Get-SasGuestBaseline {
    @{
        applications = @(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher | Sort-Object DisplayName)
        services = @(Get-CimInstance Win32_Service | Select-Object Name, State, StartMode | Sort-Object Name)
        reboot_pending = [bool]((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$profileValidator = Join-Path $repoRoot 'tools/package-analysis/validate_vm_qualification_profile.py'
$targetIntakeModule = Join-Path $PSScriptRoot 'SasTargetIntake.psm1'
Import-Module -Name $targetIntakeModule -Force
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'survey/output/package-vm-execution' }
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'package VM execution output directory'

foreach ($requiredPath in @($QualificationProfilePath, $InstallerPath, $AcceptanceScriptPath, $profileValidator)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required file missing: $requiredPath" }
    $requiredItem = Get-Item -LiteralPath $requiredPath -Force
    if (($requiredItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point input is forbidden: $requiredPath" }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python is required to validate the qualification profile.' }
$validatorOutput = & $python.Source $profileValidator --profile $QualificationProfilePath 2>&1
if ($LASTEXITCODE -ne 0) { throw "Qualification profile validation failed: $($validatorOutput -join ' ')" }

$profile = Get-Content -LiteralPath $QualificationProfilePath -Raw | ConvertFrom-Json
if ($profile.decision.status -ne 'ready_for_authorized_vm_run' -or @($profile.decision.blockers).Count -ne 0) { throw 'Profile is not ready_for_authorized_vm_run with zero blockers.' }
if ($profile.execution_contract.execution_authorized -ne $true -or [string]::IsNullOrWhiteSpace([string]$profile.execution_contract.authorization_reference)) { throw 'Profile does not contain explicit execution authorization.' }
if ($profile.guest.provider -ne 'hyper_v' -or $profile.guest.network_mode -ne 'disconnected' -or $profile.guest.snapshot_strategy -ne 'clean_checkpoint') { throw 'Initial runtime requires Hyper-V, disconnected networking, and clean_checkpoint rollback.' }
if ($profile.guest.host_execution_forbidden -ne $true -or $profile.guest.autologon_allowed -ne $false -or $profile.guest.shared_clipboard_allowed -ne $false -or $profile.guest.shared_folders_allowed -ne $false) { throw 'Unsafe guest posture in qualification profile.' }
if ($profile.rollback.mode -ne 'checkpoint_revert' -or $profile.rollback.required -ne $true) { throw 'Initial runtime requires checkpoint_revert rollback.' }
if ($profile.acceptance.criteria_status -ne 'approved') { throw 'Approved application acceptance criteria are required.' }
if ($profile.execution_contract.installer_type -notin @('exe','msi')) { throw 'Initial runtime supports only EXE and MSI installers.' }

$hostHashBefore = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hostHashBefore -ne ([string]$profile.package_selector.source_sha256).ToLowerInvariant()) { throw 'Installer SHA-256 does not match the qualified package selector.' }

if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowVmMutation) { throw 'Refusing VM mutation without -AllowVmMutation. Use -WhatIf or -FixtureMode for non-runtime validation.' }
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $Credential) { throw 'A runtime-only guest PSCredential is required for Hyper-V PowerShell Direct.' }

$runId = 'package-vm-run-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force -WhatIf:$false | Out-Null
$eventPath = Join-Path $runRoot 'package_vm_execution_events.jsonl'
$resultPath = Join-Path $runRoot 'package_vm_execution_result.json'
$handoffPath = Join-Path $runRoot 'operator_handoff.txt'
$started = Get-SasUtcNow
$errors = New-Object System.Collections.Generic.List[string]
$vmStarted = $false
$packageExecuted = $false
$installerExitCode = $null
$rebootPerformed = $false
$acceptancePassed = $false
$rollbackAttempted = $false
$rollbackSucceeded = $false
$checkpointRestored = $false
$guestStagingRemoved = $false
$initialState = 'not_observed'
$finalState = 'not_observed'
$session = $null
$guestRunRoot = "C:\ProgramData\SysAdminSuite\PackageVmRun\$runId"

Write-SasVmEvent -Path $eventPath -Value @{ event='run_started'; run_id=$runId; profile_id=$profile.profile_id; fixture_mode=[bool]$FixtureMode; authorization_reference=$profile.execution_contract.authorization_reference }

try {
    if ($FixtureMode -or $WhatIfPreference) {
        Write-SasVmEvent -Path $eventPath -Value @{ event='runtime_skipped'; reason=$(if($FixtureMode){'fixture_mode'}else{'what_if'}) }
    }
    else {
        foreach ($command in @('Get-VM','Get-VMSnapshot','Restore-VMSnapshot','Start-VM','Stop-VM','Get-VMNetworkAdapter')) {
            if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Hyper-V command unavailable: $command" }
        }
        $vm = Get-VM -Name $VmName -ErrorAction Stop
        $initialState = [string]$vm.State
        if ($vm.State -ne 'Off') { throw 'Disposable VM must be powered off before the run.' }
        $connectedAdapters = @(Get-VMNetworkAdapter -VMName $VmName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.SwitchName) })
        if ($connectedAdapters.Count -ne 0) { throw 'Disposable VM has a connected network adapter; disconnect every adapter before execution.' }
        $checkpoint = Get-VMSnapshot -VMName $VmName -Name $CheckpointName -ErrorAction Stop
        if (-not $PSCmdlet.ShouldProcess("Hyper-V VM '$VmName'", "Restore checkpoint, start guest, execute one package, accept, stop, and restore checkpoint")) { throw 'Operator declined VM execution.' }
        Restore-VMSnapshot -VMName $VmName -Name $CheckpointName -Confirm:$false -ErrorAction Stop
        Start-VM -Name $VmName -ErrorAction Stop | Out-Null
        $vmStarted = $true
        Write-SasVmEvent -Path $eventPath -Value @{ event='vm_started'; vm_name=$VmName; checkpoint=$CheckpointName }
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 3
            $heartbeat = Get-VMIntegrationService -VMName $VmName -Name 'Heartbeat' -ErrorAction SilentlyContinue
        } until (($heartbeat -and $heartbeat.PrimaryStatusDescription -eq 'OK') -or (Get-Date) -ge $deadline)
        if (-not $heartbeat -or $heartbeat.PrimaryStatusDescription -ne 'OK') { throw 'Guest heartbeat did not become ready within three minutes.' }
        $session = New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
        $baseline = Invoke-Command -Session $session -ScriptBlock ${function:Get-SasGuestBaseline}
        Invoke-Command -Session $session -ScriptBlock { param($Path) New-Item -ItemType Directory -Path $Path -Force | Out-Null } -ArgumentList $guestRunRoot
        $guestInstaller = Join-Path $guestRunRoot (Split-Path -Leaf $InstallerPath)
        $guestAcceptance = Join-Path $guestRunRoot 'acceptance.ps1'
        Copy-Item -LiteralPath $InstallerPath -Destination $guestInstaller -ToSession $session -Force
        Copy-Item -LiteralPath $AcceptanceScriptPath -Destination $guestAcceptance -ToSession $session -Force
        $guestHash = Invoke-Command -Session $session -ScriptBlock { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } -ArgumentList $guestInstaller
        if ($guestHash -ne $hostHashBefore) { throw 'Guest-staged package hash mismatch.' }
        $arguments = @($profile.execution_contract.supported_arguments | ForEach-Object { [string]$_ })
        $installerType = [string]$profile.execution_contract.installer_type
        $guestInstall = {
            param($Installer,$InstallerType,[string[]]$Arguments)
            if ($InstallerType -eq 'msi') {
                $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList (@('/i',$Installer) + $Arguments) -Wait -PassThru
            } else {
                $process = Start-Process -FilePath $Installer -ArgumentList $Arguments -Wait -PassThru
            }
            [int]$process.ExitCode
        }
        $installerExitCode = Invoke-Command -Session $session -ScriptBlock $guestInstall -ArgumentList $guestInstaller,$installerType,$arguments
        $packageExecuted = $true
        Write-SasVmEvent -Path $eventPath -Value @{ event='installer_completed'; exit_code=$installerExitCode }
        if ($installerExitCode -notin @(0,1641,3010)) { throw "Installer returned unsupported exit code: $installerExitCode" }
        $pendingAfterInstall = Invoke-Command -Session $session -ScriptBlock { [bool]((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) }
        $rebootRequired = ($installerExitCode -in @(1641,3010)) -or ($profile.execution_contract.reboot_expected -eq 'required') -or (($profile.execution_contract.reboot_expected -eq 'possible') -and $pendingAfterInstall)
        if ($rebootRequired) {
            try { Invoke-Command -Session $session -ScriptBlock { Restart-Computer -Force } -ErrorAction SilentlyContinue } catch { }
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            $session = $null
            Start-Sleep -Seconds 10
            $deadline = (Get-Date).AddMinutes(5)
            do {
                Start-Sleep -Seconds 5
                try { $session = New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop } catch { $session = $null }
            } until ($session -or (Get-Date) -ge $deadline)
            if (-not $session) { throw 'Guest did not return after required reboot.' }
            $rebootPerformed = $true
        }
        $acceptanceJson = Invoke-Command -Session $session -ScriptBlock { param($Path) $acceptanceScript = [scriptblock]::Create((Get-Content -LiteralPath $Path -Raw)); (& $acceptanceScript | ConvertTo-Json -Depth 20 -Compress) } -ArgumentList $guestAcceptance
        $acceptance = $acceptanceJson | ConvertFrom-Json
        if ($null -eq $acceptance.passed -or $null -eq $acceptance.checks) { throw 'Acceptance script did not return the required passed/checks object.' }
        $acceptancePassed = [bool]$acceptance.passed
        if (-not $acceptancePassed) { throw 'Package-specific application acceptance failed.' }
        $post = Invoke-Command -Session $session -ScriptBlock ${function:Get-SasGuestBaseline}
        Write-SasVmEvent -Path $eventPath -Value @{ event='acceptance_passed'; checks=@($acceptance.checks).Count; application_count_before=@($baseline.applications).Count; application_count_after=@($post.applications).Count; service_count_before=@($baseline.services).Count; service_count_after=@($post.services).Count }
    }
}
catch {
    $errors.Add($_.Exception.Message)
    Write-SasVmEvent -Path $eventPath -Value @{ event='run_failed'; message=$_.Exception.Message }
}
finally {
    if (-not $FixtureMode -and -not $WhatIfPreference) {
        $rollbackAttempted = $true
        try {
            if ($session) {
                Invoke-Command -Session $session -ScriptBlock { param($Path) if(Test-Path -LiteralPath $Path){Remove-Item -LiteralPath $Path -Recurse -Force} } -ArgumentList $guestRunRoot -ErrorAction Stop
                $guestStagingRemoved = $true
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                $session = $null
            }
            $vm = Get-VM -Name $VmName -ErrorAction Stop
            if ($vm.State -ne 'Off') { Stop-VM -Name $VmName -TurnOff -Confirm:$false -ErrorAction Stop }
            Restore-VMSnapshot -VMName $VmName -Name $CheckpointName -Confirm:$false -ErrorAction Stop
            $checkpointRestored = $true
            $guestStagingRemoved = ($guestStagingRemoved -or $checkpointRestored)
            $finalState = [string](Get-VM -Name $VmName -ErrorAction Stop).State
            $rollbackSucceeded = ($finalState -eq 'Off' -and $checkpointRestored -and $guestStagingRemoved)
        }
        catch {
            $errors.Add("rollback_failed:$($_.Exception.Message)")
            $rollbackSucceeded = $false
        }
    }
}

$hostHashAfter = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hostHashUnchanged = ($hostHashAfter -eq $hostHashBefore)
if (-not $hostHashUnchanged) { $errors.Add('host_package_hash_changed_during_run') }
$status = if ($FixtureMode) { 'fixture_only' } elseif ($WhatIfPreference) { 'planned' } elseif (-not $rollbackSucceeded) { 'cleanup_failed' } elseif ($errors.Count -gt 0 -or -not $acceptancePassed) { 'failed' } else { 'passed' }
$result = [ordered]@{
    schema_version = 'sas-package-vm-execution-result/v1'
    run_id = $runId
    profile_id = [string]$profile.profile_id
    authorization_reference = [string]$profile.execution_contract.authorization_reference
    package = [ordered]@{ source_sha256=$hostHashBefore; installer_type=[string]$profile.execution_contract.installer_type; arguments_source=[string]$profile.execution_contract.supported_arguments_source; host_hash_reverified=$hostHashUnchanged }
    vm = [ordered]@{ provider='hyper_v'; vm_name=$VmName; checkpoint_name=$CheckpointName; network_mode='disconnected'; initial_state=$initialState; final_state=$finalState }
    proof = [ordered]@{ fixture_mode=[bool]$FixtureMode; vm_started=$vmStarted; package_executed_in_guest=$packageExecuted; package_executed_on_host=$false; admin_box_installer_mutation=$false; physical_workstation_validated=$false; autologon_performed=$false }
    execution = [ordered]@{ status=$status; installer_exit_code=$installerExitCode; reboot_performed=$rebootPerformed; acceptance_passed=$acceptancePassed; started_at_utc=$started; completed_at_utc=(Get-SasUtcNow) }
    rollback = [ordered]@{ attempted=$rollbackAttempted; succeeded=$rollbackSucceeded; checkpoint_restored=$checkpointRestored; guest_staging_removed=$guestStagingRemoved; host_package_hash_unchanged=$hostHashUnchanged }
    artifacts = [ordered]@{ events='package_vm_execution_events.jsonl'; result='package_vm_execution_result.json'; handoff='operator_handoff.txt' }
    errors = @($errors)
    proof_ceiling = 'disposable_vm_installation_and_application_acceptance_only_no_physical_workstation_validation'
}
$result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -WhatIf:$false
@(
    'PACKAGE DISPOSABLE-VM EXECUTION'
    "Status: $status"
    "Profile: $($profile.profile_id)"
    "VM started: $vmStarted"
    "Package executed in guest: $packageExecuted"
    'Package executed on admin box: False'
    "Acceptance passed: $acceptancePassed"
    "Checkpoint restored: $checkpointRestored"
    'Physical workstation validated: False'
    'Next gate: controlled physical-workstation pilot after a passing VM result.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-SasVmEvent -Path $eventPath -Value @{ event='run_completed'; status=$status; result='package_vm_execution_result.json' }
Write-Host "PACKAGE VM EXECUTION: $status"
Write-Host "Evidence: $runRoot"
if ($status -in @('failed','cleanup_failed','blocked')) { exit 1 }
exit 0
