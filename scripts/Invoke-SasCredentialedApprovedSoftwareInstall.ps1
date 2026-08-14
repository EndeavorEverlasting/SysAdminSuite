#Requires -Version 5.1
<#
.SYNOPSIS
Deploy one catalog-approved software package over credentialed WinRM from an admin box.

.DESCRIPTION
Credentialed WinRM is an additive transport. It does not replace current-token WinRM,
SMB scheduled-task deployment, AutoLogon S4U/recovery, or crash-safe AutoLogon field work.
The operator selects this transport before mutation; this script never performs automatic
post-mutation fallback to another transport.

The lane requires protected-network posture, canonical FQDN resolution, operator-local host
eligibility, a package-specific transport opt-in, an independently pinned catalog SHA-256,
exact catalog-approved installer arguments, and an Administrator WinRM token. AutoLogon
qualification additionally requires the explicit Cybernet equipment profile and the tracked
Cybernet profile authority.

The credential remains a runtime-only PSCredential. It is never serialized, converted to
plaintext, placed on a command line, or written to evidence. This lane never changes UAC/LUA,
LocalAccountTokenFilterPolicy, WinRM configuration, TrustedHosts, firewall policy, or target
security posture merely to make remoting succeed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PackageId,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string[]]$InstallerArguments = @(),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Cybernet')]
    [string]$EquipmentProfile,

    [Parameter(Mandatory = $false)]
    [switch]$QualificationOnly,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmDeployment,

    [Parameter(Mandatory = $false)]
    [switch]$NonInteractive,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $repoRoot 'configs\software-packages\approved-apps.json'
$harnessApiPath = Join-Path $repoRoot 'harness\api\sas-harness-api.json'
$networkGatePath = Join-Path $PSScriptRoot 'Confirm-SasNorthwellNetwork.ps1'
$eligibilityPath = Join-Path $PSScriptRoot 'Test-SasHostEligibility.ps1'
$targetResolverPath = Join-Path $PSScriptRoot 'SasTargetNameResolution.psm1'
$cybernetProfilePath = Join-Path $repoRoot 'Config\cybernet-client-preferences.json'

foreach ($required in @($catalogPath, $harnessApiPath, $networkGatePath, $eligibilityPath, $targetResolverPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing credentialed deployment dependency: $required"
    }
}
if (-not $ConfirmDeployment) {
    throw 'Explicit -ConfirmDeployment is required. This lane can install software on remote targets.'
}

function Write-SasJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 28 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-SasEvent {
    param([Parameter(Mandatory = $true)][string]$Name, [hashtable]$Data = @{})
    $payload = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        event = $Name
        run_id = $runId
    }
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }
    $payload | ConvertTo-Json -Depth 18 -Compress | Add-Content -LiteralPath $eventPath -Encoding UTF8
}

function Get-SasPropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Normalize-SasUncRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') { throw "Software share root must be UNC: $Path" }
    return ($normalized.TrimEnd('\') + '\')
}

function Assert-SasSafeRelativeInstallerPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $relative = $Path.Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or
        [IO.Path]::IsPathRooted($relative) -or
        $relative.StartsWith('\') -or
        $relative -match '(^|\\)\.\.(\\|$)') {
        throw "Unsafe installer relative path: $Path"
    }
    return $relative
}

function Test-SasStringArrayExact {
    param([string[]]$Left = @(), [string[]]$Right = @())
    $a = @($Left)
    $b = @($Right)
    if ($a.Count -ne $b.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) {
        if (-not ([string]$a[$i]).Equals([string]$b[$i], [StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

Import-Module $targetResolverPath -Force

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $stateRoot 'field-runs\credentialed-winrm'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$runId = 'credentialed-winrm-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$eventPath = Join-Path $runRoot 'credentialed_winrm_events.jsonl'
$resultPath = Join-Path $runRoot 'credentialed_winrm_result.json'
$latestPointerPath = Join-Path $stateRoot 'last-credentialed-winrm-run.json'

$result = [ordered]@{
    schema_version = 'sas-credentialed-winrm-deployment-result/v2'
    run_id = $runId
    status = 'started'
    disposition = 'preflight'
    started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    completed_at_utc = $null
    package_id = $PackageId.Trim().ToLowerInvariant()
    package_name = $null
    qualification_only = $QualificationOnly.IsPresent
    equipment_profile = $null
    profile_authority_path = $null
    credential_mode = 'runtime_pscredential_only'
    credential_persisted = $false
    protected_network_passed = $false
    canonical_targets = @()
    target_results = @()
    expected_source_sha256 = $null
    source_sha256 = $null
    completed_target_count = 0
    failed_target_count = 0
    reboot_required = $false
    target_mutation_performed = $false
    cleanup_complete = $false
    result_path = $resultPath
    event_path = $eventPath
    failure_stage = $null
    failure_reason = $null
}

Write-SasJson -Path $resultPath -Value ([pscustomobject]$result)
Write-SasJson -Path $latestPointerPath -Value ([pscustomobject][ordered]@{
    schema_version = 'sas-credentialed-winrm-latest-pointer/v1'
    run_id = $runId
    run_root = $runRoot
    result_path = $resultPath
    event_path = $eventPath
    status = $result.status
    updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
})
Write-SasEvent -Name 'run_started' -Data @{ qualification_only = $QualificationOnly.IsPresent; requested_target_count = @($ComputerName).Count }

try {
    Write-SasEvent -Name 'network_gate_started'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGatePath -Purpose "Credentialed approved software deployment: $PackageId" -NonInteractive -NoOpenWifiSettings
    if ($LASTEXITCODE -ne 0) { throw "Protected-network gate failed with exit code $LASTEXITCODE" }
    $result.protected_network_passed = $true
    Write-SasEvent -Name 'network_gate_passed'

    $targetInputs = @($ComputerName | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($targetInputs.Count -eq 0) { throw 'No target computer names were supplied.' }
    if ($targetInputs.Count -gt $MaxTargets) { throw "Target count $($targetInputs.Count) exceeds MaxTargets $MaxTargets." }
    if ($QualificationOnly -and $targetInputs.Count -ne 1) { throw 'QualificationOnly is intentionally limited to exactly one target.' }

    $canonicalTargets = @()
    foreach ($targetInput in $targetInputs) {
        $resolution = Resolve-SasCanonicalTargetFqdn -TargetName $targetInput
        $fqdn = ([string]$resolution.fqdn).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($fqdn) -or $fqdn -notmatch '\.') {
            throw "Target did not resolve to one canonical FQDN: $targetInput"
        }
        $eligibility = & $eligibilityPath -Target $fqdn -ExecContext remote -RepoRoot $repoRoot
        if (-not [bool]$eligibility.eligible) {
            throw "Canonical target is not authorized by the operator-local host policy: $fqdn; reason=$($eligibility.reason)"
        }
        $canonicalTargets += $fqdn
    }
    $canonicalTargets = @($canonicalTargets | Sort-Object -Unique)
    $result.canonical_targets = $canonicalTargets
    Write-SasEvent -Name 'targets_authorized' -Data @{ target_count = $canonicalTargets.Count }

    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') {
        throw "Unsupported approved software catalog schema: $($catalog.schema_version)"
    }
    $packageMatches = @($catalog.packages | Where-Object { ([string]$_.id).Equals($PackageId.Trim(), [StringComparison]::OrdinalIgnoreCase) })
    if ($packageMatches.Count -ne 1) { throw "Approved package id not found or ambiguous: $PackageId" }
    $package = $packageMatches[0]
    $packageIdNormalized = ([string]$package.id).Trim().ToLowerInvariant()
    $result.package_id = $packageIdNormalized
    $result.package_name = [string]$package.display_name

    if (-not [bool](Get-SasPropertyValue -Object $package -Name 'install_enabled' -Default $false)) {
        throw "Package '$($package.display_name)' is not enabled for installation."
    }
    if ($QualificationOnly) {
        if (-not [bool](Get-SasPropertyValue -Object $package -Name 'credentialed_winrm_qualification_enabled' -Default $false)) {
            throw "Package '$($package.display_name)' is not approved for credentialed WinRM qualification."
        }
    }
    elseif (-not [bool](Get-SasPropertyValue -Object $package -Name 'credentialed_winrm_install_enabled' -Default $false)) {
        throw "Package '$($package.display_name)' is not promoted for credentialed WinRM installation."
    }

    if ($packageIdNormalized -eq 'autologon') {
        if (-not $QualificationOnly) {
            throw 'AutoLogon is not promoted for normal credentialed WinRM deployment; qualification is a separate evidence lane.'
        }
        if ($EquipmentProfile -ne 'Cybernet') {
            throw 'AutoLogon credentialed qualification requires explicit -EquipmentProfile Cybernet. Unknown/shared profiles fail closed before package execution.'
        }
        if (-not (Test-Path -LiteralPath $cybernetProfilePath -PathType Leaf)) {
            throw "Cybernet profile authority is missing: $cybernetProfilePath"
        }
        $profileAuthority = Get-Content -LiteralPath $cybernetProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profilePackageIds = @($profileAuthority.software.package_ids | ForEach-Object { [string]$_ })
        $fullProfileLane = $profileAuthority.software.deployment_lanes.full_profile
        if ([string]$profileAuthority.profile_id -ne 'cybernet-clinical-workstation-default' -or
            'autologon' -notin $profilePackageIds -or
            -not [bool]$profileAuthority.software.autologon_must_be_last -or
            [string]$fullProfileLane.autologon_behavior -ne 'final_separate_mutating_step') {
            throw 'Tracked Cybernet profile authority does not authorize AutoLogon as the final separate mutating step.'
        }
        $result.equipment_profile = 'Cybernet'
        $result.profile_authority_path = $cybernetProfilePath
        Write-SasEvent -Name 'equipment_profile_authorized' -Data @{ equipment_profile = 'Cybernet'; authority = 'Config/cybernet-client-preferences.json' }
    }

    $catalogRoot = Normalize-SasUncRoot -Path ([string]$catalog.software_share_root)
    $api = Get-Content -LiteralPath $harnessApiPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $approvedRoots = @($api.posture.approved_software_sources | ForEach-Object { Normalize-SasUncRoot -Path ([string]$_) })
    if (@($approvedRoots | Where-Object { $_.Equals($catalogRoot, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        throw "Catalog software share root is not approved by the harness API: $catalogRoot"
    }

    $folder = Assert-SasSafeRelativeInstallerPath -Path ([string]$package.source_folder_relative_path)
    $installerFile = ([string]$package.installer_file).Trim()
    if ([string]::IsNullOrWhiteSpace($installerFile) -or $installerFile.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $installerFile -match '[\\/]') {
        throw "Package '$($package.display_name)' does not have one safe pinned installer filename."
    }
    $installerRelativePath = Assert-SasSafeRelativeInstallerPath -Path ("$folder\$installerFile")
    $installerPath = "$catalogRoot$installerRelativePath"
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Pinned installer was not found on the approved source: $installerPath"
    }

    $catalogArguments = @($package.default_installer_arguments | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $requestedArguments = @($InstallerArguments | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requestedArguments.Count -gt 0 -and -not (Test-SasStringArrayExact -Left $requestedArguments -Right $catalogArguments)) {
        throw "InstallerArguments override is not authorized for '$($package.display_name)'. Credentialed WinRM requires exact catalog argument equality."
    }
    $arguments = @($catalogArguments)
    if ([string](Get-SasPropertyValue -Object $package -Name 'installer_arguments_policy' -Default '') -eq 'approved_empty' -and $arguments.Count -ne 0) {
        throw "Package '$($package.display_name)' requires the approved-empty installer argument policy."
    }
    if ([bool](Get-SasPropertyValue -Object $package -Name 'requires_validated_installer_arguments' -Default $false) -and $arguments.Count -eq 0) {
        throw "Package '$($package.display_name)' requires cataloged vendor-validated installer arguments before live execution."
    }

    $expectedSourceHash = ([string](Get-SasPropertyValue -Object $package -Name 'credentialed_winrm_expected_sha256' -Default '')).Trim().ToLowerInvariant()
    if ($expectedSourceHash -notmatch '^[0-9a-f]{64}$') {
        throw "Package '$($package.display_name)' has no independently pinned credentialed_winrm_expected_sha256. Pin approved bytes before this transport may contact the target."
    }
    $result.expected_source_sha256 = $expectedSourceHash
    $sourceHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.source_sha256 = $sourceHash
    if (-not $sourceHash.Equals($expectedSourceHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Approved source SHA-256 mismatch for '$($package.display_name)'. Expected $expectedSourceHash; observed $sourceHash"
    }
    Write-SasEvent -Name 'package_source_trust_proved' -Data @{ package_id = $packageIdNormalized; source_sha256 = $sourceHash; argument_count = $arguments.Count }

    if ($null -eq $Credential) {
        if ($NonInteractive) { throw 'Credential is required in NonInteractive mode.' }
        $Credential = Get-Credential -Message 'Enter an authorized administrator credential. It remains in memory only.'
        if ($null -eq $Credential) { throw 'Credential prompt was cancelled.' }
    }
    Write-SasEvent -Name 'runtime_credential_acquired' -Data @{ credential_persisted = $false }

    $remoteTokenProbe = {
        Set-StrictMode -Version 2.0
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        [pscustomobject][ordered]@{
            computer_name = $env:COMPUTERNAME
            administrator_token = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            local_system = $identity.User.IsWellKnown([Security.Principal.WellKnownSidType]::LocalSystemSid)
        }
    }

    $remoteSnapshot = {
        param([string]$DisplayName, [bool]$CaptureAutoLogon)
        Set-StrictMode -Version 2.0
        $ErrorActionPreference = 'Stop'
        $matches = @()
        foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                try {
                    $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    if (([string]$item.DisplayName).Equals($DisplayName, [StringComparison]::OrdinalIgnoreCase)) {
                        $matches += [pscustomobject][ordered]@{
                            display_name = [string]$item.DisplayName
                            version = [string]$item.DisplayVersion
                            publisher = [string]$item.Publisher
                        }
                    }
                }
                catch {}
            }
        }
        $auto = $null
        if ($CaptureAutoLogon) {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon')
            try {
                $names = @($key.GetValueNames())
                $autoValue = if ($names -contains 'AutoAdminLogon') {
                    [string]$key.GetValue('AutoAdminLogon', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
                else { $null }
                $auto = [pscustomobject][ordered]@{
                    auto_admin_logon_enabled = ($autoValue -eq '1')
                    default_username_value_name_present = ($names -contains 'DefaultUserName')
                    default_domain_value_name_present = ($names -contains 'DefaultDomainName')
                    default_password_value_name_present = ($names -contains 'DefaultPassword')
                }
            }
            finally { if ($key) { $key.Dispose() } }
        }
        [pscustomobject][ordered]@{
            captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            matching_installed_package_count = $matches.Count
            matching_installed_packages = @($matches)
            autologon = $auto
        }
    }

    $remoteExecute = {
        param([string]$InstallerPath, [string[]]$Arguments)
        Set-StrictMode -Version 2.0
        $ErrorActionPreference = 'Stop'
        $extension = [IO.Path]::GetExtension($InstallerPath)
        if ($extension.Equals('.msi', [StringComparison]::OrdinalIgnoreCase)) {
            $filePath = Join-Path $env:WINDIR 'System32\msiexec.exe'
            $effectiveArguments = @('/i', ('"{0}"' -f $InstallerPath)) + @($Arguments)
        }
        elseif ($extension.Equals('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $filePath = $InstallerPath
            $effectiveArguments = @($Arguments)
        }
        else { throw "Unsupported installer extension: $extension" }
        $process = Start-Process -FilePath $filePath -ArgumentList $effectiveArguments -Wait -PassThru
        $code = [int]$process.ExitCode
        [pscustomobject][ordered]@{
            installer_exit_code = $code
            success = ($code -in @(0, 1641, 3010))
            reboot_required = ($code -in @(1641, 3010))
        }
    }

    $captureAutoLogon = ($packageIdNormalized -eq 'autologon')

    foreach ($target in $canonicalTargets) {
        $session = $null
        $stageRoot = $null
        $targetResult = [ordered]@{
            target = $target
            status = 'started'
            administrator_token = $false
            local_system = $null
            target_mutation_performed = $false
            source_sha256 = $sourceHash
            target_sha256 = $null
            before = $null
            execution = $null
            after = $null
            cleanup_attempted = $false
            cleanup_succeeded = $false
            failure_reason = $null
        }
        try {
            Write-SasEvent -Name 'target_session_starting' -Data @{ target = $target }
            $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 3600000
            $session = New-PSSession -ComputerName $target -Credential $Credential -Authentication Negotiate -SessionOption $sessionOption
            $token = Invoke-Command -Session $session -ScriptBlock $remoteTokenProbe
            $targetResult.administrator_token = [bool]$token.administrator_token
            $targetResult.local_system = [bool]$token.local_system
            if (-not [bool]$token.administrator_token) {
                throw 'Credential authenticated, but the WinRM session does not hold an Administrator token. Refusing to alter UAC/LUA or token-filter policy.'
            }
            Write-SasEvent -Name 'target_admin_token_proved' -Data @{ target = $target; local_system = [bool]$token.local_system }

            $targetResult.before = Invoke-Command -Session $session -ScriptBlock $remoteSnapshot -ArgumentList ([string]$package.display_name), $captureAutoLogon

            $stageRoot = Invoke-Command -Session $session -ScriptBlock {
                param([string]$RunId)
                Set-StrictMode -Version 2.0
                $base = Join-Path $env:ProgramData 'SysAdminSuite\CredentialedSoftwareInstall'
                $candidate = [IO.Path]::GetFullPath((Join-Path $base $RunId))
                $expectedBase = [IO.Path]::GetFullPath($base).TrimEnd('\') + '\'
                if (-not $candidate.StartsWith($expectedBase, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Run staging path escaped the credentialed install root.'
                }
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
                $candidate
            } -ArgumentList $runId

            $result.target_mutation_performed = $true
            $targetResult.target_mutation_performed = $true
            Write-SasJson -Path $resultPath -Value ([pscustomobject]$result)
            Write-SasEvent -Name 'target_staging_created' -Data @{ target = $target; target_mutation_performed = $true }

            $remoteInstaller = Join-Path $stageRoot $installerFile
            Copy-Item -LiteralPath $installerPath -Destination $remoteInstaller -ToSession $session -Force
            $targetHash = Invoke-Command -Session $session -ScriptBlock {
                param([string]$Path)
                (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
            } -ArgumentList $remoteInstaller
            $targetResult.target_sha256 = [string]$targetHash
            if (-not $expectedSourceHash.Equals([string]$targetHash, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Target installer SHA-256 mismatch for $target. Expected independently pinned $expectedSourceHash; observed $targetHash"
            }
            Write-SasEvent -Name 'target_installer_staged' -Data @{ target = $target; target_sha256 = [string]$targetHash }

            $targetResult.execution = Invoke-Command -Session $session -ScriptBlock $remoteExecute -ArgumentList $remoteInstaller, $arguments
            if (-not [bool]$targetResult.execution.success) {
                throw "Installer returned exit code $($targetResult.execution.installer_exit_code) on $target."
            }
            if ([bool]$targetResult.execution.reboot_required) { $result.reboot_required = $true }

            $targetResult.after = Invoke-Command -Session $session -ScriptBlock $remoteSnapshot -ArgumentList ([string]$package.display_name), $captureAutoLogon
            $targetResult.status = if ($QualificationOnly) { 'qualification_completed_review_required' } else { 'completed' }
            Write-SasEvent -Name 'target_execution_completed' -Data @{ target = $target; exit_code = [int]$targetResult.execution.installer_exit_code; qualification_only = $QualificationOnly.IsPresent }
        }
        catch {
            $targetResult.status = 'failed'
            $targetResult.failure_reason = $_.Exception.Message
            Write-SasEvent -Name 'target_failed' -Data @{ target = $target; reason = $_.Exception.Message }
            throw
        }
        finally {
            if ($session -and $stageRoot) {
                $targetResult.cleanup_attempted = $true
                try {
                    $cleanup = Invoke-Command -Session $session -ScriptBlock {
                        param([string]$Path, [string]$RunId)
                        Set-StrictMode -Version 2.0
                        $base = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'SysAdminSuite\CredentialedSoftwareInstall')).TrimEnd('\') + '\'
                        $candidate = [IO.Path]::GetFullPath($Path)
                        if ($RunId -notmatch '^credentialed-winrm-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$' -or
                            -not $candidate.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or
                            (Split-Path -Leaf $candidate) -ne $RunId) {
                            throw 'Refusing cleanup outside the exact credentialed deployment run root.'
                        }
                        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force }
                        -not (Test-Path -LiteralPath $candidate)
                    } -ArgumentList $stageRoot, $runId
                    $targetResult.cleanup_succeeded = [bool]$cleanup
                }
                catch {
                    $targetResult.cleanup_succeeded = $false
                    Write-SasEvent -Name 'target_cleanup_failed' -Data @{ target = $target; reason = $_.Exception.Message }
                }
            }
            if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
            $result.target_results = @($result.target_results) + @([pscustomobject]$targetResult)
            Write-SasJson -Path $resultPath -Value ([pscustomobject]$result)
        }
    }

    $result.completed_target_count = @($result.target_results | Where-Object { [string]$_.status -in @('completed','qualification_completed_review_required') }).Count
    $result.failed_target_count = @($result.target_results | Where-Object { [string]$_.status -eq 'failed' }).Count
    $result.cleanup_complete = @($result.target_results | Where-Object { [bool]$_.target_mutation_performed -and -not [bool]$_.cleanup_succeeded }).Count -eq 0
    if (-not $result.cleanup_complete) {
        $result.status = 'CREDENTIALED_WINRM_CLEANUP_REQUIRED'
        $result.disposition = 'do_not_retry_or_switch_transport_until_exact_run_cleanup_is_resolved'
        $result.failure_stage = 'cleanup'
        throw 'One or more mutated targets retained or have unproven run-scoped staging. Resolve exact-run cleanup before another mutation attempt.'
    }

    $result.status = if ($QualificationOnly) { 'CREDENTIALED_WINRM_QUALIFICATION_COMPLETED_REVIEW_REQUIRED' } else { 'CREDENTIALED_WINRM_DEPLOYMENT_COMPLETED' }
    $result.disposition = if ($QualificationOnly) { 'review_evidence_then_separately_authorize_promotion_or_restart' } else { 'technician_acceptance_required' }
    Write-SasEvent -Name 'run_completed' -Data @{ status = $result.status; completed_target_count = $result.completed_target_count; cleanup_complete = $result.cleanup_complete }
}
catch {
    $caught = $_
    $result.completed_target_count = @($result.target_results | Where-Object { [string]$_.status -in @('completed','qualification_completed_review_required') }).Count
    $result.failed_target_count = @($result.target_results | Where-Object { [string]$_.status -eq 'failed' }).Count
    $cleanupOutstanding = @($result.target_results | Where-Object { [bool]$_.target_mutation_performed -and -not [bool]$_.cleanup_succeeded }).Count -gt 0

    if ($cleanupOutstanding) {
        $result.status = 'CREDENTIALED_WINRM_CLEANUP_REQUIRED'
        $result.disposition = 'do_not_retry_or_switch_transport_until_exact_run_cleanup_is_resolved'
        $result.failure_stage = 'cleanup'
    }
    elseif ($result.completed_target_count -gt 0) {
        $result.status = 'CREDENTIALED_WINRM_PARTIAL_COMPLETION_REVIEW_REQUIRED'
        $result.disposition = 'preserve_completed_targets_and_select_any_retry_targets_explicitly'
        if ([string]::IsNullOrWhiteSpace([string]$result.failure_stage)) { $result.failure_stage = 'later_target_failed' }
    }
    else {
        $result.status = 'CREDENTIALED_WINRM_DEPLOYMENT_FAILED'
        $result.disposition = if ([bool]$result.target_mutation_performed) { 'mutation_may_have_occurred_review_target_result_before_retry' } else { 'no_recorded_target_mutation' }
        if ([string]::IsNullOrWhiteSpace([string]$result.failure_stage)) { $result.failure_stage = 'credentialed_winrm_transaction' }
    }
    $result.failure_reason = $caught.Exception.Message
    Write-SasEvent -Name 'run_failed' -Data @{ status = $result.status; reason = $result.failure_reason; completed_target_count = $result.completed_target_count; target_mutation_performed = [bool]$result.target_mutation_performed }
    throw $caught
}
finally {
    $result.completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    Write-SasJson -Path $resultPath -Value ([pscustomobject]$result)
    Write-SasJson -Path $latestPointerPath -Value ([pscustomobject][ordered]@{
        schema_version = 'sas-credentialed-winrm-latest-pointer/v1'
        run_id = $runId
        run_root = $runRoot
        result_path = $resultPath
        event_path = $eventPath
        status = $result.status
        disposition = $result.disposition
        updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    })
    if ($null -ne $Credential) { Remove-Variable Credential -ErrorAction SilentlyContinue }
}

$output = [pscustomobject]$result
if ($PassThru) { return $output }
$output | Format-List status, disposition, run_id, package_id, package_name, qualification_only, equipment_profile, canonical_targets, completed_target_count, failed_target_count, reboot_required, cleanup_complete, result_path, event_path
