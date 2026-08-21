#Requires -Version 5.1
<#
.SYNOPSIS
Resolve the sealed AutoLogon manifest without depending on one Windows user profile.

.DESCRIPTION
The short runtime is machine-local at C:\SASAL, while older staging wrote its seal manifest only beneath
one user's LOCALAPPDATA. This resolver accepts a runtime-local authority copy first, then the current-user
legacy copy, then performs a bounded exact-path search beneath local Windows profiles. It validates candidate
posture before use, rejects conflicting authorities, and hydrates both the runtime-local metadata copy and the
current user's compatibility copy from one validated authority.

No Git command, network operation, target contact, tracked-runtime mutation, credential read, or reboot occurs.
#>
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$ExpectedCommit,
    [string]$CurrentStateRoot,
    [string]$LegacySearchRoot,
    [switch]$RequireManifest,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = $null
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
}

function Get-SasJsonPropertyValue {
    param([AllowNull()]$Object,[Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Add-SasManifestCandidate {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $fullPath = [IO.Path]::GetFullPath($Path) } catch { return }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf -ErrorAction SilentlyContinue)) { return }
    foreach ($existing in $List) {
        if ([string]$existing.path -and ([string]$existing.path).Equals($fullPath,[StringComparison]::OrdinalIgnoreCase)) { return }
    }
    [void]$List.Add([pscustomobject]@{ path=$fullPath; source=$Source })
}

function Get-SasManifestFingerprint {
    param([Parameter(Mandatory = $true)]$State)
    $entries = @((Get-SasJsonPropertyValue -Object $State -Name 'tracked_file_hashes'))
    $parts = @(
        [string](Get-SasJsonPropertyValue -Object $State -Name 'schema_version'),
        [string](Get-SasJsonPropertyValue -Object $State -Name 'runtime_root'),
        [string](Get-SasJsonPropertyValue -Object $State -Name 'prepared_commit'),
        [string](Get-SasJsonPropertyValue -Object $State -Name 'tracked_file_hash_algorithm'),
        [string](Get-SasJsonPropertyValue -Object $State -Name 'tracked_file_count')
    )
    foreach ($entry in $entries) {
        $parts += (([string](Get-SasJsonPropertyValue -Object $entry -Name 'path')) + '=' + ([string](Get-SasJsonPropertyValue -Object $entry -Name 'sha256')))
    }
    return Get-SasSha256Text -Text ($parts -join "`n")
}

function Write-SasUtf8JsonCopy {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)][string]$RawJson)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path,$RawJson,(New-Object Text.UTF8Encoding($false)))
}

try { $runtimeFullPath = [IO.Path]::GetFullPath($RuntimeRoot) }
catch {
    Write-Error "AUTOLOGON_MANIFEST_RUNTIME_INVALID: $($_.Exception.Message)"
    exit 11
}

if ([string]::IsNullOrWhiteSpace($CurrentStateRoot)) {
    $CurrentStateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
}
else {
    $CurrentStateRoot = [IO.Path]::GetFullPath($CurrentStateRoot)
}
if ([string]::IsNullOrWhiteSpace($LegacySearchRoot)) {
    $profileParent = Split-Path -Parent ([Environment]::GetFolderPath('UserProfile'))
    if ([string]::IsNullOrWhiteSpace($profileParent)) { $profileParent = Join-Path $env:SystemDrive 'Users' }
    $LegacySearchRoot = $profileParent
}
else {
    $LegacySearchRoot = [IO.Path]::GetFullPath($LegacySearchRoot)
}

$runtimeManifestPath = Join-Path $runtimeFullPath '.git\sas-autologon-short-runtime.json'
$currentLegacyPath = Join-Path $CurrentStateRoot 'autologon-short-runtime.json'
$receiptPath = Join-Path $CurrentStateRoot 'autologon-manifest-authority.json'
$candidates = New-Object 'System.Collections.Generic.List[object]'
Add-SasManifestCandidate -List $candidates -Path $runtimeManifestPath -Source 'RUNTIME_LOCAL'
Add-SasManifestCandidate -List $candidates -Path $currentLegacyPath -Source 'CURRENT_USER_LEGACY'

if (Test-Path -LiteralPath $LegacySearchRoot -PathType Container -ErrorAction SilentlyContinue) {
    foreach ($profile in @(Get-ChildItem -LiteralPath $LegacySearchRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        $candidatePath = Join-Path $profile.FullName 'AppData\Local\SysAdminSuite\autologon-short-runtime.json'
        Add-SasManifestCandidate -List $candidates -Path $candidatePath -Source 'BOUNDED_PROFILE_LEGACY'
    }
}

$valid = @()
$rejected = @()
foreach ($candidate in $candidates) {
    $raw = ''
    try {
        $raw = [IO.File]::ReadAllText([string]$candidate.path,[Text.Encoding]::UTF8)
        $state = $raw | ConvertFrom-Json
        $schema = [string](Get-SasJsonPropertyValue -Object $state -Name 'schema_version')
        if ($schema -ne 'sas-autologon-short-runtime/v2') { throw "unsupported schema $schema" }
        $candidateRuntime = [IO.Path]::GetFullPath([string](Get-SasJsonPropertyValue -Object $state -Name 'runtime_root'))
        if (-not $candidateRuntime.TrimEnd('\').Equals($runtimeFullPath.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) {
            throw "runtime mismatch $candidateRuntime"
        }
        $preparedCommit = ([string](Get-SasJsonPropertyValue -Object $state -Name 'prepared_commit')).Trim()
        if ([string]::IsNullOrWhiteSpace($preparedCommit)) { throw 'prepared commit missing' }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and
            -not $preparedCommit.Equals($ExpectedCommit.Trim(),[StringComparison]::OrdinalIgnoreCase)) {
            throw "prepared commit mismatch $preparedCommit"
        }
        if ([string](Get-SasJsonPropertyValue -Object $state -Name 'runtime_git_transport') -ne 'LOCAL_FILESYSTEM_ONLY' -or
            -not [bool](Get-SasJsonPropertyValue -Object $state -Name 'runtime_remotes_removed') -or
            [bool](Get-SasJsonPropertyValue -Object $state -Name 'protected_bootstrap_git_network_allowed')) {
            throw 'local-only runtime posture invalid'
        }
        if ([string](Get-SasJsonPropertyValue -Object $state -Name 'tracked_file_hash_algorithm') -ne 'SHA256') {
            throw 'tracked-file hash algorithm is not SHA256'
        }
        $sealEntries = @((Get-SasJsonPropertyValue -Object $state -Name 'tracked_file_hashes'))
        $countText = ([string](Get-SasJsonPropertyValue -Object $state -Name 'tracked_file_count')).Trim()
        $parsedCount = 0
        if (-not [int]::TryParse($countText,[ref]$parsedCount) -or $parsedCount -lt 1 -or $sealEntries.Count -ne $parsedCount) {
            throw "tracked-file seal count invalid: declared=$countText actual=$($sealEntries.Count)"
        }
        $valid += [pscustomobject]@{
            path = [string]$candidate.path
            source = [string]$candidate.source
            raw = $raw
            state = $state
            prepared_commit = $preparedCommit
            fingerprint = Get-SasManifestFingerprint -State $state
        }
    }
    catch {
        $rejected += [pscustomobject]@{ path=[string]$candidate.path; source=[string]$candidate.source; reason=$_.Exception.Message }
    }
}

$classification = ''
$selected = $null
$runtimeCopyWritten = $false
$currentUserCopyWritten = $false
$uniqueFingerprints = @($valid | Select-Object -ExpandProperty fingerprint -Unique)
if ($valid.Count -eq 0) {
    $classification = 'AUTOLOGON_MANIFEST_NOT_FOUND'
}
elif ($uniqueFingerprints.Count -gt 1) {
    $classification = 'AUTOLOGON_MANIFEST_AMBIGUOUS'
}
else {
    $classification = 'AUTOLOGON_MANIFEST_AUTHORITY_READY'
    $selected = @($valid | Sort-Object @{Expression={ switch ([string]$_.source) { 'RUNTIME_LOCAL' {0}; 'CURRENT_USER_LEGACY' {1}; default {2} } }},path | Select-Object -First 1)[0]

    if (-not ([string]$selected.path).Equals($runtimeManifestPath,[StringComparison]::OrdinalIgnoreCase)) {
        $gitMetadataRoot = Split-Path -Parent $runtimeManifestPath
        if (Test-Path -LiteralPath $gitMetadataRoot -PathType Container) {
            Write-SasUtf8JsonCopy -Path $runtimeManifestPath -RawJson ([string]$selected.raw)
            $runtimeCopyWritten = $true
        }
    }
    if (-not ([string]$selected.path).Equals($currentLegacyPath,[StringComparison]::OrdinalIgnoreCase)) {
        Write-SasUtf8JsonCopy -Path $currentLegacyPath -RawJson ([string]$selected.raw)
        $currentUserCopyWritten = $true
    }
}

$receipt = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-manifest-authority/v1'
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    classification = $classification
    runtime_root = $runtimeFullPath
    selected_manifest_path = if ($null -eq $selected) { $null } else { [string]$selected.path }
    selected_source = if ($null -eq $selected) { $null } else { [string]$selected.source }
    prepared_commit = if ($null -eq $selected) { $null } else { [string]$selected.prepared_commit }
    runtime_manifest_path = $runtimeManifestPath
    current_user_legacy_path = $currentLegacyPath
    valid_candidate_count = $valid.Count
    rejected_candidate_count = $rejected.Count
    rejected_candidates = $rejected
    runtime_authority_copy_written = $runtimeCopyWritten
    current_user_compatibility_copy_written = $currentUserCopyWritten
    protected_git_activity = 'NONE'
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    tracked_runtime_mutation_performed = $false
}
try {
    if (-not (Test-Path -LiteralPath $CurrentStateRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $CurrentStateRoot -Force | Out-Null
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}
catch {
    Write-Error "AUTOLOGON_MANIFEST_RECEIPT_WRITE_FAILED: $($_.Exception.Message)"
    exit 11
}

if ($classification -eq 'AUTOLOGON_MANIFEST_AUTHORITY_READY') {
    Write-Host "AutoLogon manifest authority: $($selected.source) :: $($selected.path)" -ForegroundColor Green
    if ($runtimeCopyWritten) { Write-Host "Runtime-local authority copy hydrated: $runtimeManifestPath" -ForegroundColor Green }
    if ($currentUserCopyWritten) { Write-Host "Current-user compatibility copy hydrated: $currentLegacyPath" -ForegroundColor Green }
    Write-Host 'Manifest resolution performed no Git, network, target contact, or tracked-runtime mutation.' -ForegroundColor Green
    if ($PassThru) { $receipt }
    exit 0
}

if ($classification -eq 'AUTOLOGON_MANIFEST_AMBIGUOUS') {
    Write-Host "AUTOLOGON_MANIFEST_AMBIGUOUS: $($uniqueFingerprints.Count) conflicting valid manifest authorities were found." -ForegroundColor Red
    foreach ($candidate in $valid) { Write-Host "  $($candidate.source): $($candidate.path) [$($candidate.prepared_commit)]" -ForegroundColor Yellow }
    exit 12
}

if ($RequireManifest) {
    Write-Host "AUTOLOGON_MANIFEST_NOT_FOUND: no valid v2 manifest authority was found for $runtimeFullPath." -ForegroundColor Red
    Write-Host "Checked runtime-local authority: $runtimeManifestPath" -ForegroundColor Yellow
    Write-Host "Checked current-user legacy path: $currentLegacyPath" -ForegroundColor Yellow
    Write-Host "Bounded profile search root: $LegacySearchRoot" -ForegroundColor Yellow
    exit 10
}

Write-Host 'AutoLogon manifest authority not present; optional hydration skipped.' -ForegroundColor DarkGray
exit 0
