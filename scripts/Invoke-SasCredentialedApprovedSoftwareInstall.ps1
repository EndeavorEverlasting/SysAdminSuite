#Requires -Version 5.1
<#
.SYNOPSIS
Deploy an approved software package over credentialed WinRM from an admin box.

.DESCRIPTION
Prompts for or accepts one runtime-only PSCredential, proves protected-network posture,
resolves canonical target FQDNs, enforces the operator-local host eligibility policy,
loads only a catalog-approved package, copies the pinned installer through an authenticated
PowerShell session, verifies source/target SHA-256 equality, proves the remote token is an
Administrator token, executes the installer, captures bounded before/after state, and removes
only the run-scoped SysAdminSuite staging directory.

This lane is additive. It does not replace current-token WinRM, SMB scheduled-task,
AutoLogon S4U/recovery, or crash-safe AutoLogon field deployment. Operators select one
transport before target mutation; a failed run may inform a later explicitly selected lane,
but this script never performs automatic post-mutation transport fallback.

The credential is never serialized, exported, written to evidence, converted to plaintext,
or placed in a command line. This lane never changes EnableLUA, UAC policy,
LocalAccountTokenFilterPolicy, WinRM configuration, TrustedHosts, or firewall policy.

Packages must opt in through credentialed_winrm_install_enabled. A package may separately
allow a one-target qualification run through credentialed_winrm_qualification_enabled.
Qualification completion is evidence for review; it does not promote the package.
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

foreach ($required in @($catalogPath, $harnessApiPath, $networkGatePath, $eligibilityPath, $targetResolverPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing credentialed deployment dependency: $required"
    }
}

if (-not $ConfirmDeployment) {
    throw 'Explicit -ConfirmDeployment is required. This lane can install software on remote targets.'
}

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

function Write-SasJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-SasEvent {
    param([Parameter(Mandatory = $true)][string]$Name, [hashtable]$Data = @{})
    $payload = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        event = $Name
        run_id = $runId
    }
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }
    $payload | ConvertTo-Json -Depth 16 -Compress | Add-Content -LiteralPath $eventPath -Encoding UTF8
}

function Normalize-SasUncRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') { throw "Software share root must be UNC: $Path" }
    return ($normalized.TrimEnd('\') + '\')
}

function Get-SasPropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Assert-SasSafeRelativeInstallerPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $relative = $Path.Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('\') -or $relative -match '(^|\\)\.\.(\\|$)') {
        throw "Unsafe installer relative path: $Path"
    }
    return $relative
}

Import-Module $targetResolverPath -Force

$result = [ordered]@{
    schema_version = 'sas-credentialed-winrm-deployment-result/v1'
    run_id = $runId
    status = 'started'
    started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    completed_at_utc = $null
    package_id = $PackageId.Trim().ToLowerInvariant()
    package_name = $null
    qualification_only = $QualificationOnly.IsPresent
    credential_mode = 'runtime_pscredential_only'
    credential_persisted = $false
    protected_network_passed = $false
    canonical_targets = @()
    target_results = @()
    source_sha256 = $null
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
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') { throw "Unsupported approved software catalog schema: $($catalog.schema_version)" }
    $packageMatches = @($catalog.packages | Where-Object { ([string]$_.id).Equals($PackageId.Trim(), [StringComparison]::OrdinalIgnoreCase) })
    if ($packageMatches.Count -ne 1) { throw "Approved package id not found or ambiguous: $PackageId" }
    $package = $packageMatches[0]
    $result.package_name = [string]$package.display_name

    if (-not [bool](Get-SasPropertyValue -Object $package -Name 'install_enabled' -Default $false)) {
        throw "Package '$($package.display_name)' is not enabled for installation."
    }
    if ($QualificationOnly) {
        if (-not [bool](Get-SasPropertyValue -Object $package -Name 'credentialed_winrm_qualification_enabled' -Default $false)) {
            throw "Package '$($package.display_name)' is not approved for credentialed WinRM qualification."
        }
    }
    else {
        if (-not [bool](Get-SasPropertyValue -Object $package -Name 'credentialed_winrm_install_enabled' -Default $false)) {
            throw "Package '$($package.display_name)' is not promoted for credentialed WinRM installation. Use QualificationOnly only when the catalog explicitly allows qualification."
        }
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
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "Pinned installer was not found on the approved source: $installerPath" }

    $arguments = @($InstallerArguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($arguments.Count -eq 0) { $arguments = @($package.default_installer_arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
    if ([bool](Get-SasPropertyValue -Object $package -Name 'requires_validated_installer_arguments' -Default $false) -and $arguments.Count -eq 0) {
        throw "Package '$($package.display_name)' requires vendor-validated installer arguments before live execution."
    }

    $sourceHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.source_sha256 = $sourceHash
    Write-SasEvent -Name 'package_source_validated' -Data @{ package_id = [string]$package.id; source_sha256 = $sourceHash; argument_count = $arguments.Count }

    if ($null -eq $Credential) {
        if ($NonInteractive) { throw 'Credential is required in NonInteractive mode.' }
        $Credential = Get-Credential -Message "Enter an authorized administrator credential for the credentialed WinRM deployment. The credential remains in memory only."
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
                        $matches += [pscustomobject][ordered]@{ display_name = [string]$item.DisplayName; version = [string]$item.DisplayVersion; publisher = [string]$item.Publisher }
                    }
                } catch {}
            }
        }
        $auto = $null
        if ($CaptureAutoLogon) {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon')
            try {
                $names = @($key.GetValueNames())
                $autoValue = if ($names -contains 'AutoAdminLogon') { [string]$key.GetValue('AutoAdminLogon', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
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
            software_matches = @($matches)
            autologon = $auto
        }
    }

    $remoteInstall = {
        param([string]$InstallerPath, [string[]]$Arguments)
        Set-StrictMode -Version 2.0
        $ErrorActionPreference = 'Stop'
        $extension = [IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()
        if ($extension -eq '.msi') {
            $msiArgs = @('/i', $InstallerPath) + @($Arguments)
            $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        }
        elseif ($extension -eq '.exe') {
            $process = Start-Process -FilePath $InstallerPath -ArgumentList @($Arguments) -Wait -PassThru
        }
        else { throw "Unsupported installer extension: $extension" }
        [pscustomobject][ordered]@{
            exit_code = [int]$process.ExitCode
            reboot_required = ([int]$process.ExitCode -in @(1641, 3010))
            accepted_exit_code = ([int]$process.ExitCode -in @(0, 1641, 3010))
        }
    }

    foreach ($target in $canonicalTargets) {
        $session = $null
        $stageRoot = $null
        $targetResult = [ordered]@{
            target = $target
            status = 'started'
            administrator_token = $false
            local_system = $null
            before = $null
            target_sha256 = $null
            execution = $null
            after = $null
            target_mutation_performed = $false
            cleanup = [ordered]@{ attempted = $false; succeeded = $false; stage_root_remaining = $null; error = $null }
            error = $null
        }
        try {
            Write-SasEvent -Name 'target_session_opening' -Data @{ target = $target }
            $option = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 3600000
            $session = New-PSSession -ComputerName $target -Credential $Credential -Authentication Negotiate -SessionOption $option
            $token = Invoke-Command -Session $session -ScriptBlock $remoteTokenProbe
            $targetResult.administrator_token = [bool]$token.administrator_token
            $targetResult.local_system = [bool]$token.local_system
            if (-not [bool]$token.administrator_token) {
                throw 'Authenticated remote token is not an Administrator token. Refusing to alter UAC/LUA or token-filter policy.'
            }
            Write-SasEvent -Name 'administrator_token_proved' -Data @{ target = $target; local_system = [bool]$token.local_system }

            $captureAutoLogon = ([string]$package.id -eq 'autologon')
            $targetResult.before = Invoke-Command -Session $session -ScriptBlock $remoteSnapshot -ArgumentList ([string]$package.display_name), $captureAutoLogon

            $stageRoot = Invoke-Command -Session $session -ScriptBlock {
                param([string]$RunId)
                $root = Join-Path $env:ProgramData ("SysAdminSuite\CredentialedSoftwareInstall\{0}" -f $RunId)
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                return $root
            } -ArgumentList $runId
            $result.target_mutation_performed = $true
            $targetResult.target_mutation_performed = $true
            Write-SasJson -Path $resultPath -Value ([pscustomobject]$result)
            Write-SasEvent -Name 'target_staging_created' -Data @{ target = $target }

            $remoteInstaller = Join-Path $stageRoot $installerFile
            Copy-Item -LiteralPath $installerPath -Destination $remoteInstaller -ToSession $session -Force
            $targetHash = Invoke-Command -Session $session -ScriptBlock {
                param([string]$Path)
                (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
            } -ArgumentList $remoteInstaller
            $targetResult.target_sha256 = [string]$targetHash
            if (-not ([string]$targetHash).Equals($sourceHash, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Target installer SHA-256 mismatch for $target."
            }
            Write-SasEvent -Name 'installer_staged_and_verified' -Data @{ target = $target; source_sha256 = $sourceHash; target_sha256 = [string]$targetHash }

            $targetResult.execution = Invoke-Command -Session $session -ScriptBlock $remoteInstall -ArgumentList $remoteInstaller, @($arguments)
            if (-not [bool]$targetResult.execution.accepted_exit_code) {
                throw "Installer returned unsupported exit code $($targetResult.execution.exit_code) on $target."
            }
            $result.reboot_required = ($result.reboot_required -or [bool]$targetResult.execution.reboot_required)
            Write-SasEvent -Name 'installer_completed' -Data @{ target = $target; exit_code = [int]$targetResult.execution.exit_code; reboot_required = [bool]$targetResult.execution.reboot_required }

            $targetResult.after = Invoke-Command -Session $session -ScriptBlock $remoteSnapshot -ArgumentList ([string]$package.display_name), $captureAutoLogon
            $targetResult.status = if ($QualificationOnly) { 'qualification_completed_review_required' } else { 'completed' }
        }
        catch {
            $targetResult.status = 'failed'
            $targetResult.error = $_.Exception.Message
            throw
        }
        finally {
            if ($session -and $stageRoot) {
                $targetResult.cleanup.attempted = $true
                try {
                    $remaining = Invoke-Command -Session $session -ScriptBlock {
                        param([string]$RunId, [string]$ExpectedRoot)
                        $base = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'SysAdminSuite\CredentialedSoftwareInstall'))
                        $expected = [IO.Path]::GetFullPath((Join-Path $base $RunId))
                        $actual = [IO.Path]::GetFullPath($ExpectedRoot)
                        if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside exact run-scoped staging root.' }
                        if (Test-Path -LiteralPath $actual) { Remove-Item -LiteralPath $actual -Recurse -Force }
                        return (Test-Path -LiteralPath $actual)
                    } -ArgumentList $runId, $stageRoot
                    $targetResult.cleanup.stage_root_remaining = [bool]$remaining
                    $targetResult.cleanup.succeeded = -not [bool]$remaining
                }
                catch {
                    $targetResult.cleanup.error = $_.Exception.Message
                    $targetResult.cleanup.succeeded = $false
                }
            }
            if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
            $result.target_results = @($result.target_results) + @([pscustomobject]$targetResult)
            Write-SasJson -Path $resultPath -Value ([pscustomobject]$result)
        }
    }

    $allCleanup = @($result.target_results | Where-Object { -not [bool]$_.cleanup.succeeded }).Count -eq 0
    $result.cleanup_complete = $allCleanup
    if (-not $allCleanup) { throw 'One or more targets retained run-scoped SysAdminSuite staging. Review cleanup evidence before another mutation attempt.' }

    if ($QualificationOnly) {
        $result.status = 'qualification_completed_review_required'
        Write-Host 'CREDENTIALED_WINRM_QUALIFICATION_COMPLETED_REVIEW_REQUIRED' -ForegroundColor Yellow
    }
    else {
        $result.status = 'completed'
        Write-Host 'CREDENTIALED_WINRM_DEPLOYMENT_COMPLETED' -ForegroundColor Green
    }
}
catch {
    $result.status = 'failed'
    $result.failure_stage = 'credentialed_winrm_transaction'
    $result.failure_reason = $_.Exception.Message
    Write-SasEvent -Name 'run_failed' -Data @{ reason = $_.Exception.Message; target_mutation_performed = [bool]$result.target_mutation_performed }
    Write-Error $_
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
        target_mutation_performed = [bool]$result.target_mutation_performed
        updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    })
    Remove-Variable Credential -ErrorAction SilentlyContinue
    Write-Host "Result: $resultPath"
    Write-Host "Latest: $latestPointerPath"
}

if ($PassThru) { [pscustomobject]$result }
if ($result.status -eq 'failed') { exit 1 }
