[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Audit', 'InstallSystem', 'Uninstall', 'RecoveryPurge', 'Verify')]
    [string]$Action,

    [string]$InstallerPath,

    [string[]]$InstallerArguments = @(),

    [switch]$AllowMutation,

    [switch]$PurgeUserState,

    [ValidateSet('Any', 'Absent', 'System')]
    [string]$ExpectedState = 'Any',

    [string]$ProfilePath,

    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProfilePath) {
    $ProfilePath = Join-Path $repoRoot 'Config\cursor-workstation-profile.json'
}

function Get-SasObjectPropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-WindowsHost {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Cursor workstation lifecycle is supported only on Windows.'
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This Cursor mutation requires an elevated Administrator PowerShell session.'
    }
}

function Assert-MutationAuthorized {
    if (-not $AllowMutation) {
        throw 'Mutation was requested without -AllowMutation. Audit and Verify remain read-only.'
    }
}

function Expand-SasProfilePath {
    param([Parameter(Mandatory = $true)][string]$Value)

    $programFilesX86 = ${env:ProgramFiles(x86)}
    $tokens = [ordered]@{
        '{LOCALAPPDATA}' = $env:LOCALAPPDATA
        '{APPDATA}' = $env:APPDATA
        '{USERPROFILE}' = $env:USERPROFILE
        '{PROGRAMFILES}' = $env:ProgramFiles
        '{PROGRAMFILESX86}' = $programFilesX86
        '{PROGRAMDATA}' = $env:ProgramData
        '{PUBLIC}' = $env:PUBLIC
    }

    $expanded = $Value
    foreach ($token in $tokens.Keys) {
        $replacement = [string]$tokens[$token]
        $expanded = $expanded.Replace($token, $replacement)
    }
    return $expanded
}

function Get-ExpandedProfilePaths {
    param([Parameter(Mandatory = $true)]$Values)

    $resolved = @()
    foreach ($value in @($Values)) {
        $path = Expand-SasProfilePath -Value ([string]$value)
        if ($path) { $resolved += $path }
    }
    return @($resolved | Select-Object -Unique)
}

function Test-PathUnderRoot {
    param(
        [string]$Candidate,
        [string]$Root
    )

    if (-not $Candidate -or -not $Root) { return $false }
    try {
        $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\')
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        return (
            $candidateFull -ieq $rootFull -or
            $candidateFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)
        )
    }
    catch {
        return $false
    }
}

function Get-CursorUninstallEntries {
    param($Profile)

    $entries = @()
    foreach ($root in @($Profile.installation.uninstall_registry_roots)) {
        if (-not (Test-Path -LiteralPath $root.path)) { continue }

        foreach ($key in @(Get-ChildItem -LiteralPath $root.path -ErrorAction SilentlyContinue)) {
            $app = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $app) { continue }

            $displayName = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'DisplayName')
            if (-not $displayName) { continue }
            if ($displayName -notmatch [string]$Profile.application.display_name_regex) { continue }

            $entries += [pscustomobject]@{
                Scope = [string]$root.scope
                DisplayName = $displayName
                DisplayVersion = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'DisplayVersion')
                InstallLocation = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'InstallLocation')
                UninstallString = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'UninstallString')
                QuietUninstallString = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'QuietUninstallString')
                RegistryPath = [string]$key.PSPath
            }
        }
    }
    return @($entries)
}

function Get-CursorInstallDirectories {
    param($Profile)

    $items = @()
    foreach ($path in @(Get-ExpandedProfilePaths -Values $Profile.installation.machine_install_roots)) {
        if (Test-Path -LiteralPath $path) {
            $items += [pscustomobject]@{ Scope = 'machine'; Path = $path }
        }
    }
    foreach ($path in @(Get-ExpandedProfilePaths -Values $Profile.installation.user_install_roots)) {
        if (Test-Path -LiteralPath $path) {
            $items += [pscustomobject]@{ Scope = 'user'; Path = $path }
        }
    }
    return @($items)
}

function Get-CursorStateDirectories {
    param($Profile)

    $items = @()
    foreach ($path in @(Get-ExpandedProfilePaths -Values $Profile.state.user_state_roots)) {
        if (Test-Path -LiteralPath $path) { $items += $path }
    }
    return @($items)
}

function Get-CursorProcesses {
    param($Profile)

    $roots = @(
        @(Get-ExpandedProfilePaths -Values $Profile.installation.machine_install_roots) +
        @(Get-ExpandedProfilePaths -Values $Profile.installation.user_install_roots)
    ) | Select-Object -Unique
    $processNames = @($Profile.application.process_names)
    $items = @()

    try {
        foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
            $name = [string](Get-SasObjectPropertyValue -InputObject $process -Name 'Name')
            $executablePath = [string](Get-SasObjectPropertyValue -InputObject $process -Name 'ExecutablePath')
            $processId = Get-SasObjectPropertyValue -InputObject $process -Name 'ProcessId'

            $nameMatch = $false
            foreach ($expectedName in $processNames) {
                if ($name -ieq [string]$expectedName) {
                    $nameMatch = $true
                    break
                }
            }

            $pathMatch = $false
            if ($executablePath) {
                foreach ($root in $roots) {
                    if (Test-PathUnderRoot -Candidate $executablePath -Root $root) {
                        $pathMatch = $true
                        break
                    }
                }
            }

            if ($nameMatch -or $pathMatch) {
                $items += [pscustomobject]@{
                    ProcessId = [int]$processId
                    Name = $name
                    ExecutablePath = $executablePath
                }
            }
        }
    }
    catch {
        foreach ($expectedName in $processNames) {
            $baseName = [IO.Path]::GetFileNameWithoutExtension([string]$expectedName)
            foreach ($process in @(Get-Process -Name $baseName -ErrorAction SilentlyContinue)) {
                $path = [string](Get-SasObjectPropertyValue -InputObject $process -Name 'Path')
                $items += [pscustomobject]@{
                    ProcessId = [int]$process.Id
                    Name = [string]$process.ProcessName
                    ExecutablePath = $path
                }
            }
        }
    }

    return @($items | Sort-Object ProcessId -Unique)
}

function Get-CursorCommandPaths {
    $items = @()
    foreach ($command in @(Get-Command cursor -All -ErrorAction SilentlyContinue)) {
        $path = [string](Get-SasObjectPropertyValue -InputObject $command -Name 'Path')
        if (-not $path) {
            $path = [string](Get-SasObjectPropertyValue -InputObject $command -Name 'Source')
        }
        if ($path) { $items += $path }
    }
    return @($items | Select-Object -Unique)
}

function Get-CursorInventory {
    param($Profile)

    $registrations = @(Get-CursorUninstallEntries -Profile $Profile)
    $installDirectories = @(Get-CursorInstallDirectories -Profile $Profile)
    $processes = @(Get-CursorProcesses -Profile $Profile)
    $commands = @(Get-CursorCommandPaths)
    $stateDirectories = @(Get-CursorStateDirectories -Profile $Profile)

    $machineEvidence = @(
        $registrations | Where-Object { $_.Scope -like 'machine*' }
    ).Count -gt 0 -or @(
        $installDirectories | Where-Object { $_.Scope -eq 'machine' }
    ).Count -gt 0

    $userEvidence = @(
        $registrations | Where-Object { $_.Scope -eq 'user' }
    ).Count -gt 0 -or @(
        $installDirectories | Where-Object { $_.Scope -eq 'user' }
    ).Count -gt 0

    $classification = 'absent'
    if ($machineEvidence -and $userEvidence) {
        $classification = 'mixed'
    }
    elseif ($registrations.Count -gt 1) {
        $classification = 'multiple-registrations'
    }
    elseif ($machineEvidence) {
        $classification = 'system'
    }
    elseif ($userEvidence -or $processes.Count -gt 0 -or $commands.Count -gt 0) {
        $classification = 'user-or-stale'
    }

    return [pscustomobject]@{
        Classification = $classification
        Registrations = $registrations
        InstallDirectories = $installDirectories
        Processes = $processes
        CommandPaths = $commands
        StateDirectories = $stateDirectories
        MachineInstallEvidence = [bool]$machineEvidence
        UserInstallEvidence = [bool]$userEvidence
    }
}

function Test-CursorAbsent {
    param($Inventory)
    return (
        @($Inventory.Registrations).Count -eq 0 -and
        @($Inventory.InstallDirectories).Count -eq 0 -and
        @($Inventory.Processes).Count -eq 0 -and
        @($Inventory.CommandPaths).Count -eq 0
    )
}

function Test-CursorCanonicalSystemInstall {
    param($Inventory)
    return (
        [bool]$Inventory.MachineInstallEvidence -and
        -not [bool]$Inventory.UserInstallEvidence -and
        [string]$Inventory.Classification -eq 'system'
    )
}

function Get-CursorRecommendation {
    param($Inventory)

    switch ([string]$Inventory.Classification) {
        'absent' { return 'InstallSystem when Cursor is required.' }
        'system' { return 'No repair indicated by local installation inventory. Perform an application smoke test before restoring settings or extensions.' }
        'mixed' { return 'Use RecoveryPurge after explicit authorization; mixed user/system installations are noncanonical.' }
        'multiple-registrations' { return 'Use RecoveryPurge after explicit authorization; duplicate registrations are local installation evidence.' }
        default { return 'Use Uninstall first; if registrations, install roots, locks, or command residue remain, escalate to RecoveryPurge.' }
    }
}

function Stop-CursorOwnedProcesses {
    param($Profile)

    $stopped = @()
    foreach ($process in @(Get-CursorProcesses -Profile $Profile)) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
            $stopped += [pscustomobject]@{
                ProcessId = $process.ProcessId
                Name = $process.Name
                Outcome = 'stopped'
            }
        }
        catch {
            $stopped += [pscustomobject]@{
                ProcessId = $process.ProcessId
                Name = $process.Name
                Outcome = 'failed'
                Error = $_.Exception.Message
            }
        }
    }
    Start-Sleep -Milliseconds 500
    return @($stopped)
}

function Split-SasExecutableCommandLine {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $trimmed = $CommandLine.Trim()
    if ($trimmed -match '^"([^"]+\.exe)"\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $matches[1]; Arguments = $matches[2] }
    }
    if ($trimmed -match '^(.+?\.exe)\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $matches[1].Trim('"'); Arguments = $matches[2] }
    }
    throw "Unsupported uninstall command format: $CommandLine"
}

function Invoke-CursorRegisteredUninstallers {
    param($Profile)

    $results = @()
    foreach ($entry in @(Get-CursorUninstallEntries -Profile $Profile)) {
        if (-not $entry.UninstallString) {
            $results += [pscustomobject]@{
                DisplayName = $entry.DisplayName
                DisplayVersion = $entry.DisplayVersion
                Outcome = 'missing-uninstall-string'
            }
            continue
        }

        try {
            $command = Split-SasExecutableCommandLine -CommandLine $entry.UninstallString
            $resolved = $command.FilePath
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                $found = Get-Command $resolved -ErrorAction SilentlyContinue
                if ($found) {
                    $foundPath = [string](Get-SasObjectPropertyValue -InputObject $found -Name 'Path')
                    if ($foundPath) { $resolved = $foundPath }
                }
            }
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                throw "Registered uninstaller is missing: $($command.FilePath)"
            }

            if ($command.Arguments) {
                $process = Start-Process -FilePath $resolved -ArgumentList $command.Arguments -Wait -PassThru -ErrorAction Stop
            }
            else {
                $process = Start-Process -FilePath $resolved -Wait -PassThru -ErrorAction Stop
            }
            $results += [pscustomobject]@{
                DisplayName = $entry.DisplayName
                DisplayVersion = $entry.DisplayVersion
                Outcome = 'executed'
                ExitCode = [int]$process.ExitCode
            }
        }
        catch {
            $results += [pscustomobject]@{
                DisplayName = $entry.DisplayName
                DisplayVersion = $entry.DisplayVersion
                Outcome = 'failed'
                Error = $_.Exception.Message
            }
        }
    }
    return @($results)
}

function Remove-CursorInstallRoots {
    param($Profile)

    $removed = @()
    $roots = @(
        @(Get-ExpandedProfilePaths -Values $Profile.installation.machine_install_roots) +
        @(Get-ExpandedProfilePaths -Values $Profile.installation.user_install_roots)
    ) | Select-Object -Unique
    foreach ($path in $roots) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            $removed += $path
        }
    }
    return @($removed)
}

function Remove-CursorRegistryRegistrations {
    param($Profile)

    $removed = @()
    foreach ($entry in @(Get-CursorUninstallEntries -Profile $Profile)) {
        if (Test-Path -LiteralPath $entry.RegistryPath) {
            Remove-Item -LiteralPath $entry.RegistryPath -Recurse -Force -ErrorAction Stop
            $removed += [pscustomobject]@{
                DisplayName = $entry.DisplayName
                DisplayVersion = $entry.DisplayVersion
                Scope = $entry.Scope
            }
        }
    }
    return @($removed)
}

function Remove-CursorStartupEntries {
    param($Profile)

    $installRoots = @(
        @(Get-ExpandedProfilePaths -Values $Profile.installation.machine_install_roots) +
        @(Get-ExpandedProfilePaths -Values $Profile.installation.user_install_roots)
    ) | Select-Object -Unique
    $removed = @()

    foreach ($root in @($Profile.state.startup_registry_roots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $item = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }

        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -like 'PS*') { continue }
            $value = [string]$property.Value
            $cursorValue = $false
            foreach ($installRoot in $installRoots) {
                if ($value -and $value.IndexOf($installRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $cursorValue = $true
                    break
                }
            }
            if ($property.Name -match '^Cursor' -or $cursorValue) {
                Remove-ItemProperty -LiteralPath $root -Name $property.Name -Force -ErrorAction Stop
                $removed += "$root::$($property.Name)"
            }
        }
    }
    return @($removed)
}

function Remove-CursorShortcuts {
    param($Profile)

    $removed = @()
    foreach ($root in @(Get-ExpandedProfilePaths -Values $Profile.state.shortcut_roots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($shortcut in @(Get-ChildItem -LiteralPath $root -Filter 'Cursor*.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $shortcut.FullName -Force -ErrorAction Stop
            $removed += $shortcut.FullName
        }
    }
    return @($removed)
}

function Normalize-PathEntry {
    param([string]$Value)
    if (-not $Value) { return '' }
    return $Value.Trim().Trim('"').TrimEnd('\').ToLowerInvariant()
}

function Remove-CursorCliPathEntries {
    param($Profile)

    $targets = @{}
    foreach ($path in @(Get-ExpandedProfilePaths -Values $Profile.installation.cli_path_templates)) {
        $targets[(Normalize-PathEntry -Value $path)] = $true
    }

    $changes = @()
    foreach ($scope in @('User', 'Machine')) {
        $original = [Environment]::GetEnvironmentVariable('Path', $scope)
        if (-not $original) { continue }
        $parts = @($original -split ';' | Where-Object { $_ })
        $kept = @()
        $removed = @()
        foreach ($part in $parts) {
            if ($targets.ContainsKey((Normalize-PathEntry -Value $part))) {
                $removed += $part
            }
            else {
                $kept += $part
            }
        }
        if ($removed.Count -gt 0) {
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), $scope)
            $changes += [pscustomobject]@{ Scope = $scope; Removed = $removed }
        }
    }

    if ($env:Path) {
        $currentKept = @()
        foreach ($part in @($env:Path -split ';' | Where-Object { $_ })) {
            if (-not $targets.ContainsKey((Normalize-PathEntry -Value $part))) {
                $currentKept += $part
            }
        }
        $env:Path = $currentKept -join ';'
    }

    return @($changes)
}

function Remove-CursorUserState {
    param($Profile)

    $removed = @()
    foreach ($path in @(Get-ExpandedProfilePaths -Values $Profile.state.user_state_roots)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            $removed += $path
        }
    }
    return @($removed)
}

function Test-CursorSystemInstaller {
    param(
        $Profile,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Installer is not a file: $Path"
    }

    $fileName = [IO.Path]::GetFileName($resolvedPath)
    if ($fileName -match [string]$Profile.installation.user_installer_filename_regex) {
        throw 'The selected installer is a Cursor user installer. SysAdminSuite requires the system installer.'
    }
    if ($fileName -notmatch [string]$Profile.installation.system_installer_filename_regex) {
        throw "Installer filename is not admitted by the Cursor system profile: $fileName"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $resolvedPath
    if ($signature.Status.ToString() -ne 'Valid') {
        throw "Cursor installer Authenticode signature is not valid: $($signature.Status)"
    }
    if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch [string]$Profile.installation.authenticode_subject_regex) {
        throw 'Cursor installer signer does not match the expected Anysphere publisher identity.'
    }

    $hash = Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256
    return [pscustomobject]@{
        Path = $resolvedPath
        FileName = $fileName
        Sha256 = $hash.Hash
        SignerSubject = $signature.SignerCertificate.Subject
    }
}

function Write-CursorResult {
    param(
        $Profile,
        [Parameter(Mandatory = $true)]$Result
    )

    $root = if ($OutputRoot) {
        $OutputRoot
    }
    else {
        Expand-SasProfilePath -Value ([string]$Profile.evidence.local_output_root)
    }
    $runDirectory = Join-Path $root ([string]$Result.run_id)
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $resultPath = Join-Path $runDirectory 'cursor_workstation_result.json'
    $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    return $resultPath
}

Assert-WindowsHost
if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    throw "Cursor workstation profile not found: $ProfilePath"
}
$profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
if ([string]$profile.schema_version -ne 'sas-cursor-workstation-profile/v1') {
    throw "Unsupported Cursor workstation profile version: $($profile.schema_version)"
}

$runId = 'cursor-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$started = (Get-Date).ToUniversalTime().ToString('o')
$preInventory = Get-CursorInventory -Profile $profile
$postInventory = $preInventory
$status = 'UNKNOWN'
$detail = $null
$failure = $null

try {
    switch ($Action) {
        'Audit' {
            $status = 'AUDITED'
            $detail = [pscustomobject]@{
                Recommendation = Get-CursorRecommendation -Inventory $preInventory
            }
        }

        'Verify' {
            switch ($ExpectedState) {
                'Absent' {
                    if (-not (Test-CursorAbsent -Inventory $preInventory)) {
                        throw "Cursor Verify expected Absent but observed $($preInventory.Classification)."
                    }
                    $status = 'VERIFIED_ABSENT'
                }
                'System' {
                    if (-not (Test-CursorCanonicalSystemInstall -Inventory $preInventory)) {
                        throw "Cursor Verify expected a canonical system install but observed $($preInventory.Classification)."
                    }
                    $status = 'VERIFIED_SYSTEM'
                }
                default {
                    $status = 'VERIFIED_OBSERVED_STATE'
                }
            }
        }

        'InstallSystem' {
            Assert-MutationAuthorized
            Assert-Administrator
            if (-not $InstallerPath) {
                throw 'InstallSystem requires -InstallerPath to an operator-downloaded official Cursor system installer.'
            }
            if (-not (Test-CursorAbsent -Inventory $preInventory)) {
                throw "InstallSystem requires a clean absent baseline; observed $($preInventory.Classification)."
            }
            $installer = Test-CursorSystemInstaller -Profile $profile -Path $InstallerPath

            if ($PSCmdlet.ShouldProcess('local Windows workstation', "Install Cursor system-wide from $($installer.FileName)")) {
                if ($InstallerArguments.Count -gt 0) {
                    $installerProcess = Start-Process -FilePath $installer.Path -ArgumentList $InstallerArguments -Wait -PassThru -ErrorAction Stop
                }
                else {
                    $installerProcess = Start-Process -FilePath $installer.Path -Wait -PassThru -ErrorAction Stop
                }
                if (@(0, 3010) -notcontains [int]$installerProcess.ExitCode) {
                    throw "Cursor system installer returned exit code $($installerProcess.ExitCode)."
                }
                Start-Sleep -Seconds 2
                $postInventory = Get-CursorInventory -Profile $profile
                if (-not (Test-CursorCanonicalSystemInstall -Inventory $postInventory)) {
                    throw "Cursor installer completed but canonical system state was not proven; observed $($postInventory.Classification)."
                }
                $status = if ([int]$installerProcess.ExitCode -eq 3010) {
                    'INSTALLED_SYSTEM_REBOOT_REQUIRED'
                }
                else {
                    'INSTALLED_SYSTEM'
                }
                $detail = [pscustomobject]@{
                    InstallerFileName = $installer.FileName
                    InstallerSha256 = $installer.Sha256
                    SignerSubject = $installer.SignerSubject
                    ExitCode = [int]$installerProcess.ExitCode
                }
            }
            else {
                $status = 'WHATIF_INSTALL_SYSTEM'
            }
        }

        'Uninstall' {
            Assert-MutationAuthorized
            Assert-Administrator
            if (Test-CursorAbsent -Inventory $preInventory) {
                $status = 'ALREADY_ABSENT'
                break
            }

            if ($PSCmdlet.ShouldProcess('local Windows workstation', 'Run registered Cursor uninstallers while preserving user state')) {
                $stopped = @(Stop-CursorOwnedProcesses -Profile $profile)
                $uninstallResults = @(Invoke-CursorRegisteredUninstallers -Profile $profile)
                Start-Sleep -Seconds 2
                $postInventory = Get-CursorInventory -Profile $profile
                $detail = [pscustomobject]@{
                    StoppedProcesses = $stopped
                    Uninstallers = $uninstallResults
                    UserStatePreserved = $true
                }
                if (-not (Test-CursorAbsent -Inventory $postInventory)) {
                    throw "Registered uninstall did not reach a clean absent state; observed $($postInventory.Classification). Use RecoveryPurge only after reviewing the audit."
                }
                $status = 'UNINSTALLED'
            }
            else {
                $status = 'WHATIF_UNINSTALL'
            }
        }

        'RecoveryPurge' {
            Assert-MutationAuthorized
            Assert-Administrator

            if ($PSCmdlet.ShouldProcess('local Windows workstation', 'Purge broken Cursor install registrations, install roots, startup entries, shortcuts, and CLI PATH residue')) {
                $stopped = @(Stop-CursorOwnedProcesses -Profile $profile)
                $removedInstallRoots = @(Remove-CursorInstallRoots -Profile $profile)
                $removedRegistrations = @(Remove-CursorRegistryRegistrations -Profile $profile)
                $removedStartup = @(Remove-CursorStartupEntries -Profile $profile)
                $removedShortcuts = @(Remove-CursorShortcuts -Profile $profile)
                $removedPathEntries = @(Remove-CursorCliPathEntries -Profile $profile)
                $removedState = @()
                if ($PurgeUserState) {
                    $removedState = @(Remove-CursorUserState -Profile $profile)
                }

                Start-Sleep -Milliseconds 500
                $postInventory = Get-CursorInventory -Profile $profile
                $detail = [pscustomobject]@{
                    StoppedProcesses = $stopped
                    RemovedInstallRoots = $removedInstallRoots
                    RemovedRegistrations = $removedRegistrations
                    RemovedStartupEntries = $removedStartup
                    RemovedShortcuts = $removedShortcuts
                    RemovedPathEntries = $removedPathEntries
                    UserStatePurged = [bool]$PurgeUserState
                    RemovedUserStateRoots = $removedState
                }
                if (-not (Test-CursorAbsent -Inventory $postInventory)) {
                    throw "RecoveryPurge did not reach a clean absent state; observed $($postInventory.Classification)."
                }
                $status = if ($PurgeUserState) { 'PURGED_WITH_USER_STATE' } else { 'PURGED_INSTALL_ONLY' }
            }
            else {
                $status = 'WHATIF_RECOVERY_PURGE'
            }
        }
    }
}
catch {
    $failure = $_
    $status = 'FAILED'
    try {
        $postInventory = Get-CursorInventory -Profile $profile
    }
    catch {
        $postInventory = $preInventory
    }
}

$result = [ordered]@{
    schema_version = 'sas-cursor-workstation-result/v1'
    run_id = $runId
    action = $Action
    expected_state = $ExpectedState
    status = $status
    started_utc = $started
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    profile_schema_version = [string]$profile.schema_version
    mutation_authorized = [bool]$AllowMutation
    purge_user_state = [bool]$PurgeUserState
    pre_inventory = $preInventory
    post_inventory = $postInventory
    detail = $detail
    error = if ($failure) { $failure.Exception.Message } else { $null }
}

$resultPath = Write-CursorResult -Profile $profile -Result $result
$result | ConvertTo-Json -Depth 12
Write-Host "Cursor lifecycle result: $resultPath"

if ($failure) {
    throw $failure
}
