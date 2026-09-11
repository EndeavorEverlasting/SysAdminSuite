[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Audit', 'Verify')]
    [string]$Action,

    [ValidateSet('Any', 'Absent', 'System')]
    [string]$ExpectedState = 'Any'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $repoRoot 'Config\cursor-workstation-profile.json'

function Get-SasObjectPropertyValue {
    param($InputObject, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-WindowsHost {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Cursor workstation audit is supported only on Windows.'
    }
}

function Expand-SasProfilePath {
    param([Parameter(Mandatory = $true)][string]$Value)

    $tokens = [ordered]@{
        '{LOCALAPPDATA}' = $env:LOCALAPPDATA
        '{APPDATA}' = $env:APPDATA
        '{USERPROFILE}' = $env:USERPROFILE
        '{PROGRAMFILES}' = $env:ProgramFiles
        '{PROGRAMFILESX86}' = ${env:ProgramFiles(x86)}
        '{PROGRAMDATA}' = $env:ProgramData
        '{PUBLIC}' = $env:PUBLIC
    }

    $expanded = $Value
    foreach ($token in $tokens.Keys) {
        if ($expanded.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $replacement = [string]$tokens[$token]
        if ([string]::IsNullOrWhiteSpace($replacement)) { return '' }
        $expanded = $expanded.Replace($token, $replacement)
    }
    if ($expanded -match '\{[A-Z0-9_]+\}') { return '' }
    return $expanded
}

function Get-ExpandedProfilePaths {
    param([Parameter(Mandatory = $true)]$Values)
    $resolved = @()
    foreach ($value in @($Values)) {
        $path = Expand-SasProfilePath -Value ([string]$value)
        if (-not [string]::IsNullOrWhiteSpace($path)) { $resolved += $path }
    }
    return @($resolved | Select-Object -Unique)
}

function Test-PathUnderRoot {
    param([string]$Candidate, [string]$Root)
    if (-not $Candidate -or -not $Root) { return $false }
    try {
        $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\')
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        return ($candidateFull -ieq $rootFull -or $candidateFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase))
    }
    catch { return $false }
}

function Get-CursorRoots {
    param($Profile)
    $machine = @(Get-ExpandedProfilePaths -Values $Profile.installation.machine_install_roots)
    $user = @(Get-ExpandedProfilePaths -Values $Profile.installation.user_install_roots)
    return [pscustomobject]@{ Machine = $machine; User = $user; All = @($machine + $user | Select-Object -Unique) }
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
            if (-not $displayName -or $displayName -notmatch [string]$Profile.application.display_name_regex) { continue }
            $entries += [pscustomobject]@{
                Scope = [string]$root.scope
                DisplayName = $displayName
                DisplayVersion = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'DisplayVersion')
                InstallLocation = [string](Get-SasObjectPropertyValue -InputObject $app -Name 'InstallLocation')
                RegistryPath = [string]$key.PSPath
            }
        }
    }
    return @($entries)
}

function Get-CursorInstallEvidence {
    param($Profile, $Roots)
    $items = @()
    $expectedExecutable = [string]$Profile.application.expected_executable
    foreach ($scopeName in @('Machine', 'User')) {
        foreach ($root in @($Roots.$scopeName)) {
            $rootExists = Test-Path -LiteralPath $root -PathType Container
            $exe = Join-Path $root $expectedExecutable
            $exeExists = Test-Path -LiteralPath $exe -PathType Leaf
            if ($rootExists -or $exeExists) {
                $items += [pscustomobject]@{
                    Scope = $scopeName.ToLowerInvariant()
                    Root = $root
                    RootExists = [bool]$rootExists
                    ExpectedExecutable = $exe
                    ExecutableExists = [bool]$exeExists
                }
            }
        }
    }
    return @($items)
}

function Get-CursorProcessEvidence {
    param($Roots)
    $items = @()
    try {
        foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
            $path = [string](Get-SasObjectPropertyValue -InputObject $process -Name 'ExecutablePath')
            if (-not $path) { continue }
            $owned = $false
            foreach ($root in @($Roots.All)) {
                if (Test-PathUnderRoot -Candidate $path -Root $root) { $owned = $true; break }
            }
            if (-not $owned) { continue }
            $items += [pscustomobject]@{
                ProcessId = [int](Get-SasObjectPropertyValue -InputObject $process -Name 'ProcessId')
                Name = [string](Get-SasObjectPropertyValue -InputObject $process -Name 'Name')
                ExecutablePath = $path
            }
        }
        return [pscustomobject]@{ Succeeded = $true; Error = $null; Items = @($items) }
    }
    catch {
        return [pscustomobject]@{ Succeeded = $false; Error = $_.Exception.Message; Items = @() }
    }
}

function Get-CursorCommandEvidence {
    param($Roots)
    $owned = @()
    $external = @()
    foreach ($command in @(Get-Command cursor -All -ErrorAction SilentlyContinue)) {
        $path = [string](Get-SasObjectPropertyValue -InputObject $command -Name 'Path')
        if (-not $path) { $path = [string](Get-SasObjectPropertyValue -InputObject $command -Name 'Source') }
        if (-not $path) { continue }
        $isOwned = $false
        foreach ($root in @($Roots.All)) {
            if (Test-PathUnderRoot -Candidate $path -Root $root) { $isOwned = $true; break }
        }
        if ($isOwned) { $owned += $path } else { $external += $path }
    }
    return [pscustomobject]@{ Owned = @($owned | Select-Object -Unique); External = @($external | Select-Object -Unique) }
}

function Get-CursorInventory {
    param($Profile)

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $roots = Get-CursorRoots -Profile $Profile
    $registrations = @(Get-CursorUninstallEntries -Profile $Profile)
    $installEvidence = @(Get-CursorInstallEvidence -Profile $Profile -Roots $roots)
    $processEvidence = Get-CursorProcessEvidence -Roots $roots
    $commandEvidence = Get-CursorCommandEvidence -Roots $roots

    $machineRegistrations = @($registrations | Where-Object { $_.Scope -like 'machine*' })
    $userRegistrations = @($registrations | Where-Object { $_.Scope -eq 'user' })
    $machineExecutables = @($installEvidence | Where-Object { $_.Scope -eq 'machine' -and $_.ExecutableExists })
    $userExecutables = @($installEvidence | Where-Object { $_.Scope -eq 'user' -and $_.ExecutableExists })

    $machineEvidence = ($machineRegistrations.Count -gt 0 -and $machineExecutables.Count -gt 0)
    $userEvidence = ($userRegistrations.Count -gt 0 -or $userExecutables.Count -gt 0)
    $residue = ($registrations.Count -gt 0 -or $installEvidence.Count -gt 0 -or @($processEvidence.Items).Count -gt 0 -or @($commandEvidence.Owned).Count -gt 0)

    $classification = 'absent-current-context'
    if (-not [bool]$processEvidence.Succeeded) { $classification = 'inspection-incomplete' }
    elseif ($machineEvidence -and $userEvidence) { $classification = 'mixed' }
    elseif ($registrations.Count -gt 1) { $classification = 'multiple-registrations' }
    elseif ($machineEvidence -and -not $userEvidence) { $classification = 'system' }
    elseif ($residue) { $classification = 'user-or-stale' }

    return [pscustomobject]@{
        Classification = $classification
        ContextUser = [string]$identity.Name
        ContextUserSid = [string]$identity.User.Value
        ContextProfile = [string]$env:USERPROFILE
        ContextScope = 'current-security-principal'
        Registrations = $registrations
        InstallEvidence = $installEvidence
        Processes = @($processEvidence.Items)
        ProcessInspectionSucceeded = [bool]$processEvidence.Succeeded
        ProcessInspectionError = [string]$processEvidence.Error
        OwnedCommandPaths = @($commandEvidence.Owned)
        ExternalCommandPathsIgnored = @($commandEvidence.External)
        MachineInstallEvidence = [bool]$machineEvidence
        UserInstallEvidence = [bool]$userEvidence
    }
}

function Test-CursorAbsentCurrentContext {
    param($Inventory)
    return (
        [bool]$Inventory.ProcessInspectionSucceeded -and
        @($Inventory.Registrations).Count -eq 0 -and
        @($Inventory.InstallEvidence).Count -eq 0 -and
        @($Inventory.Processes).Count -eq 0 -and
        @($Inventory.OwnedCommandPaths).Count -eq 0
    )
}

function Test-CursorCanonicalSystemInstall {
    param($Inventory)
    return (
        [bool]$Inventory.ProcessInspectionSucceeded -and
        [bool]$Inventory.MachineInstallEvidence -and
        -not [bool]$Inventory.UserInstallEvidence -and
        [string]$Inventory.Classification -eq 'system'
    )
}

function Get-CursorRecommendation {
    param($Inventory)
    switch ([string]$Inventory.Classification) {
        'absent-current-context' { return 'No Cursor evidence was found for the current security principal or canonical machine roots. Mutation remains unavailable in this safety floor.' }
        'system' { return 'Canonical machine registration plus executable evidence is present. Perform a separate GUI smoke test if runtime behavior matters.' }
        'inspection-incomplete' { return 'Process inspection failed. Treat absence/system verification as unproven and repair the local inspection boundary first.' }
        default { return 'Local Cursor installation inconsistency is present. Preserve this evidence; mutating repair is intentionally disabled until the hardened lifecycle lane closes its trust-boundary requirements.' }
    }
}

function Write-CursorResult {
    param($Profile, [Parameter(Mandatory = $true)]$Result)
    $root = Expand-SasProfilePath -Value ([string]$Profile.evidence.local_output_root)
    if (-not $root) { throw 'Canonical Cursor evidence root could not be resolved on this host.' }
    $runDirectory = Join-Path $root ([string]$Result.run_id)
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $resultPath = Join-Path $runDirectory 'cursor_workstation_result.json'
    $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    return $resultPath
}

Assert-WindowsHost
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Canonical Cursor workstation profile not found: $profilePath" }
$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
if ([string]$profile.schema_version -ne 'sas-cursor-workstation-profile/v1') { throw "Unsupported Cursor workstation profile version: $($profile.schema_version)" }
if ([bool]$profile.posture.mutation_available) { throw 'This read-only engine refuses a profile that enables mutation.' }

$runId = 'cursor-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
$inventory = Get-CursorInventory -Profile $profile
$status = 'AUDITED'

if ($Action -eq 'Verify') {
    switch ($ExpectedState) {
        'Absent' {
            if (-not (Test-CursorAbsentCurrentContext -Inventory $inventory)) { throw "Cursor Verify expected Absent for the current security principal but observed $($inventory.Classification)." }
            $status = 'VERIFIED_ABSENT_CURRENT_CONTEXT'
        }
        'System' {
            if (-not (Test-CursorCanonicalSystemInstall -Inventory $inventory)) { throw "Cursor Verify expected canonical System evidence but observed $($inventory.Classification)." }
            $status = 'VERIFIED_SYSTEM'
        }
        default { $status = 'VERIFIED_OBSERVED_STATE' }
    }
}

$result = [ordered]@{
    schema_version = 'sas-cursor-workstation-result/v1'
    run_id = $runId
    action = $Action
    expected_state = $ExpectedState
    status = $status
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    mutation_available = $false
    target_mutation_performed = $false
    inventory = $inventory
    recommendation = Get-CursorRecommendation -Inventory $inventory
    proof_ceiling = 'Repository/runtime audit can describe the current security principal plus canonical machine roots. It does not prove another user profile, GUI behavior, vendor-service health, or authorize install/uninstall/purge.'
}

$resultPath = Write-CursorResult -Profile $profile -Result $result
$result | ConvertTo-Json -Depth 12
Write-Host "Cursor read-only lifecycle result: $resultPath"
