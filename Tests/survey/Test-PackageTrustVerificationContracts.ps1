#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$trustScript = Join-Path $repoRoot 'scripts/Invoke-SasPackageTrust.ps1'
$interopPath = Join-Path $repoRoot 'tools/package-analysis/SasPackageTrustInterop.cs'
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

function Get-FixtureFileClass {
    param([string]$Extension)
    switch ($Extension) {
        '.ps1' { 'script' }
        '.py' { 'script' }
        '.zip' { 'archive' }
        '.exe' { 'portable_executable' }
        '.dll' { 'portable_executable' }
        default { 'other' }
    }
}

function Write-BaseResult {
    param([string]$InputRoot, [string[]]$RelativePaths, [string]$Path)
    $files = foreach ($relative in $RelativePaths) {
        $source = Join-Path $InputRoot $relative
        $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
        [ordered]@{
            relative_path = $relative.Replace('\', '/')
            extension = $extension
            file_class = Get-FixtureFileClass -Extension $extension
            archive = if ($extension -eq '.zip') { [ordered]@{ nested_installer_extensions = @('.exe') } } else { $null }
            sha256 = Get-Sha256 -Path $source
        }
    }
    [ordered]@{
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
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function New-PolicyEntry {
    param(
        [string]$RelativePath,
        [string]$SourcePath,
        [string]$Requirement,
        [string[]]$Thumbprints = @(),
        [string]$ApprovalReference = 'FIXTURE-APPROVAL'
    )
    return [ordered]@{
        relative_path = $RelativePath
        expected_sha256 = Get-Sha256 -Path $SourcePath
        signature_requirement = $Requirement
        approved_signer_thumbprints = @($Thumbprints)
        approved_signer_subjects = @()
        approval_reference = $ApprovalReference
        observed_signature_status = $null
        observed_signer_thumbprint = $null
        observed_signer_subject = $null
    }
}

function Invoke-TrustChild {
    param(
        [string]$Scenario,
        [string[]]$Arguments,
        [int]$TimeoutMilliseconds = 75000
    )

    Write-Host "SCENARIO START: $Scenario"
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $pwsh
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $trustScript) + $Arguments) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        try { $process.Kill($true) } catch { }
        throw "Trust child timed out after $TimeoutMilliseconds ms: $Scenario"
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $script:LastTrustChildOutput = ($stdout + [Environment]::NewLine + $stderr).Trim()
    $exitCode = $process.ExitCode
    $process.Dispose()
    Write-Host "SCENARIO END: $Scenario (exit $exitCode)"
    return $exitCode
}

function New-EphemeralCodeSigningCert {
    # In-memory/My-store only. Never install into Root or TrustedPublisher (those stores raise interactive Security Warning UI).
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=SysAdminSuite Fixture Signer',
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $request.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $false)
    )
    $request.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
            $true
        )
    )
    $ekuOids = [System.Security.Cryptography.OidCollection]::new()
    [void]$ekuOids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3', 'Code Signing'))
    $request.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($ekuOids, $false)
    )
    $notBefore = [DateTimeOffset]::UtcNow.AddMinutes(-5)
    $notAfter = $notBefore.AddDays(2)
    $ephemeral = $request.CreateSelfSigned($notBefore, $notAfter)
    $securePassword = ConvertTo-SecureString -String ('fixture-' + [guid]::NewGuid().ToString('N')) -AsPlainText -Force
    $pfxBytes = $ephemeral.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $securePassword)
    $ephemeral.Dispose()
    return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $pfxBytes,
        $securePassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet
    )
}

Write-Host 'SETUP START: package trust contract surfaces'
foreach ($path in @($trustScript, $interopPath, $policySchema, $resultSchema, $manifestPath, $docPath, $skillPath, $workflowPath)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing required package trust file: $path"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-True ([string]$manifest.schema_version -eq 'sas-package-trust-verification-skill/v1') 'Unexpected trust manifest schema.'
Assert-True ([string]$manifest.entrypoint -eq 'scripts/Invoke-SasPackageTrust.ps1') 'Unexpected canonical trust entrypoint.'
Assert-True ($manifest.operation.network_activity -eq $false) 'Trust operation must be network-free.'
Assert-True ($manifest.operation.package_execution -eq $false) 'Trust operation must not execute package code.'
Assert-True ($manifest.operation.online_revocation_check -eq $false) 'Trust operation must not claim online revocation.'

foreach ($schemaPath in @($policySchema, $resultSchema)) {
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    Assert-True ([string]$schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema') "Unexpected JSON Schema dialect: $schemaPath"
    Assert-True ($schema.additionalProperties -eq $false) "Schema must be closed: $schemaPath"
}

$scriptText = (Get-Content -LiteralPath $trustScript -Raw) + (Get-Content -LiteralPath $interopPath -Raw)
foreach ($required in @(
    'WTD_CACHE_ONLY_URL_RETRIEVAL',
    'WTD_REVOCATION_CHECK_NONE',
    'WinVerifyTrust',
    'source_path_contains_reparse_point',
    'strong_name_cryptographic_validation_performed = $false',
    'code_policy_required',
    'signed_file_requires_required_valid_policy',
    'opaque_code_container_requires_component_intake'
)) {
    Assert-True ($scriptText.Contains($required)) "Missing trust safety contract: $required"
}
foreach ($forbidden in @('Get-AuthenticodeSignature', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-Process', 'Invoke-Command', 'New-PSSession')) {
    Assert-True (-not $scriptText.Contains($forbidden)) "Forbidden trust implementation surface found: $forbidden"
}
Assert-True (-not $scriptText.Contains('TrustedPublisher')) 'Trust engine must not mutate TrustedPublisher.'
Assert-True (-not $scriptText.Contains("X509Store('Root'")) 'Trust engine must not mutate Root.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-package-trust-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $tempRoot 'fixture'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$cert = $null
$myStore = $null

try {
    Write-Host 'SETUP: writing fixture files'
    $unsignedPath = Join-Path $fixture 'unsigned.ps1'
    $selfSignedPath = Join-Path $fixture 'selfsigned.ps1'
    $trustedSignedPath = Join-Path $fixture 'trusted-signed.exe'
    $pythonPath = Join-Path $fixture 'tool.py'
    $archivePath = Join-Path $fixture 'bundle.zip'
    $noncodePath = Join-Path $fixture 'readme.txt'
    Set-Content -LiteralPath $unsignedPath -Encoding UTF8 -Value "Write-Output 'fixture'"
    Set-Content -LiteralPath $selfSignedPath -Encoding UTF8 -Value "Write-Output 'self-signed fixture'"
    Set-Content -LiteralPath $pythonPath -Encoding UTF8 -Value "print('fixture')"
    [System.IO.File]::WriteAllBytes($archivePath, [byte[]](80, 75, 3, 4, 0, 0, 0, 0))
    Set-Content -LiteralPath $noncodePath -Encoding UTF8 -Value 'fixture resource'

    # Valid Authenticode proof uses an already-trusted Windows binary copy. Never install fixture roots.
    $systemSignedSource = (Get-Command pwsh -ErrorAction Stop).Source
    Assert-True (Test-Path -LiteralPath $systemSignedSource -PathType Leaf) "Missing system-signed source: $systemSignedSource"
    [System.IO.File]::Copy($systemSignedSource, $trustedSignedPath, $true)
    Write-Host "SETUP: copied system-signed binary from pwsh for valid Authenticode proof"

    Write-Host 'SETUP: creating ephemeral code-signing certificate in CurrentUser\\My only'
    $cert = New-EphemeralCodeSigningCert
    $myStore = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
    $myStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $myStore.Add($cert)
    Write-Host 'SETUP: signing self-signed script without Root/TrustedPublisher trust'
    $signature = Set-AuthenticodeSignature -FilePath $selfSignedPath -Certificate $cert -HashAlgorithm SHA256
    Assert-True ([string]$signature.Status -in @('Valid', 'UnknownError', 'NotTrusted')) "Fixture signing failed: $($signature.Status) $($signature.StatusMessage)"
    Write-Host 'SETUP END: fixtures ready (no Root or TrustedPublisher mutation)'

    $allPaths = @('unsigned.ps1', 'selfsigned.ps1', 'trusted-signed.exe', 'tool.py', 'bundle.zip', 'readme.txt')
    $basePath = Join-Path $tempRoot 'base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths $allPaths -Path $basePath

    $observeOut = Join-Path $tempRoot 'observe'
    $exit = Invoke-TrustChild -Scenario 'observation' -Arguments @('-InputPath', $fixture, '-BaseResultPath', $basePath, '-ObservationOnly', '-OutputRoot', $observeOut, '-FixtureMode')
    Assert-True ($exit -eq 0) "Observation mode failed with exit code $exit`n$script:LastTrustChildOutput"
    $observe = Get-Content -LiteralPath (Join-Path $observeOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$observe.summary.overall_disposition -eq 'review_required') 'Observation mode must not approve deployment.'
    Assert-True ($observe.proof.network_activity_performed -eq $false) 'Observation mode must report no network activity.'
    Assert-True ($observe.proof.cache_only_url_retrieval -eq $true) 'Cache-only URL retrieval must be explicit.'
    $observedByPath = @{}
    foreach ($record in $observe.files) { $observedByPath[[string]$record.relative_path] = $record }
    Assert-True ([string]$observedByPath['unsigned.ps1'].signature_status -eq 'not_signed') 'Unsigned fixture status mismatch.'
    Assert-True ([string]$observedByPath['trusted-signed.exe'].signature_status -eq 'valid') "System-signed fixture status mismatch: $($observedByPath['trusted-signed.exe'].signature_status)"
    Assert-True ([string]$observedByPath['selfsigned.ps1'].signature_status -notin @('valid', 'not_signed')) 'Self-signed fixture unexpectedly looked fully trusted or unsigned.'
    Assert-True ([string]$observedByPath['tool.py'].trust_scope -eq 'code_policy_required') 'Python code was treated as non-code.'
    Assert-True ([string]$observedByPath['bundle.zip'].trust_scope -eq 'code_policy_required') 'Archive was treated as non-code.'
    Assert-True (Test-Path -LiteralPath (Join-Path $observeOut 'package_trust_policy.starter.json')) 'Observation mode must emit a starter policy.'
    $trustedThumbprint = [string]$observedByPath['trusted-signed.exe'].signer_thumbprint
    Assert-True (-not [string]::IsNullOrWhiteSpace($trustedThumbprint)) 'Trusted signed fixture must expose a signer thumbprint.'

    $approvedBasePath = Join-Path $tempRoot 'approved-base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths @('unsigned.ps1', 'trusted-signed.exe', 'tool.py', 'readme.txt') -Path $approvedBasePath
    $approvedPolicyPath = Join-Path $tempRoot 'approved-policy.json'
    Write-Policy -Entries @(
        (New-PolicyEntry -RelativePath 'unsigned.ps1' -SourcePath $unsignedPath -Requirement 'allow_unsigned_explicit' -ApprovalReference 'FIXTURE-UNSIGNED'),
        (New-PolicyEntry -RelativePath 'tool.py' -SourcePath $pythonPath -Requirement 'allow_unsigned_explicit' -ApprovalReference 'FIXTURE-PYTHON'),
        (New-PolicyEntry -RelativePath 'trusted-signed.exe' -SourcePath $trustedSignedPath -Requirement 'required_valid' -Thumbprints @($trustedThumbprint) -ApprovalReference 'FIXTURE-SIGNER')
    ) -Path $approvedPolicyPath
    $approvedOut = Join-Path $tempRoot 'approved'
    $exit = Invoke-TrustChild -Scenario 'approved signer and explicit code exceptions' -Arguments @('-InputPath', $fixture, '-BaseResultPath', $approvedBasePath, '-TrustPolicyPath', $approvedPolicyPath, '-OutputRoot', $approvedOut, '-FixtureMode')
    Assert-True ($exit -eq 0) "Approved composite failed with exit code $exit`n$script:LastTrustChildOutput"
    $approved = Get-Content -LiteralPath (Join-Path $approvedOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$approved.summary.overall_disposition -eq 'approved_for_vm_intake') 'Approved composite should pass VM intake.'
    Assert-True ($approved.summary.deployment_approved -eq $true) 'Approved composite must set deployment_approved.'
    $approvedSigned = @($approved.files | Where-Object { $_.relative_path -eq 'trusted-signed.exe' })[0]
    Assert-True ($approvedSigned.signer_identity_match -eq $true) 'Trusted signed fixture signer identity did not match policy.'

    $blockedBasePath = Join-Path $tempRoot 'blocked-base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths @('trusted-signed.exe', 'tool.py', 'bundle.zip') -Path $blockedBasePath
    $blockedPolicyPath = Join-Path $tempRoot 'blocked-policy.json'
    Write-Policy -Entries @(
        (New-PolicyEntry -RelativePath 'trusted-signed.exe' -SourcePath $trustedSignedPath -Requirement 'allow_unsigned_explicit' -ApprovalReference 'INVALID-SIGNED-EXCEPTION'),
        (New-PolicyEntry -RelativePath 'bundle.zip' -SourcePath $archivePath -Requirement 'review_required' -ApprovalReference 'OPAQUE-REVIEW')
    ) -Path $blockedPolicyPath
    $blockedOut = Join-Path $tempRoot 'blocked'
    $exit = Invoke-TrustChild -Scenario 'signed exception misuse and opaque code' -Arguments @('-InputPath', $fixture, '-BaseResultPath', $blockedBasePath, '-TrustPolicyPath', $blockedPolicyPath, '-OutputRoot', $blockedOut, '-FixtureMode')
    Assert-True ($exit -eq 4) "Fail-closed composite should return 4, received $exit`n$script:LastTrustChildOutput"
    $blocked = Get-Content -LiteralPath (Join-Path $blockedOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    $blockedByPath = @{}
    foreach ($record in $blocked.files) { $blockedByPath[[string]$record.relative_path] = $record }
    Assert-True ([string]$blockedByPath['trusted-signed.exe'].disposition -eq 'blocked') 'Signed file passed an unsigned exception.'
    Assert-True (@($blockedByPath['trusted-signed.exe'].reasons) -contains 'signed_file_requires_required_valid_policy') 'Signed misuse reason missing.'
    Assert-True ([string]$blockedByPath['tool.py'].disposition -eq 'blocked') 'Unlisted Python code must be blocked.'
    Assert-True ([string]$blockedByPath['bundle.zip'].disposition -eq 'blocked') 'Opaque archive must be blocked.'
    Assert-True (@($blockedByPath['bundle.zip'].reasons) -contains 'opaque_code_container_requires_component_intake') 'Opaque archive reason missing.'

    $tamperBasePath = Join-Path $tempRoot 'tamper-base.json'
    Write-BaseResult -InputRoot $fixture -RelativePaths @('unsigned.ps1', 'selfsigned.ps1', 'tool.py') -Path $tamperBasePath
    Set-Content -LiteralPath $unsignedPath -Encoding UTF8 -Value "Write-Output 'changed after base'"
    # Corrupt signed body bytes while leaving the trailing Authenticode block present so WinTrust reports digest failure, not not_signed.
    $signedText = [System.IO.File]::ReadAllText($selfSignedPath)
    Assert-True ($signedText -match 'SIG # End signature block') 'Self-signed fixture is missing an Authenticode signature block.'
    $tamperedText = $signedText.Replace("Write-Output 'self-signed fixture'", "Write-Output 'self-signed fixture TAMPERED'")
    Assert-True ($tamperedText -ne $signedText) 'Failed to corrupt self-signed fixture body.'
    [System.IO.File]::WriteAllText($selfSignedPath, $tamperedText)
    # Keep unsigned base hash stale (continuity failure). Refresh self-signed base hash so WinTrust evaluates the broken signature.
    $tamperBase = Get-Content -LiteralPath $tamperBasePath -Raw | ConvertFrom-Json
    $selfSignedBaseRecord = @($tamperBase.files | Where-Object { $_.relative_path -eq 'selfsigned.ps1' })[0]
    $selfSignedBaseRecord.sha256 = Get-Sha256 -Path $selfSignedPath
    $tamperBase | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tamperBasePath -Encoding UTF8
    $tamperPolicyPath = Join-Path $tempRoot 'tamper-policy.json'
    Write-Policy -Entries @(
        (New-PolicyEntry -RelativePath 'unsigned.ps1' -SourcePath $unsignedPath -Requirement 'allow_unsigned_explicit' -ApprovalReference 'HASH-MISMATCH-EXPECTED'),
        (New-PolicyEntry -RelativePath 'selfsigned.ps1' -SourcePath $selfSignedPath -Requirement 'allow_unsigned_explicit' -ApprovalReference 'TAMPER-MUST-BLOCK'),
        (New-PolicyEntry -RelativePath 'tool.py' -SourcePath $pythonPath -Requirement 'allow_unsigned_explicit' -ApprovalReference 'FIXTURE-PYTHON')
    ) -Path $tamperPolicyPath
    $tamperOut = Join-Path $tempRoot 'tamper'
    $exit = Invoke-TrustChild -Scenario 'hash continuity and tamper rejection' -Arguments @('-InputPath', $fixture, '-BaseResultPath', $tamperBasePath, '-TrustPolicyPath', $tamperPolicyPath, '-OutputRoot', $tamperOut, '-FixtureMode')
    Assert-True ($exit -eq 4) "Tamper composite should return 4, received $exit`n$script:LastTrustChildOutput"
    $tamper = Get-Content -LiteralPath (Join-Path $tamperOut 'package_trust_verification.json') -Raw | ConvertFrom-Json
    Assert-True (@($tamper.errors | Where-Object { $_.relative_path -eq 'unsigned.ps1' -and $_.message -eq 'hash_mismatch_since_base_analysis' }).Count -eq 1) 'Hash mismatch evidence missing.'
    $tamperedSigned = @($tamper.files | Where-Object { $_.relative_path -eq 'selfsigned.ps1' })[0]
    Assert-True ([string]$tamperedSigned.disposition -eq 'blocked') 'Tampered signature must remain blocked.'
    Assert-True ([string]$tamperedSigned.signature_status -notin @('valid', 'not_signed')) 'Tampered signature was treated as valid or unsigned.'
}
finally {
    if ($myStore) {
        try {
            if ($cert) { $myStore.Remove($cert) }
        } finally {
            $myStore.Close()
            $myStore.Dispose()
        }
    }
    if ($cert) { $cert.Dispose() }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: 8 package trust verification contract groups across 4 bounded scenarios'
