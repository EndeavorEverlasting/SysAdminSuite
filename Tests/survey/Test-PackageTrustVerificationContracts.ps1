#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$trustScript = Join-Path $repoRoot 'scripts/Test-SasPackageTrust.ps1'
$policySchema = Join-Path $repoRoot 'schemas/harness/package-trust-policy.schema.json'
$resultSchema = Join-Path $repoRoot 'schemas/harness/package-trust-verification-result.schema.json'
$manifestPath = Join-Path $repoRoot 'harness/api/package-trust-verification-skill.json'
$docPath = Join-Path $repoRoot 'docs/PACKAGE_TRUST_VERIFICATION.md'
$skillPath = Join-Path $repoRoot '.claude/skills/package-static-analysis/SKILL.md'
$workflowPath = Join-Path $repoRoot '.github/workflows/package-static-analysis.yml'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-BaseResult {
    param([string]$InputRoot, [string[]]$RelativePaths, [string]$Path)
    $files = foreach ($relative in $RelativePaths) {
        $source = Join-Path $InputRoot $relative
        [ordered]@{
            relative_path = $relative.Replace('\', '/')
            extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
            sha256 = Get-Sha256 -Path $source
        }
    }
    $result = [ordered]@{
        schema_version = 'sas-package-static-analysis/v1'
        input = [ordered]@{ absolute_path_emitted = $false }
        proof = [ordered]@{
            file_execution_performed = $false
            archive_payload_extracted = $false
            network_activity_performed = $false
            target_mutation_performed = $false
            host_mutation_performed = $false
            signature_trust_validated = $false
            runtime_behavior_validated = $false
        }
        files = @($files)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Policy {
    param([object[]]$Entries, [string]$Path)
    [ordered]@{
        schema_version = 'sas-package-trust-policy/v1'
        policy_id = 'fixture-policy'
        default_disposition = 'blocked'
        unlisted_noncode_disposition = 'hash_only_approved'
        entries = @($Entries)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-TrustChild {
    param([string[]]$Arguments)
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $trustScript @Arguments 2>&1 | Out-String | Write-Verbose
    return $LASTEXITCODE
}

foreach ($path in @($trustScript, $policySchema, $resultSchema, $manifestPath, $docPath, $skillPath, $workflowPath)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing required package trust file: $path"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-True ([string]$manifest.schema_version -eq 'sas-package-trust-verification-skill/v1') 'Unexpected trust manifest schema.'
Assert-True ($manifest.operation.network_activity -eq $false) 'Trust operation must be network-free.'
Assert-True ($manifest.operation.package_execution -eq $false) 'Trust operation must not execute package code.'
Assert-True ($manifest.operation.online_revocation_check -eq $false) 'Trust operation must not claim online revocation.'

foreach ($schemaPath in @($policySchema, $resultSchema)) {
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    Assert-True ([string]$schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema') "Unexpected JSON Schema dialect: $schemaPath"
    Assert-True ($schema.additionalProperties -eq $false) "Schema must be closed: $schemaPath"
}

$scriptText = Get-Content -LiteralPath $trustScript -Raw
foreach ($required in @('WTD_CACHE_ONLY_URL_RETRIEVAL', 'WTD_REVOCATION_CHECK_NONE', 'WinVerifyTrust', 'source_path_contains_reparse_point', 'strong_name_cryptographic_validation_performed = $false')) {
    Assert-True ($scriptText.Contains($required)) "Missing trust safety contract: $required"
}
foreach ($forbidden in @('Get-AuthenticodeSignature', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-Process', 'Invoke-Command', 'New-PSSession')) {
    Assert-True (-not $scriptText.Contains($forbidden)) "Forbidden trust implementation surface found: $forbidden"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-package-trust-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$fixture = Join-Path $tempRoot 'fixture'
New-Item -ItemType Directory -Path $fixture | Out-Null
$cert = $null
$stores = New-Object System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Store]

try {
    $unsignedPath = Join-Path $fixture 'unsigned.ps1'
    $noncodePath = Join-Path $fixture 'readme.txt'
    Set-Content -LiteralPath $unsignedPath -Encoding UTF8 -Value "Write-Output 'fixture'"
    Set-Content -LiteralPath $noncodePath -Encoding UTF8 -Value 'fixture resource'
    $basePath = Join-Path $tempRoot 'base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths @('unsigned.ps1', 'readme.txt') -Path $basePath

    $observeOut = Join-Path $tempRoot 'observe'
    $exit = Invoke-TrustChild -Arguments @('-InputPath', $fixture, '-BaseResultPath', $basePath, '-ObservationOnly', '-OutputRoot', $observeOut, '-FixtureMode')
    Assert-True ($exit -eq 0) "Observation mode failed with exit code $exit"
    $observe = Get-Content -LiteralPath (Join-Path $observeOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$observe.summary.overall_disposition -eq 'review_required') 'Observation mode must not approve deployment.'
    Assert-True ($observe.proof.network_activity_performed -eq $false) 'Observation mode must report no network activity.'
    Assert-True ($observe.proof.cache_only_url_retrieval -eq $true) 'Cache-only URL retrieval must be explicit.'
    Assert-True (Test-Path -LiteralPath (Join-Path $observeOut 'package_trust_policy.starter.json')) 'Observation mode must emit a starter policy.'
    $unsignedObserved = @($observe.files | Where-Object { $_.relative_path -eq 'unsigned.ps1' })[0]
    Assert-True ([string]$unsignedObserved.signature_status -eq 'not_signed') "Unsigned fixture status was $($unsignedObserved.signature_status)"

    $unsignedPolicyPath = Join-Path $tempRoot 'unsigned-policy.json'
    Write-Policy -Entries @(
        [ordered]@{
            relative_path = 'unsigned.ps1'
            expected_sha256 = Get-Sha256 -Path $unsignedPath
            signature_requirement = 'allow_unsigned_explicit'
            approved_signer_thumbprints = @()
            approved_signer_subjects = @()
            approval_reference = 'FIXTURE-UNSIGNED-APPROVAL'
            observed_signature_status = 'not_signed'
            observed_signer_thumbprint = $null
            observed_signer_subject = $null
        }
    ) -Path $unsignedPolicyPath
    $unsignedOut = Join-Path $tempRoot 'unsigned-approved'
    $exit = Invoke-TrustChild -Arguments @('-InputPath', $fixture, '-BaseResultPath', $basePath, '-TrustPolicyPath', $unsignedPolicyPath, '-OutputRoot', $unsignedOut, '-FixtureMode')
    Assert-True ($exit -eq 0) "Explicit unsigned approval failed with exit code $exit"
    $unsignedResult = Get-Content -LiteralPath (Join-Path $unsignedOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$unsignedResult.summary.overall_disposition -eq 'approved_for_vm_intake') 'Explicit unsigned approval should pass exact-hash VM intake.'
    Assert-True ($unsignedResult.summary.deployment_approved -eq $true) 'Approved trust result must set deployment_approved true.'

    Set-Content -LiteralPath $unsignedPath -Encoding UTF8 -Value "Write-Output 'changed'"
    $mismatchOut = Join-Path $tempRoot 'hash-mismatch'
    $exit = Invoke-TrustChild -Arguments @('-InputPath', $fixture, '-BaseResultPath', $basePath, '-ObservationOnly', '-OutputRoot', $mismatchOut, '-FixtureMode')
    Assert-True ($exit -eq 4) "Hash mismatch should block with exit code 4, received $exit"
    $mismatch = Get-Content -LiteralPath (Join-Path $mismatchOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$mismatch.summary.overall_disposition -eq 'blocked') 'Hash mismatch must block.'
    Assert-True (@($mismatch.errors | Where-Object { $_.message -eq 'hash_mismatch_since_base_analysis' }).Count -eq 1) 'Hash mismatch evidence missing.'

    $signedPath = Join-Path $fixture 'signed.ps1'
    Set-Content -LiteralPath $signedPath -Encoding UTF8 -Value "Write-Output 'signed fixture'"
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=SysAdminSuite Fixture Signer' -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -NotAfter (Get-Date).AddDays(2)
    foreach ($storeName in @('Root', 'TrustedPublisher')) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $store.Add($cert)
        $stores.Add($store)
    }
    $signature = Set-AuthenticodeSignature -FilePath $signedPath -Certificate $cert -HashAlgorithm SHA256
    Assert-True ([string]$signature.Status -in @('Valid', 'UnknownError')) 'Fixture signing failed.'

    $signedBasePath = Join-Path $tempRoot 'signed-base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths @('signed.ps1') -Path $signedBasePath
    $signedPolicyPath = Join-Path $tempRoot 'signed-policy.json'
    Write-Policy -Entries @(
        [ordered]@{
            relative_path = 'signed.ps1'
            expected_sha256 = Get-Sha256 -Path $signedPath
            signature_requirement = 'required_valid'
            approved_signer_thumbprints = @($cert.Thumbprint)
            approved_signer_subjects = @()
            approval_reference = 'FIXTURE-SIGNER-APPROVAL'
            observed_signature_status = 'valid'
            observed_signer_thumbprint = $cert.Thumbprint
            observed_signer_subject = $cert.Subject
        }
    ) -Path $signedPolicyPath
    $signedOut = Join-Path $tempRoot 'signed-approved'
    $exit = Invoke-TrustChild -Arguments @('-InputPath', $fixture, '-BaseResultPath', $signedBasePath, '-TrustPolicyPath', $signedPolicyPath, '-OutputRoot', $signedOut, '-FixtureMode')
    Assert-True ($exit -eq 0) "Signed fixture approval failed with exit code $exit"
    $signedResult = Get-Content -LiteralPath (Join-Path $signedOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    $signedRecord = @($signedResult.files)[0]
    Assert-True ([string]$signedRecord.signature_status -eq 'valid') "Signed fixture status was $($signedRecord.signature_status)"
    Assert-True ($signedRecord.signer_identity_match -eq $true) 'Signed fixture signer identity did not match policy.'
    Assert-True ([string]$signedResult.summary.overall_disposition -eq 'approved_for_vm_intake') 'Signed fixture should pass VM intake gate.'

    Add-Content -LiteralPath $signedPath -Encoding UTF8 -Value '# tampered after signing'
    $tamperedBasePath = Join-Path $tempRoot 'tampered-base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths @('signed.ps1') -Path $tamperedBasePath
    $tamperedPolicyPath = Join-Path $tempRoot 'tampered-policy.json'
    Write-Policy -Entries @(
        [ordered]@{
            relative_path = 'signed.ps1'
            expected_sha256 = Get-Sha256 -Path $signedPath
            signature_requirement = 'allow_unsigned_explicit'
            approved_signer_thumbprints = @()
            approved_signer_subjects = @()
            approval_reference = 'FIXTURE-UNSIGNED-EXCEPTION'
            observed_signature_status = 'bad_digest'
            observed_signer_thumbprint = $cert.Thumbprint
            observed_signer_subject = $cert.Subject
        }
    ) -Path $tamperedPolicyPath
    $tamperedOut = Join-Path $tempRoot 'tampered'
    $exit = Invoke-TrustChild -Arguments @('-InputPath', $fixture, '-BaseResultPath', $tamperedBasePath, '-TrustPolicyPath', $tamperedPolicyPath, '-OutputRoot', $tamperedOut, '-FixtureMode')
    Assert-True ($exit -eq 4) "Tampered signature should block with exit code 4, received $exit"
    $tampered = Get-Content -LiteralPath (Join-Path $tamperedOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$tampered.summary.overall_disposition -eq 'blocked') 'Tampered signature must remain blocked.'
    $tamperedStatus = [string](@($tampered.files)[0].signature_status)
    Assert-True ($tamperedStatus -notin @('valid', 'not_signed')) "Tampered signature was misclassified as $tamperedStatus"
}
finally {
    foreach ($store in $stores) {
        try {
            if ($cert) { $store.Remove($cert) }
        } finally {
            $store.Close()
            $store.Dispose()
        }
    }
    if ($cert) {
        $my = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
        try {
            $my.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $my.Remove($cert)
        } finally {
            $my.Close()
            $my.Dispose()
            $cert.Dispose()
        }
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: 6 package trust verification contract groups'
