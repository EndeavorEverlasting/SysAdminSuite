#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies package hashes and offline Windows trust policy without executing package code.
.DESCRIPTION
    Consumes sas-package-static-analysis/v1 evidence, re-verifies every local source hash,
    evaluates embedded Authenticode with cache-only WinVerifyTrust, and applies an explicit
    signer or unsigned-code policy. Archives, shortcuts, and unresolved package containers
    remain blocked until their components receive separate intake.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BaseResultPath,

    [Parameter(Mandatory = $false)]
    [string]$TrustPolicyPath,

    [Parameter(Mandatory = $false)]
    [switch]$ObservationOnly,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 50000)]
    [int]$MaxFiles = 50000,

    [Parameter(Mandatory = $false)]
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Package trust verification requires Windows because it uses WinVerifyTrust.'
}
if (-not $ObservationOnly -and [string]::IsNullOrWhiteSpace($TrustPolicyPath)) {
    throw 'Supply -TrustPolicyPath for a deployment gate or use -ObservationOnly for evidence collection.'
}
if ($ObservationOnly -and -not [string]::IsNullOrWhiteSpace($TrustPolicyPath)) {
    throw '-ObservationOnly cannot be combined with -TrustPolicyPath.'
}
foreach ($requiredPath in @($InputPath, $BaseResultPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path does not exist: $requiredPath" }
}
if (-not [string]::IsNullOrWhiteSpace($TrustPolicyPath) -and -not (Test-Path -LiteralPath $TrustPolicyPath -PathType Leaf)) {
    throw "Trust policy does not exist: $TrustPolicyPath"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$interopPath = Join-Path $repoRoot 'tools/package-analysis/SasPackageTrustInterop.cs'
if (-not (Test-Path -LiteralPath $interopPath -PathType Leaf)) {
    throw "Package trust interop source is missing: $interopPath"
}
if (-not ('Sas.PackageTrust.WinTrustVerifier' -as [type])) {
    Add-Type -Path $interopPath
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $repoRoot "survey/output/package_trust_verification/$stamp"
}
if (-not $FixtureMode) {
    Import-Module (Join-Path $PSScriptRoot 'SasTargetIntake.psm1') -Force
    Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'package trust verification output directory'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$authenticodeExtensions = @(
    '.exe','.dll','.msi','.msp','.mst','.msix','.msixbundle','.appx','.appxbundle',
    '.cab','.cat','.ps1','.psm1','.psd1','.cmd','.bat','.vbs','.js','.jse','.wsf'
)
$codeExtensions = @(
    '.exe','.dll','.msi','.msp','.mst','.msix','.msixbundle','.appx','.appxbundle',
    '.cab','.cat','.ps1','.psm1','.psd1','.cmd','.bat','.vbs','.js','.jse','.wsf',
    '.py','.pyw','.sh','.bash','.zsh','.pl','.rb','.jar','.zip','.whl','.nupkg','.lnk','.url'
)
$codeFileClasses = @('installer','portable_executable','script','shortcut','archive')
$opaqueFileClasses = @('archive','shortcut')

function Get-SasSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-SasReparsePointChain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $false)][string]$RelativePath
    )
    $current = Get-Item -LiteralPath $RootPath -Force
    if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'input_root_is_reparse_point'
    }
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return }
    foreach ($part in ($RelativePath.Replace('/', '\').Split('\') | Where-Object { $_ -ne '' })) {
        $currentPath = Join-Path $current.FullName $part
        if (-not (Test-Path -LiteralPath $currentPath)) { throw 'source_file_missing' }
        $current = Get-Item -LiteralPath $currentPath -Force
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'source_path_contains_reparse_point'
        }
    }
}

function Resolve-SasTrustSourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$InputItem,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    if ($InputItem -is [System.IO.FileInfo]) {
        Test-SasReparsePointChain -RootPath $InputItem.FullName
        return $InputItem.FullName
    }
    $normalized = $RelativePath.Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($normalized) -or [System.IO.Path]::IsPathRooted($normalized) -or $normalized -match '(^|\\)\.\.(\\|$)') {
        throw 'unsafe_relative_path_in_base_result'
    }
    Test-SasReparsePointChain -RootPath $InputItem.FullName -RelativePath $normalized
    $rootFull = [System.IO.Path]::GetFullPath($InputItem.FullName).TrimEnd('\')
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFull $normalized))
    if (-not $candidate.StartsWith("$rootFull\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'base_result_path_escapes_input_root'
    }
    return $candidate
}

function ConvertTo-SasHexStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$Value)
    return ('0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes($Value), 0))
}

function Get-SasSignatureStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$HexCode)
    switch ($HexCode.ToUpperInvariant()) {
        '0X00000000' { 'valid' }
        '0X800B0100' { 'not_signed' }
        '0X80096010' { 'bad_digest' }
        '0X800B0004' { 'subject_not_trusted' }
        '0X800B0101' { 'certificate_expired' }
        '0X800B0109' { 'untrusted_root' }
        '0X800B0111' { 'explicit_distrust' }
        '0X800B010A' { 'chain_build_failed' }
        '0X800B0003' { 'subject_form_unknown' }
        default { 'verification_error' }
    }
}

function Normalize-SasThumbprint {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return ($Value -replace '[^A-Fa-f0-9]', '').ToUpperInvariant()
}

function Read-SasTrustPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $policy = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ([string]$policy.schema_version -ne 'sas-package-trust-policy/v1') { throw "Unsupported trust policy schema: $($policy.schema_version)" }
    if ([string]::IsNullOrWhiteSpace([string]$policy.policy_id)) { throw 'Trust policy policy_id is required.' }
    if ([string]$policy.default_disposition -notin @('review_required','blocked')) { throw 'Invalid default_disposition.' }
    if ([string]$policy.unlisted_noncode_disposition -notin @('hash_only_approved','review_required','blocked')) { throw 'Invalid unlisted_noncode_disposition.' }
    $seen = @{}
    foreach ($entry in @($policy.entries)) {
        $relative = ([string]$entry.relative_path).Replace('\','/')
        if ([string]::IsNullOrWhiteSpace($relative) -or [System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') {
            throw "Unsafe trust-policy relative_path: $relative"
        }
        $key = $relative.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate trust-policy relative_path: $relative" }
        $seen[$key] = $true
        if ([string]$entry.expected_sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "Invalid expected_sha256 for $relative" }
        $requirement = [string]$entry.signature_requirement
        if ($requirement -notin @('required_valid','allow_unsigned_explicit','review_required')) { throw "Invalid signature_requirement for $relative" }
        $thumbprints = @($entry.approved_signer_thumbprints | ForEach-Object { Normalize-SasThumbprint ([string]$_) } | Where-Object { $_ })
        $subjects = @($entry.approved_signer_subjects | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($requirement -eq 'required_valid' -and ($thumbprints.Count + $subjects.Count) -eq 0) {
            throw "required_valid entry must declare an approved signer identity: $relative"
        }
        if ($requirement -eq 'allow_unsigned_explicit' -and [string]::IsNullOrWhiteSpace([string]$entry.approval_reference)) {
            throw "allow_unsigned_explicit entry must declare approval_reference: $relative"
        }
    }
    return $policy
}

function Find-SasPolicyEntry {
    [CmdletBinding()]
    param($Policy, [string]$RelativePath)
    $normalized = $RelativePath.Replace('\','/')
    return @($Policy.entries | Where-Object { ([string]$_.relative_path).Replace('\','/').Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
}

function Test-SasSignerIdentity {
    [CmdletBinding()]
    param($PolicyEntry, [AllowNull()][string]$SignerSubject, [AllowNull()][string]$SignerThumbprint)
    $approvedThumbprints = @($PolicyEntry.approved_signer_thumbprints | ForEach-Object { Normalize-SasThumbprint ([string]$_) } | Where-Object { $_ })
    $approvedSubjects = @($PolicyEntry.approved_signer_subjects | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $actualThumbprint = Normalize-SasThumbprint $SignerThumbprint
    if ($actualThumbprint -and $approvedThumbprints -contains $actualThumbprint) { return $true }
    foreach ($subject in $approvedSubjects) {
        if ($SignerSubject -and $SignerSubject.Equals($subject, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-SasTrustClassification {
    [CmdletBinding()]
    param($BaseRecord, [string]$Extension)
    $fileClass = [string]$BaseRecord.file_class
    $archive = $BaseRecord.archive
    $nestedInstallerCount = if ($archive -and $archive.nested_installer_extensions) { @($archive.nested_installer_extensions).Count } else { 0 }
    $isOpaque = $fileClass -in $opaqueFileClasses -or $nestedInstallerCount -gt 0
    if ($Extension -in $authenticodeExtensions) {
        return [pscustomobject]@{ trust_scope = 'authenticode_candidate'; opaque = $false }
    }
    if ($Extension -in $codeExtensions -or $fileClass -in $codeFileClasses -or $nestedInstallerCount -gt 0) {
        return [pscustomobject]@{ trust_scope = 'code_policy_required'; opaque = [bool]$isOpaque }
    }
    return [pscustomobject]@{ trust_scope = 'hash_only_noncode'; opaque = $false }
}

$base = Get-Content -LiteralPath $BaseResultPath -Raw | ConvertFrom-Json
if ([string]$base.schema_version -ne 'sas-package-static-analysis/v1') { throw "Unsupported base result schema: $($base.schema_version)" }
if ($base.input.absolute_path_emitted -ne $false) { throw 'Base result does not preserve the absolute-path boundary.' }
foreach ($field in @('file_execution_performed','archive_payload_extracted','network_activity_performed','target_mutation_performed','host_mutation_performed','signature_trust_validated','runtime_behavior_validated')) {
    if ($base.proof.$field -ne $false) { throw "Base proof field must be false: $field" }
}
$baseFiles = @($base.files)
if ($baseFiles.Count -gt $MaxFiles) { throw "File limit exceeded: $($baseFiles.Count) > $MaxFiles" }

$policy = $null
$policyHash = $null
if (-not $ObservationOnly) {
    $policy = Read-SasTrustPolicy -Path $TrustPolicyPath
    $policyHash = Get-SasSha256 -Path $TrustPolicyPath
}

$inputItem = Get-Item -LiteralPath $InputPath -Force
$records = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]

foreach ($baseRecord in $baseFiles) {
    $relativePath = [string]$baseRecord.relative_path
    try {
        $candidate = Resolve-SasTrustSourcePath -InputItem $inputItem -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'source_file_missing' }
        $actualHash = Get-SasSha256 -Path $candidate
        if (-not $actualHash.Equals([string]$baseRecord.sha256, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'hash_mismatch_since_base_analysis' }

        $extension = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant()
        $classification = Get-SasTrustClassification -BaseRecord $baseRecord -Extension $extension
        $trustScope = [string]$classification.trust_scope
        $opaque = [bool]$classification.opaque
        $verification = $null
        $hexCode = $null
        $signatureStatus = 'not_applicable'
        $signerSubject = $null
        $signerThumbprint = $null
        if ($trustScope -eq 'authenticode_candidate') {
            $verification = [Sas.PackageTrust.WinTrustVerifier]::Verify($candidate)
            $hexCode = ConvertTo-SasHexStatus ([int]$verification.ResultCode)
            $signatureStatus = Get-SasSignatureStatus $hexCode
            $signerSubject = if ([string]::IsNullOrWhiteSpace([string]$verification.SignerSubject)) { $null } else { [string]$verification.SignerSubject }
            $signerThumbprint = Normalize-SasThumbprint ([string]$verification.SignerThumbprint)
        }

        $policyEntry = if ($policy) { Find-SasPolicyEntry -Policy $policy -RelativePath $relativePath } else { $null }
        $policyEntryFound = $null -ne $policyEntry
        $requirement = if ($policyEntryFound) { [string]$policyEntry.signature_requirement } elseif ($ObservationOnly) { 'observation_only' } elseif ($trustScope -eq 'hash_only_noncode') { 'hash_only_noncode' } else { 'no_policy_entry' }
        $identityMatch = if ($policyEntryFound -and $signatureStatus -eq 'valid') { Test-SasSignerIdentity $policyEntry $signerSubject $signerThumbprint } else { $false }
        $disposition = 'review_required'
        $reasons = New-Object System.Collections.Generic.List[string]

        if ($ObservationOnly) {
            $reasons.Add('observation_only_no_deployment_approval')
        }
        elseif ($opaque) {
            $disposition = 'blocked'
            $reasons.Add('opaque_code_container_requires_component_intake')
        }
        elseif (-not $policyEntryFound -and $trustScope -eq 'hash_only_noncode') {
            $disposition = [string]$policy.unlisted_noncode_disposition
            $reasons.Add('unlisted_noncode_hash_verified')
        }
        elseif (-not $policyEntryFound) {
            $disposition = [string]$policy.default_disposition
            $reasons.Add('no_matching_policy_entry_for_code_bearing_file')
        }
        elseif (-not $actualHash.Equals([string]$policyEntry.expected_sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            $disposition = 'blocked'
            $reasons.Add('policy_hash_mismatch')
        }
        elseif ($requirement -eq 'review_required') {
            $reasons.Add('policy_entry_requires_human_review')
        }
        elseif ($requirement -eq 'required_valid') {
            if ($trustScope -ne 'authenticode_candidate') {
                $disposition = 'blocked'
                $reasons.Add('required_valid_not_supported_for_this_code_surface')
            }
            elseif ($signatureStatus -ne 'valid') {
                $disposition = 'blocked'
                $reasons.Add("required_valid_signature_status_$signatureStatus")
            }
            elseif (-not $identityMatch) {
                $disposition = 'blocked'
                $reasons.Add('signer_identity_not_approved')
            }
            else {
                $disposition = 'approved'
                $reasons.Add('valid_signature_and_approved_signer')
            }
        }
        elseif ($requirement -eq 'allow_unsigned_explicit') {
            if ($trustScope -eq 'authenticode_candidate' -and $signatureStatus -eq 'not_signed') {
                $disposition = 'approved'
                $reasons.Add('unsigned_package_explicitly_approved_by_hash')
            }
            elseif ($trustScope -eq 'code_policy_required') {
                $disposition = 'approved'
                $reasons.Add('non_authenticode_code_explicitly_approved_by_hash')
            }
            elseif ($signatureStatus -eq 'valid') {
                $disposition = 'blocked'
                $reasons.Add('signed_file_requires_required_valid_policy')
            }
            elseif ($trustScope -eq 'hash_only_noncode') {
                $disposition = 'approved'
                $reasons.Add('noncode_file_explicitly_approved_by_hash')
            }
            else {
                $disposition = 'blocked'
                $reasons.Add("explicit_unsigned_exception_does_not_allow_status_$signatureStatus")
            }
        }

        $records.Add([pscustomobject][ordered]@{
            relative_path = $relativePath.Replace('\','/')
            sha256 = $actualHash
            hash_verified = $true
            trust_scope = $trustScope
            signature_status = $signatureStatus
            winverifytrust_code = $hexCode
            signer_subject = $signerSubject
            signer_thumbprint = $signerThumbprint
            signer_not_before = if ($verification -and $verification.SignerNotBefore.HasValue) { $verification.SignerNotBefore.Value.ToString('o') } else { $null }
            signer_not_after = if ($verification -and $verification.SignerNotAfter.HasValue) { $verification.SignerNotAfter.Value.ToString('o') } else { $null }
            policy_entry_found = $policyEntryFound
            signature_requirement = $requirement
            signer_identity_match = [bool]$identityMatch
            disposition = $disposition
            reasons = @($reasons.ToArray())
            package_execution_performed = $false
        })
    }
    catch {
        $message = [string]$_.Exception.Message
        $errors.Add([pscustomobject][ordered]@{
            relative_path = if ($relativePath) { $relativePath.Replace('\','/') } else { '<missing>' }
            error_type = $_.Exception.GetType().Name
            message = $message.Substring(0, [Math]::Min(300, $message.Length))
        })
    }
}

$approvedCount = @($records | Where-Object { $_.disposition -in @('approved','hash_only_approved') }).Count
$reviewCount = @($records | Where-Object { $_.disposition -eq 'review_required' }).Count
$blockedCount = @($records | Where-Object { $_.disposition -eq 'blocked' }).Count
$overall = if ($errors.Count -gt 0 -or $blockedCount -gt 0) { 'blocked' } elseif ($ObservationOnly -or $reviewCount -gt 0 -or $records.Count -eq 0) { 'review_required' } else { 'approved_for_vm_intake' }

$result = [ordered]@{
    schema_version = 'sas-package-trust-verification/v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    input = [ordered]@{ kind = if ($inputItem -is [System.IO.DirectoryInfo]) { 'directory' } else { 'file' }; display_name = $inputItem.Name; absolute_path_emitted = $false }
    base_result = [ordered]@{ schema_version = [string]$base.schema_version; sha256 = Get-SasSha256 $BaseResultPath; hash_verified_source_files = $records.Count }
    policy = [ordered]@{ provided = [bool](-not $ObservationOnly); schema_version = if ($policy) { [string]$policy.schema_version } else { $null }; policy_id = if ($policy) { [string]$policy.policy_id } else { $null }; sha256 = $policyHash; observation_only = [bool]$ObservationOnly }
    proof = [ordered]@{
        proof_level = 'offline_authenticode_policy'
        file_execution_performed = $false
        archive_payload_extracted = $false
        network_activity_performed = $false
        target_mutation_performed = $false
        host_mutation_performed = $false
        cache_only_url_retrieval = $true
        online_revocation_checked = $false
        authenticode_integrity_and_local_trust_evaluated = $true
        signer_policy_evaluated = [bool](-not $ObservationOnly)
        strong_name_cryptographic_validation_performed = $false
        deployment_runtime_validated = $false
    }
    summary = [ordered]@{
        base_files = $baseFiles.Count
        files_verified = $records.Count
        error_count = $errors.Count
        approved_count = $approvedCount
        review_required_count = $reviewCount
        blocked_count = $blockedCount
        overall_disposition = $overall
        deployment_approved = ($overall -eq 'approved_for_vm_intake')
    }
    files = @($records.ToArray())
    errors = @($errors.ToArray())
}

if ($ObservationOnly) {
    $starterEntries = foreach ($record in @($records | Where-Object { $_.trust_scope -ne 'hash_only_noncode' })) {
        [ordered]@{
            relative_path = $record.relative_path
            expected_sha256 = $record.sha256
            signature_requirement = 'review_required'
            approved_signer_thumbprints = @()
            approved_signer_subjects = @()
            approval_reference = $null
            observed_signature_status = $record.signature_status
            observed_signer_thumbprint = $record.signer_thumbprint
            observed_signer_subject = $record.signer_subject
        }
    }
    [ordered]@{
        schema_version = 'sas-package-trust-policy/v1'
        policy_id = 'starter-review-required'
        default_disposition = 'blocked'
        unlisted_noncode_disposition = 'hash_only_approved'
        entries = @($starterEntries)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'package_trust_policy.starter.json') -Encoding UTF8
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputRoot 'package_trust_verification.json') -Encoding UTF8
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('PACKAGE TRUST VERIFICATION')
$lines.Add("Files verified: $($result.summary.files_verified)")
$lines.Add("Errors: $($result.summary.error_count)")
$lines.Add("Approved: $($result.summary.approved_count)")
$lines.Add("Review required: $($result.summary.review_required_count)")
$lines.Add("Blocked: $($result.summary.blocked_count)")
$lines.Add("Overall: $($result.summary.overall_disposition)")
$lines.Add('')
$lines.Add('Proof: offline_authenticode_policy')
$lines.Add('- WinVerifyTrust used cache-only URL retrieval')
$lines.Add('- online revocation was not checked')
$lines.Add('- no package code executed')
$lines.Add('- no network, host, target, or VM activity')
$lines.Add('- strong-name cryptographic validation not performed')
$lines.Add('')
foreach ($record in $records) { $lines.Add("[$($record.disposition.ToUpperInvariant())] $($record.relative_path) - $($record.trust_scope) - $($record.signature_status)") }
foreach ($entry in $errors) { $lines.Add("[ERROR] $($entry.relative_path) - $($entry.message)") }
$lines.Add('')
$lines.Add('Artifacts:')
$lines.Add('- package_trust_verification.json')
$lines.Add('- package_trust_verification.txt')
if ($ObservationOnly) { $lines.Add('- package_trust_policy.starter.json') }
$lines | Set-Content -LiteralPath (Join-Path $OutputRoot 'package_trust_verification.txt') -Encoding UTF8

Write-Output ([pscustomobject]$result)
Write-Host "Evidence: $OutputRoot"
if ($overall -eq 'blocked') { exit 4 }
if ($overall -eq 'review_required' -and -not $ObservationOnly) { exit 3 }
exit 0
