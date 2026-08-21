#Requires -Version 5.1
<#
.SYNOPSIS
Collect a comparison-ready read-only hardware profile from explicit Windows workstation targets.

.DESCRIPTION
Uses the caller's current Windows authorization and read-only WMI queries to collect the same
hardware identity fields needed to compare candidate Tangent workstations with a separately proven
Cybernet reference. It does not select a Cybernet profile, install software, change configuration,
create tasks, write the remote registry, or reboot a target.

Live evidence is written only below survey/output and must not be committed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateCount(1,25)]
    [string[]]$ComputerName,

    [ValidateNotNullOrEmpty()]
    [string]$CandidateLabel = 'UnclassifiedCandidate',

    [string]$OutputRoot,

    [switch]$SkipNetworkGate
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\workstation_profile_probe'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$localNames = @('.', 'localhost', $env:COMPUTERNAME) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }
if ($SkipNetworkGate) {
    foreach ($target in $ComputerName) {
        if ($localNames -notcontains $target.Trim().ToLowerInvariant()) {
            throw '-SkipNetworkGate is restricted to local fixture targets.'
        }
    }
}
else {
    $networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
    if (-not (Test-Path -LiteralPath $networkGate -PathType Leaf)) {
        throw "Missing Northwell network gate: $networkGate"
    }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate -Purpose 'read-only workstation hardware profile probe' -NonInteractive
    $networkCode = [int]$global:LASTEXITCODE
    if ($networkCode -ne 0) {
        throw "Approved Northwell network posture is required before target contact. Exit code: $networkCode"
    }
}

function Convert-SasMacAddress {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return $Value.Trim().ToUpperInvariant().Replace('-', ':')
}

function Convert-SasWmiDate {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { return [Management.ManagementDateTimeConverter]::ToDateTime($Value).ToUniversalTime().ToString('o') }
    catch { return $null }
}

function Get-SasWmiFirst {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Class
    )
    return Get-WmiObject -ComputerName $Target -Class $Class -ErrorAction Stop | Select-Object -First 1
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($rawTarget in $ComputerName) {
    $target = $rawTarget.Trim()
    if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$' -and $target -ne '.') {
        throw "Invalid explicit target name: $target"
    }

    Write-Host "Read-only workstation profile probe: $target" -ForegroundColor Cyan
    $row = [ordered]@{
        SchemaVersion = 'sas-readonly-workstation-profile/v1'
        GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
        CandidateLabel = $CandidateLabel
        RequestedTarget = $target
        ObservedHostName = $null
        Manufacturer = $null
        Model = $null
        ProductVendor = $null
        ProductName = $null
        ProductID = $null
        BIOSSerial = $null
        BIOSVersion = $null
        BoardManufacturer = $null
        BoardProduct = $null
        BoardSerial = $null
        OSCaption = $null
        OSVersion = $null
        OSBuild = $null
        OSArchitecture = $null
        LastBootUtc = $null
        ProcessorName = $null
        MemoryGB = $null
        COMPorts = $null
        MACs = $null
        ProbeStatus = 'QueryFailed'
        IdentityEvidence = 'SerialAndModelRequiredForHardwareComparison'
        ProfileSelection = 'NONE_READ_ONLY_DISCOVERY'
        TargetMutationPerformed = $false
        Notes = $null
    }

    try {
        $computer = Get-SasWmiFirst -Target $target -Class 'Win32_ComputerSystem'
        $product = Get-SasWmiFirst -Target $target -Class 'Win32_ComputerSystemProduct'
        $bios = Get-SasWmiFirst -Target $target -Class 'Win32_BIOS'
        $board = Get-SasWmiFirst -Target $target -Class 'Win32_BaseBoard'
        $os = Get-SasWmiFirst -Target $target -Class 'Win32_OperatingSystem'
        $cpu = Get-SasWmiFirst -Target $target -Class 'Win32_Processor'
        $serialPorts = @(Get-WmiObject -ComputerName $target -Class Win32_SerialPort -ErrorAction SilentlyContinue)
        $nics = @(Get-WmiObject -ComputerName $target -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction SilentlyContinue)

        $row.ObservedHostName = [string]$computer.Name
        $row.Manufacturer = [string]$computer.Manufacturer
        $row.Model = [string]$computer.Model
        $row.ProductVendor = [string]$product.Vendor
        $row.ProductName = [string]$product.Name
        $row.ProductID = [string]$product.IdentifyingNumber
        $row.BIOSSerial = [string]$bios.SerialNumber
        $row.BIOSVersion = [string]$bios.SMBIOSBIOSVersion
        $row.BoardManufacturer = [string]$board.Manufacturer
        $row.BoardProduct = [string]$board.Product
        $row.BoardSerial = [string]$board.SerialNumber
        $row.OSCaption = [string]$os.Caption
        $row.OSVersion = [string]$os.Version
        $row.OSBuild = [string]$os.BuildNumber
        $row.OSArchitecture = [string]$os.OSArchitecture
        $row.LastBootUtc = Convert-SasWmiDate -Value ([string]$os.LastBootUpTime)
        $row.ProcessorName = [string]$cpu.Name
        if ([double]$computer.TotalPhysicalMemory -gt 0) {
            $row.MemoryGB = [math]::Round(([double]$computer.TotalPhysicalMemory / 1GB), 2)
        }
        $row.COMPorts = (@($serialPorts | ForEach-Object { [string]$_.DeviceID } | Where-Object { $_ } | Sort-Object -Unique) -join ';')
        $row.MACs = (@($nics | ForEach-Object { Convert-SasMacAddress -Value ([string]$_.MACAddress) } | Where-Object { $_ } | Sort-Object -Unique) -join ';')

        if ([string]::IsNullOrWhiteSpace([string]$row.Model) -or [string]::IsNullOrWhiteSpace([string]$row.BIOSSerial)) {
            $row.ProbeStatus = 'IdentityIncomplete'
            $row.Notes = 'Read-only query succeeded, but model and/or BIOS serial is missing; do not classify hardware.'
        }
        else {
            $row.ProbeStatus = 'ComparisonReady'
            $row.Notes = 'Observed model + BIOS serial are available for comparison with a separately approved hardware reference.'
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($message.Length -gt 240) { $message = $message.Substring(0,240) }
        $row.Notes = $message
    }

    $result = [pscustomobject]$row
    [void]$results.Add($result)
    $result | Format-List RequestedTarget,ObservedHostName,Manufacturer,Model,BIOSSerial,OSCaption,OSBuild,ProcessorName,MemoryGB,COMPorts,MACs,ProbeStatus,ProfileSelection | Out-Host
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$csvPath = Join-Path $OutputRoot "workstation_profile_$stamp.csv"
$jsonPath = Join-Path $OutputRoot "workstation_profile_$stamp.json"
@($results) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
@($results) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host "Comparison-ready CSV: $csvPath" -ForegroundColor Green
Write-Host "Structured evidence: $jsonPath" -ForegroundColor Green
Write-Host 'No deployment profile was selected and no target mutation was performed.' -ForegroundColor Green
Write-Host 'To compare Tangent and Cybernet hardware, run this same read-only probe against the explicit Tangent candidates and a separately proven Cybernet reference host.' -ForegroundColor Cyan

if (@($results | Where-Object { $_.ProbeStatus -eq 'QueryFailed' }).Count -gt 0) { exit 20 }
if (@($results | Where-Object { $_.ProbeStatus -eq 'IdentityIncomplete' }).Count -gt 0) { exit 21 }
exit 0
