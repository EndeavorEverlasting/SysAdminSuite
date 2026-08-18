#Requires -Version 5.1
<#
.SYNOPSIS
Repairs the protected local AutoLogon runtime for the S4U transport path-budget defect.

.DESCRIPTION
Local-only emergency repair for an already prepared SysAdminSuite AutoLogon runtime.
It performs no Git, network, target, credential, package, or deployment activity.

The repair is deliberately anchor-based instead of line-ending-sensitive regex. It
supports both CRLF and LF source files, writes backups before mutation, parses both
patched PowerShell surfaces before committing them, and restores both originals on
any failure.
#>
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot,
    [switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmRepair) {
    throw 'Runtime repair requires -ConfirmRepair.'
}

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$transportPath = Join-Path $RuntimeRoot 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
$statusPath = Join-Path $RuntimeRoot 'scripts\Get-SasAutoLogonS4URunStatus.ps1'
foreach ($required in @($transportPath,$statusPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required runtime repair surface missing: $required"
    }
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $RuntimeRoot 'runs\field-hotfixes'
    }
    else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes'
    }
    $EvidenceRoot = Join-Path $base ('s4u-path-repair-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null

$transportBackup = Join-Path $EvidenceRoot 'Test-SasSoftwareDeploymentTransport.before.ps1'
$statusBackup = Join-Path $EvidenceRoot 'Get-SasAutoLogonS4URunStatus.before.ps1'
$resultPath = Join-Path $EvidenceRoot 's4u-path-budget-runtime-repair-result.json'
Copy-Item -LiteralPath $transportPath -Destination $transportBackup -Force
Copy-Item -LiteralPath $statusPath -Destination $statusBackup -Force

function Get-SasRepairSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = $null
    $sha = $null
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Assert-SasRepairParse {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $detail = (@($errors | ForEach-Object { $_.Message }) -join '; ')
        throw "PowerShell parser rejected repaired surface ${Label}: $detail"
    }
}

function Insert-SasRepairAfterUniqueLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Anchor,
        [Parameter(Mandatory = $true)][string]$Insertion
    )
    $first = $Text.IndexOf($Anchor,[StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Repair anchor not found: $Anchor" }
    $second = $Text.IndexOf($Anchor,$first + $Anchor.Length,[StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Repair anchor is ambiguous: $Anchor" }
    return $Text.Insert($first + $Anchor.Length,$Insertion)
}

function Insert-SasRepairBeforeUniqueLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Anchor,
        [Parameter(Mandatory = $true)][string]$Insertion
    )
    $first = $Text.IndexOf($Anchor,[StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Repair anchor not found: $Anchor" }
    $second = $Text.IndexOf($Anchor,$first + $Anchor.Length,[StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Repair anchor is ambiguous: $Anchor" }
    return $Text.Insert($first,$Insertion)
}

function Replace-SasRepairUniqueLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$OldValue,
        [Parameter(Mandatory = $true)][string]$NewValue
    )
    $first = $Text.IndexOf($OldValue,[StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Repair anchor not found: $OldValue" }
    $second = $Text.IndexOf($OldValue,$first + $OldValue.Length,[StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Repair anchor is ambiguous: $OldValue" }
    return $Text.Remove($first,$OldValue.Length).Insert($first,$NewValue)
}

$transportBefore = Get-SasRepairSha256 -Path $transportPath
$statusBefore = Get-SasRepairSha256 -Path $statusPath
$classification = 'AUTOLOGON_S4U_PATH_BUDGET_RUNTIME_REPAIR_APPLIED'

try {
    $transportText = [IO.File]::ReadAllText($transportPath)
    $statusText = [IO.File]::ReadAllText($statusPath)

    if ($transportText.Contains('$transportWindowsPathBudget = 240') -and
        $transportText.Contains('sas-software-deployment-transport-link/v1') -and
        $statusText.Contains('preflight_link_valid = $preflightLinkValid')) {
        Assert-SasRepairParse -Text $transportText -Label $transportPath
        Assert-SasRepairParse -Text $statusText -Label $statusPath
        $classification = 'AUTOLOGON_S4U_PATH_BUDGET_RUNTIME_REPAIR_ALREADY_PRESENT'
    }
    else {
        if (-not $transportText.Contains('$transportWindowsPathBudget = 240')) {
            $budgetBlock = @'

# Protected-runtime field repair: compact nested transport evidence before Windows path overflow.
$transportWindowsPathBudget = 240
$transportOwnerLinkPath = $null
function Get-SasTransportProjectedArtifactPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CandidateOutputRoot)

    $resolved = [IO.Path]::GetFullPath($CandidateOutputRoot)
    $workflowRoot = Join-Path $resolved 'software-deployment-transport'
    $sampleRunId = 'software-deployment-transport-99999999-999999-ffffffff'
    $sampleRunRoot = Join-Path $workflowRoot $sampleRunId
    return (Join-Path (Join-Path $sampleRunRoot 'artifacts') 'software_deployment_transport_result.json')
}

if ($OutputRoot) {
    $requestedOutputRoot = [IO.Path]::GetFullPath($OutputRoot)
    Assert-SasLocalOutputRoot -OutputRoot $requestedOutputRoot -RepoRoot $repoRoot
    $projectedArtifactPath = Get-SasTransportProjectedArtifactPath -CandidateOutputRoot $requestedOutputRoot
    if ($projectedArtifactPath.Length -ge $transportWindowsPathBudget) {
        $ownerRoot = Split-Path -Parent $requestedOutputRoot
        $transportOwnerLinkPath = Join-Path $ownerRoot 'transport_preflight_link.json'
        if ($transportOwnerLinkPath.Length -ge $transportWindowsPathBudget) {
            throw "TRANSPORT_OWNER_LINK_PATH_BUDGET_BLOCKED: owner-side linkage still exceeds $transportWindowsPathBudget characters."
        }
        $compactOutputRoot = Join-Path $repoRoot 'runs'
        $compactProjectedArtifactPath = Get-SasTransportProjectedArtifactPath -CandidateOutputRoot $compactOutputRoot
        if ($compactProjectedArtifactPath.Length -ge $transportWindowsPathBudget) {
            throw "TRANSPORT_OUTPUT_ROOT_PATH_BUDGET_BLOCKED: canonical compact run root still exceeds $transportWindowsPathBudget characters."
        }
        Write-Warning "TRANSPORT_OUTPUT_ROOT_COMPACTED: requested transport run root would exceed the Windows path budget; using $compactOutputRoot."
        $OutputRoot = $compactOutputRoot
    }
}
'@
            $transportText = Insert-SasRepairAfterUniqueLiteral -Text $transportText `
                -Anchor 'Import-Module $runContextModulePath -Force' -Insertion $budgetBlock
        }

        if (-not $transportText.Contains('sas-software-deployment-transport-link/v1')) {
            $ownerLinkBlock = @'
if (-not [string]::IsNullOrWhiteSpace([string]$transportOwnerLinkPath)) {
    $ownerLinkParent = Split-Path -Parent $transportOwnerLinkPath
    if (-not (Test-Path -LiteralPath $ownerLinkParent -PathType Container)) {
        New-Item -ItemType Directory -Path $ownerLinkParent -Force | Out-Null
    }
    [pscustomobject][ordered]@{
        schema_version = 'sas-software-deployment-transport-link/v1'
        transport_run_root = $context.run_root
        result_path = $resultPath
        artifact_registry_path = $context.artifact_registry_path
        network_activity_performed = $networkActivity
        target_mutation_performed = $false
        created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $transportOwnerLinkPath -Encoding UTF8
}

'@
            $transportText = Insert-SasRepairBeforeUniqueLiteral -Text $transportText `
                -Anchor '$output = [pscustomobject]@{' -Insertion $ownerLinkBlock
        }

        if (-not $statusText.Contains('function Test-SasStatusPathUnderRoot {')) {
            $statusHelper = @'
function Test-SasStatusPathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $fullPath.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)
}

'@
            $statusText = Insert-SasRepairBeforeUniqueLiteral -Text $statusText `
                -Anchor '$allFiles = @(' -Insertion $statusHelper
        }

        if (-not $statusText.Contains('$preflightLinkFile =')) {
            $oldPreflight = '$preflightResult = $allFiles | Where-Object { $_.Name -eq ''software_deployment_transport_result.json'' } | Select-Object -First 1'
            $newPreflight = @'
$preflightResult = $allFiles | Where-Object { $_.Name -eq 'software_deployment_transport_result.json' } | Select-Object -First 1
$preflightLinkFile = $allFiles | Where-Object { $_.Name -eq 'transport_preflight_link.json' } | Select-Object -First 1
$preflightLinkValid = $false
$preflightResultPath = $(if ($preflightResult) { $preflightResult.FullName } else { $null })
if ($null -eq $preflightResult -and $null -ne $preflightLinkFile) {
    try {
        $link = Get-Content -LiteralPath $preflightLinkFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $linkedPath = [string]$link.result_path
        $approvedTransportRoot = Join-Path $repoRoot 'runs'
        if ([string]$link.schema_version -eq 'sas-software-deployment-transport-link/v1' -and
            -not [string]::IsNullOrWhiteSpace($linkedPath) -and
            [IO.Path]::GetFileName($linkedPath) -eq 'software_deployment_transport_result.json' -and
            (Test-SasStatusPathUnderRoot -Path $linkedPath -Root $approvedTransportRoot) -and
            (Test-Path -LiteralPath $linkedPath -PathType Leaf)) {
            $preflightLinkValid = $true
            $preflightResultPath = [IO.Path]::GetFullPath($linkedPath)
            $preflightResult = Get-Item -LiteralPath $preflightResultPath
        }
    }
    catch { }
}
'@
            $statusText = Replace-SasRepairUniqueLiteral -Text $statusText `
                -OldValue $oldPreflight -NewValue $newPreflight
        }

        if (-not $statusText.Contains('preflight_link_valid = $preflightLinkValid')) {
            $oldStatus = '    preflight_result_present = ($null -ne $preflightResult)'
            $newStatus = @'
    preflight_result_present = ($null -ne $preflightResult)
    preflight_result_path = $preflightResultPath
    preflight_link_present = ($null -ne $preflightLinkFile)
    preflight_link_valid = $preflightLinkValid
    preflight_link_path = $(if ($preflightLinkFile) { $preflightLinkFile.FullName } else { $null })
'@
            $statusText = Replace-SasRepairUniqueLiteral -Text $statusText `
                -OldValue $oldStatus -NewValue $newStatus
        }

        Assert-SasRepairParse -Text $transportText -Label $transportPath
        Assert-SasRepairParse -Text $statusText -Label $statusPath

        foreach ($marker in @(
            '$transportWindowsPathBudget = 240',
            'TRANSPORT_OUTPUT_ROOT_COMPACTED',
            'sas-software-deployment-transport-link/v1'
        )) {
            if (-not $transportText.Contains($marker)) { throw "Transport repair marker missing: $marker" }
        }
        foreach ($marker in @(
            'Test-SasStatusPathUnderRoot',
            'transport_preflight_link.json',
            'preflight_link_valid = $preflightLinkValid'
        )) {
            if (-not $statusText.Contains($marker)) { throw "Status repair marker missing: $marker" }
        }

        $utf8 = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($transportPath,$transportText,$utf8)
        [IO.File]::WriteAllText($statusPath,$statusText,$utf8)
    }
}
catch {
    Copy-Item -LiteralPath $transportBackup -Destination $transportPath -Force
    Copy-Item -LiteralPath $statusBackup -Destination $statusPath -Force
    throw "AUTOLOGON_S4U_PATH_BUDGET_RUNTIME_REPAIR_FAILED: originals restored. $($_.Exception.Message)"
}

$transportAfter = Get-SasRepairSha256 -Path $transportPath
$statusAfter = Get-SasRepairSha256 -Path $statusPath
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-path-budget-runtime-repair/v1'
    classification = $classification
    runtime_root = $RuntimeRoot
    evidence_root = $EvidenceRoot
    transport_path = $transportPath
    status_path = $statusPath
    transport_sha256_before = $transportBefore
    transport_sha256_after = $transportAfter
    status_sha256_before = $statusBefore
    status_sha256_after = $statusAfter
    powershell_parse_passed = $true
    git_performed = $false
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($PassThru) { return $result }
Write-Host $classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"
