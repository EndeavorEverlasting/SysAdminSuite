#Requires -Version 5.1
<#
.SYNOPSIS
    Explains the latest Northwell printer mapping proof without contacting or mutating a target.

.DESCRIPTION
    Reads existing Summary.json and Status.json evidence only. It distinguishes a proven
    SYSTEM/HKLM registration from a missing machine-wide registration, a remote-agent error,
    an identity mismatch, or an otherwise inconclusive proof. A printer that already exists
    for an interactive user is not promoted to SYSTEM-wide success unless the preserved HKLM
    evidence proves that all-users registration.

    This script performs no network probe, task operation, printer mutation, test page, or
    target contact. It is safe to use after a failed field transaction instead of remapping
    blindly.
#>

[CmdletBinding()]
param(
    [string]$EvidenceRoot,
    [string]$StateRoot,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SasStringArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    return @(
        @($Value) |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-SasStatusArray {
    param([Parameter(Mandatory)]$Status,[Parameter(Mandatory)][string]$Name)
    $property = $Status.PSObject.Properties[$Name]
    if ($null -eq $property) { return @() }
    return @(ConvertTo-SasStringArray -Value $property.Value)
}

function Get-SasStatusString {
    param([Parameter(Mandatory)]$Status,[Parameter(Mandatory)][string]$Name)
    $property = $Status.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Resolve-SasPrinterStateRoot {
    if (-not [string]::IsNullOrWhiteSpace($StateRoot)) {
        $candidate = [IO.Path]::GetFullPath($StateRoot)
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        throw "Printer state root does not exist: $candidate"
    }

    foreach ($base in @($env:SAS_RUNTIME_ROOT,'C:\SASAL')) {
        if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
        try { $candidate = Join-Path ([IO.Path]::GetFullPath([string]$base)) '.state\printer-bootstrap' } catch { continue }
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
    return $null
}

function Resolve-SasLatestPrinterEvidenceRoot {
    if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
        $explicit = [IO.Path]::GetFullPath($EvidenceRoot)
        if (-not (Test-Path -LiteralPath $explicit -PathType Container)) { throw "Printer evidence root does not exist: $explicit" }
        if (-not (Test-Path -LiteralPath (Join-Path $explicit 'Summary.json') -PathType Leaf)) { throw "Summary.json not found under printer evidence root: $explicit" }
        return $explicit
    }

    $pointerCandidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($base in @($env:SAS_RUNTIME_ROOT,'C:\SASAL')) {
        if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
        try { $fullBase = [IO.Path]::GetFullPath([string]$base) } catch { continue }
        $direct = Join-Path $fullBase 'mapping\Logs\LATEST-PATH.txt'
        if (-not $pointerCandidates.Contains($direct)) { [void]$pointerCandidates.Add($direct) }
    }

    $state = Resolve-SasPrinterStateRoot
    if (-not [string]::IsNullOrWhiteSpace([string]$state)) {
        foreach ($pointer in @(Get-ChildItem -LiteralPath $state -Filter 'LATEST-PATH.txt' -File -Recurse -ErrorAction SilentlyContinue)) {
            if (-not $pointerCandidates.Contains($pointer.FullName)) { [void]$pointerCandidates.Add($pointer.FullName) }
        }
    }

    $validPointerRoots = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pointer in $pointerCandidates) {
        if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) { continue }
        try {
            $value = ([string](Get-Content -LiteralPath $pointer -Raw -ErrorAction Stop)).Trim()
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $root = [IO.Path]::GetFullPath($value)
            $summary = Join-Path $root 'Summary.json'
            if (Test-Path -LiteralPath $summary -PathType Leaf) {
                $item = Get-Item -LiteralPath $summary -ErrorAction Stop
                $validPointerRoots.Add([pscustomobject]@{ Root=$root; LastWriteTimeUtc=$item.LastWriteTimeUtc })
            }
        }
        catch {}
    }
    if ($validPointerRoots.Count -gt 0) {
        return [string](($validPointerRoots.ToArray() | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).Root)
    }

    $summaryCandidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($base in @($env:SAS_RUNTIME_ROOT,'C:\SASAL',$state)) {
        if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
        try { $fullBase = [IO.Path]::GetFullPath([string]$base) } catch { continue }
        if (-not (Test-Path -LiteralPath $fullBase -PathType Container)) { continue }
        foreach ($summary in @(Get-ChildItem -LiteralPath $fullBase -Filter 'Summary.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($summary.FullName -notmatch '(?i)[\\/]mapping[\\/]Logs[\\/]|[\\/]printer-bootstrap[\\/]') { continue }
            $summaryCandidates.Add([pscustomobject]@{ Root=$summary.Directory.FullName; LastWriteTimeUtc=$summary.LastWriteTimeUtc })
        }
    }
    if ($summaryCandidates.Count -eq 0) { throw 'No existing Northwell printer mapping evidence was found. Run mapping before diagnosing it.' }
    return [string](($summaryCandidates.ToArray() | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).Root)
}

function Get-SasPrinterProofDiagnostic {
    param([Parameter(Mandatory)]$Status)

    $requested = @(Get-SasStatusArray -Status $Status -Name 'Requested')
    $before = @(Get-SasStatusArray -Status $Status -Name 'BeforeMachineWideUNC')
    $after = @(Get-SasStatusArray -Status $Status -Name 'MachineWideUNC')
    $already = @(Get-SasStatusArray -Status $Status -Name 'AlreadyDesiredPrinters')
    $missing = @(Get-SasStatusArray -Status $Status -Name 'Missing')
    $still = @(Get-SasStatusArray -Status $Status -Name 'StillPresent')
    $rawKeys = @(Get-SasStatusArray -Status $Status -Name 'RawConnectionKeys')
    $identity = Get-SasStatusString -Status $Status -Name 'Identity'
    $desired = Get-SasStatusString -Status $Status -Name 'DesiredState'
    $errorText = Get-SasStatusString -Status $Status -Name 'Error'
    $successProperty = $Status.PSObject.Properties['Success']
    $success = ($null -ne $successProperty -and [bool]$successProperty.Value)

    $normalizedRequested = @($requested | ForEach-Object { $_.ToLowerInvariant() })
    $normalizedAfter = @($after | ForEach-Object { $_.ToLowerInvariant() })
    $presentProof = ($normalizedRequested.Count -gt 0 -and @($normalizedRequested | Where-Object { $normalizedAfter -notcontains $_ }).Count -eq 0)
    $absentProof = ($normalizedRequested.Count -gt 0 -and @($normalizedRequested | Where-Object { $normalizedAfter -contains $_ }).Count -eq 0)

    $classification = 'MACHINE_WIDE_PROOF_INCONCLUSIVE'
    if (-not [string]::IsNullOrWhiteSpace($errorText)) { $classification = 'REMOTE_AGENT_ERROR' }
    elseif ($identity -notmatch 'SYSTEM$') { $classification = 'SYSTEM_IDENTITY_NOT_PROVEN' }
    elseif ($desired.Equals('Present',[System.StringComparison]::OrdinalIgnoreCase) -and $success -and $missing.Count -eq 0 -and $presentProof) { $classification = 'MACHINE_WIDE_REGISTRATION_PROVEN' }
    elseif ($desired.Equals('Absent',[System.StringComparison]::OrdinalIgnoreCase) -and $success -and $still.Count -eq 0 -and $absentProof) { $classification = 'MACHINE_WIDE_REMOVAL_PROVEN' }
    elseif ($missing.Count -gt 0) { $classification = 'MACHINE_WIDE_REGISTRATION_MISSING' }
    elseif ($still.Count -gt 0) { $classification = 'MACHINE_WIDE_REGISTRATION_STILL_PRESENT' }

    return [pscustomobject][ordered]@{
        classification = $classification
        computer = Get-SasStatusString -Status $Status -Name 'ComputerName'
        identity = $identity
        desired_state = $desired
        requested = $requested
        before_machine_wide = $before
        after_machine_wide = $after
        already_desired_machine_wide = $already
        missing_machine_wide = $missing
        still_present_machine_wide = $still
        raw_hklm_connection_keys = $rawKeys
        agent_error = $errorText
        target_contact_performed = $false
        target_mutation_performed = $false
        test_page_printed = $false
    }
}

$resolvedEvidenceRoot = Resolve-SasLatestPrinterEvidenceRoot
$summaryPath = Join-Path $resolvedEvidenceRoot 'Summary.json'
$summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$statusFiles = @(Get-ChildItem -LiteralPath $resolvedEvidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction Stop)
if ($statusFiles.Count -eq 0) { throw "No Status.json files were found under printer evidence root: $resolvedEvidenceRoot" }

$diagnostics = New-Object 'System.Collections.Generic.List[object]'
foreach ($statusFile in $statusFiles) {
    $status = Get-Content -LiteralPath $statusFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $diagnostics.Add((Get-SasPrinterProofDiagnostic -Status $status))
}

$failed = @($diagnostics.ToArray() | Where-Object { $_.classification -notin @('MACHINE_WIDE_REGISTRATION_PROVEN','MACHINE_WIDE_REMOVAL_PROVEN') })
$overall = if ($failed.Count -eq 0) { 'AUTHORITATIVE_MACHINE_WIDE_PROOF_PRESENT' } else { 'AUTHORITATIVE_MACHINE_WIDE_PROOF_NOT_PRESENT' }

Write-Host ''
Write-Host '=== NORTHWELL PRINTER EVIDENCE DIAGNOSTIC ===' -ForegroundColor Cyan
Write-Host "DIAGNOSTIC_STATUS=COMPLETED"
Write-Host "MAPPING_PROOF=$overall"
Write-Host "EVIDENCE_ROOT=$resolvedEvidenceRoot"
Write-Host 'TARGET_CONTACT_PERFORMED=False'
Write-Host 'TARGET_MUTATION_PERFORMED=False'
Write-Host 'TEST_PAGE_PRINTED=False'
foreach ($diagnostic in $diagnostics) {
    Write-Host ''
    Write-Host ("CLASSIFICATION={0}" -f $diagnostic.classification) -ForegroundColor $(if ($diagnostic.classification -match '_PROVEN$') { 'Green' } else { 'Yellow' })
    Write-Host ("COMPUTER={0}" -f $diagnostic.computer)
    Write-Host ("IDENTITY={0}" -f $diagnostic.identity)
    Write-Host ("DESIRED_STATE={0}" -f $diagnostic.desired_state)
    Write-Host ("REQUESTED={0}" -f ($diagnostic.requested -join ';'))
    Write-Host ("BEFORE_MACHINE_WIDE={0}" -f ($diagnostic.before_machine_wide -join ';'))
    Write-Host ("AFTER_MACHINE_WIDE={0}" -f ($diagnostic.after_machine_wide -join ';'))
    Write-Host ("ALREADY_DESIRED_MACHINE_WIDE={0}" -f ($diagnostic.already_desired_machine_wide -join ';'))
    Write-Host ("MISSING_MACHINE_WIDE={0}" -f ($diagnostic.missing_machine_wide -join ';'))
    Write-Host ("RAW_HKLM_KEYS={0}" -f ($diagnostic.raw_hklm_connection_keys -join ';'))
    if (-not [string]::IsNullOrWhiteSpace([string]$diagnostic.agent_error)) { Write-Host ("AGENT_ERROR={0}" -f $diagnostic.agent_error) -ForegroundColor Yellow }
}

if ($PassThru) {
    [pscustomobject][ordered]@{
        schema_version = 'sas-northwell-printer-evidence-diagnostic/v1'
        diagnostic_status = 'COMPLETED'
        mapping_proof = $overall
        evidence_root = $resolvedEvidenceRoot
        summary_success = [bool]$summary.Success
        diagnostics = $diagnostics.ToArray()
        target_contact_performed = $false
        target_mutation_performed = $false
        test_page_printed = $false
    }
}
