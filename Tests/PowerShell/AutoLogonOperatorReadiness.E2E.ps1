#Requires -Version 5.1
<#
.SYNOPSIS
Bounded local-only E2E for cross-user AutoLogon operator readiness.

.DESCRIPTION
Runs only against disposable local fixture state. It creates no field target, performs no target contact,
and never invokes the Public Desktop AutoLogon Remote delegate. The test exercises the real readiness
installer, then runs the installed verifier under a newly created non-administrator local account.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$runtimeRoot = 'C:\SASAL'
$programData = if ([string]::IsNullOrWhiteSpace([string]$env:ProgramData)) { 'C:\ProgramData' } else { $env:ProgramData }
$programDataSuiteRoot = Join-Path $programData 'SysAdminSuite'
$installRoot = Join-Path $programDataSuiteRoot 'bin'
$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
if ([string]::IsNullOrWhiteSpace($commonDesktop)) { $commonDesktop = 'C:\Users\Public\Desktop' }
$commonDocuments = [Environment]::GetFolderPath('CommonDocuments')
if ([string]::IsNullOrWhiteSpace($commonDocuments)) { $commonDocuments = 'C:\Users\Public\Documents' }
$publicEvidenceRoot = Join-Path $commonDocuments 'SysAdminSuite'
$publicDesktopDelegate = Join-Path $commonDesktop 'SysAdminSuite - AutoLogon Remote.cmd'
$originalMachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$fixtureUserName = 'sasready' + ([guid]::NewGuid().ToString('N').Substring(0,8))
$fixturePasswordText = 'SasRdy!' + ([guid]::NewGuid().ToString('N').Substring(0,18)) + '9aA'
$fixtureUserCreated = $false
$fixtureUserSid = ''
$secondaryLogonWasRunning = $false

function Get-SasTestSha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = $null
    $sha256 = $null
    try {
        $stream = [IO.File]::Open($LiteralPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bytes = $sha256.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Test-SasPathSegment {
    param([AllowNull()][string]$PathValue,[Parameter(Mandatory = $true)][string]$Expected)
    $expectedNormalized = $Expected.Trim().TrimEnd('\')
    foreach ($segment in @(([string]$PathValue) -split ';')) {
        $candidate = $segment.Trim().Trim('"').TrimEnd('\')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            $candidate.Equals($expectedNormalized,[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Write-SasUtf8NoBom {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)][string]$Text)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

$collisions = @(@(
    $runtimeRoot,
    $programDataSuiteRoot,
    $publicEvidenceRoot,
    $publicDesktopDelegate
) | Where-Object { Test-Path -LiteralPath $_ })
if ($collisions.Count -gt 0) {
    throw ('AUTOLOGON_OPERATOR_READINESS_E2E_FIXTURE_COLLISION: refusing to replace pre-existing state: ' + ($collisions -join ', '))
}

try {
    # Force the installer to exercise the Machine PATH mutation and broadcast path.
    $baselineSegments = @(([string]$originalMachinePath) -split ';' | Where-Object {
        $candidate = ([string]$_).Trim().Trim('"').TrimEnd('\')
        -not (-not [string]::IsNullOrWhiteSpace($candidate) -and
            $candidate.Equals($installRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase))
    })
    [Environment]::SetEnvironmentVariable('Path',($baselineSegments -join ';'),'Machine')

    $runtimeScripts = Join-Path $runtimeRoot 'scripts'
    $runtimeGit = Join-Path $runtimeRoot '.git'
    New-Item -ItemType Directory -Path $runtimeScripts -Force | Out-Null
    New-Item -ItemType Directory -Path $runtimeGit -Force | Out-Null
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

    $resolverName = 'Resolve-SasAutoLogonManifestAuthority.ps1'
    $auditorName = 'Test-SasAutoLogonRuntimeSeal.ps1'
    $resolverSource = Join-Path $repoRoot ('scripts\' + $resolverName)
    $auditorSource = Join-Path $repoRoot ('scripts\' + $auditorName)
    $resolverFixture = Join-Path $runtimeScripts $resolverName
    $auditorFixture = Join-Path $runtimeScripts $auditorName
    Copy-Item -LiteralPath $resolverSource -Destination $resolverFixture -Force
    Copy-Item -LiteralPath $auditorSource -Destination $auditorFixture -Force

    Write-SasUtf8NoBom -Path (Join-Path $installRoot 'sas.cmd') -Text @'
@echo off
if /I "%~1"=="platform" (
  echo SAS_OPERATOR_READINESS_E2E_PLATFORM_READY
  exit /b 0
)
exit /b 9
'@
    Write-SasUtf8NoBom -Path (Join-Path $installRoot 'Invoke-SasNetworkAwareField.ps1') -Text @'
# Local-only readiness E2E placeholder. Intentionally never invoked by this test.
throw 'AUTOLOGON_OPERATOR_READINESS_E2E_NETWORK_ENTRYPOINT_MUST_NOT_RUN'
'@

    $trackedFileHashes = @(
        [pscustomobject][ordered]@{
            path = 'scripts/Resolve-SasAutoLogonManifestAuthority.ps1'
            sha256 = Get-SasTestSha256Hex -LiteralPath $resolverFixture
        },
        [pscustomobject][ordered]@{
            path = 'scripts/Test-SasAutoLogonRuntimeSeal.ps1'
            sha256 = Get-SasTestSha256Hex -LiteralPath $auditorFixture
        }
    )
    $manifest = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-short-runtime/v2'
        runtime_root = $runtimeRoot
        source_root = $repoRoot
        prepared_commit = 'fixture-readiness-e2e'
        prepared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        preparation_network_classification = 'GUEST_INTERNET'
        preparation_network_label = 'CI_DISPOSABLE_LOCAL_FIXTURE'
        runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
        runtime_remotes_removed = $true
        protected_bootstrap_git_network_allowed = $false
        tracked_file_hash_algorithm = 'SHA256'
        tracked_file_count = $trackedFileHashes.Count
        tracked_file_hashes = $trackedFileHashes
        target_contact_performed = $false
        target_mutation_performed = $false
    }
    $manifestPath = Join-Path $runtimeGit 'sas-autologon-short-runtime.json'
    Write-SasUtf8NoBom -Path $manifestPath -Text ($manifest | ConvertTo-Json -Depth 8)

    $installer = Join-Path $repoRoot 'scripts\Install-SasAutoLogonOperatorReadiness.ps1'
    & $installer

    $machinePathAfterInstall = [Environment]::GetEnvironmentVariable('Path','Machine')
    if (-not (Test-SasPathSegment -PathValue $machinePathAfterInstall -Expected $installRoot)) {
        throw 'AUTOLOGON_OPERATOR_READINESS_E2E_MACHINE_PATH_NOT_INSTALLED'
    }

    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $securePassword = ConvertTo-SecureString $fixturePasswordText -AsPlainText -Force
    New-LocalUser -Name $fixtureUserName -Password $securePassword -Description 'Disposable SysAdminSuite readiness E2E account' | Out-Null
    $fixtureUserCreated = $true
    $fixtureUser = Get-LocalUser -Name $fixtureUserName -ErrorAction Stop
    $fixtureUserSid = [string]$fixtureUser.SID.Value
    $usersGroup = Get-LocalGroup -SID (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545'))
    Add-LocalGroupMember -Group $usersGroup.Name -Member $fixtureUserName
    $administratorsGroup = Get-LocalGroup -SID (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))
    $unexpectedAdmin = @(Get-LocalGroupMember -Group $administratorsGroup.Name -ErrorAction Stop | Where-Object {
        $null -ne $_.SID -and [string]$_.SID.Value -eq $fixtureUserSid
    })
    if ($unexpectedAdmin.Count -gt 0) {
        throw 'AUTOLOGON_OPERATOR_READINESS_E2E_ACCOUNT_BECAME_ADMINISTRATOR'
    }

    $secondaryLogon = Get-Service -Name seclogon -ErrorAction Stop
    $secondaryLogonWasRunning = ($secondaryLogon.Status -eq 'Running')
    if (-not $secondaryLogonWasRunning) { Start-Service -Name seclogon -ErrorAction Stop }

    $credential = New-Object Management.Automation.PSCredential(($env:COMPUTERNAME + '\' + $fixtureUserName),$securePassword)
    $installedVerifier = Join-Path $installRoot 'Test-SasAutoLogonOperatorReadiness.ps1'
    $stdoutPath = Join-Path $publicEvidenceRoot 'ci-standard-user.stdout.txt'
    $stderrPath = Join-Path $publicEvidenceRoot 'ci-standard-user.stderr.txt'
    $argumentList = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy','Bypass',
        '-File',('"' + $installedVerifier + '"'),
        '-RequireStandardUser'
    )
    $child = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -Credential $credential -LoadUserProfile -WorkingDirectory $env:SystemRoot `
        -ArgumentList $argumentList -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -Wait -PassThru

    if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-Content -LiteralPath $stdoutPath | Out-Host }
    if ($child.ExitCode -ne 0) {
        $stderrText = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)
        } else { '' }
        throw "AUTOLOGON_OPERATOR_READINESS_E2E_STANDARD_USER_FAILED: exit=$($child.ExitCode) stderr=$stderrText"
    }

    $receiptPath = Join-Path $publicEvidenceRoot 'autologon-operator-readiness.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "AUTOLOGON_OPERATOR_READINESS_E2E_RECEIPT_MISSING: $receiptPath"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$receipt.status -ne 'PASS' -or
        [string]$receipt.classification -ne 'AUTOLOGON_OPERATOR_READINESS_VERIFIED' -or
        -not [bool]$receipt.require_standard_user -or
        [bool]$receipt.current_token_is_administrator -or
        [bool]$receipt.current_account_is_local_administrator_member -or
        -not [bool]$receipt.deployment_run_root_write_probe_passed -or
        [bool]$receipt.receipt_is_authority -or
        [bool]$receipt.network_activity_performed -or
        [bool]$receipt.target_contact_performed -or
        [bool]$receipt.target_mutation_performed -or
        [bool]$receipt.deployment_started) {
        throw ('AUTOLOGON_OPERATOR_READINESS_E2E_RECEIPT_INVALID: ' + ($receipt | ConvertTo-Json -Depth 8 -Compress))
    }

    Write-Host 'PASS: bounded true-standard-user AutoLogon operator-readiness E2E.' -ForegroundColor Green
    Write-Host "Fixture account SID: $fixtureUserSid"
    Write-Host 'Target contact: NONE; deployment started: NO.' -ForegroundColor Green
}
finally {
    if ($fixtureUserCreated) {
        try { Remove-LocalUser -Name $fixtureUserName -ErrorAction Stop } catch { Write-Warning "Could not remove fixture user: $($_.Exception.Message)" }
        if (-not [string]::IsNullOrWhiteSpace($fixtureUserSid)) {
            try {
                $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { [string]$_.SID -eq $fixtureUserSid })
                foreach ($profile in $profiles) {
                    if (-not [bool]$profile.Loaded) { Remove-CimInstance -InputObject $profile -ErrorAction Stop }
                }
            }
            catch { Write-Warning "Could not remove fixture profile: $($_.Exception.Message)" }
        }
    }
    if (-not $secondaryLogonWasRunning) {
        try { Stop-Service -Name seclogon -Force -ErrorAction SilentlyContinue } catch { }
    }
    foreach ($path in @($publicDesktopDelegate,$publicEvidenceRoot,$programDataSuiteRoot,$runtimeRoot)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    [Environment]::SetEnvironmentVariable('Path',$originalMachinePath,'Machine')
}
