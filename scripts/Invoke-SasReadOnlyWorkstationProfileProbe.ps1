#Requires -Version 5.1
<#
.SYNOPSIS
Collect a comparison-ready read-only hardware profile from explicit Windows workstation targets.

.DESCRIPTION
Uses the caller's current Windows authorization and bounded read-only WMI queries to collect the
same hardware identity fields needed to compare candidate Tangent workstations with a separately
proven Cybernet reference. It does not select a Cybernet profile, install software, change
configuration, create tasks, write the remote registry, or reboot a target.

Live evidence defaults to the operator-local SysAdminSuite evidence root outside the repository.
#>

[CmdletBinding(DefaultParameterSetName = 'ComputerNames')]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ComputerNames')]
    [ValidateCount(1,25)]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'TargetsCsv')]
    [ValidateNotNullOrEmpty()]
    [string]$TargetsCsv,

    [ValidateNotNullOrEmpty()]
    [string]$CandidateLabel = 'UnclassifiedCandidate',

    [ValidateRange(3,60)]
    [int]$QueryTimeoutSeconds = 12,

    [string]$OutputRoot,

    [switch]$SkipNetworkGate
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Evidence\WorkstationProfile'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$targetList = if ($PSCmdlet.ParameterSetName -eq 'TargetsCsv') {
    @($TargetsCsv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
else {
    @($ComputerName | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($targetList.Count -lt 1 -or $targetList.Count -gt 25) {
    throw 'Provide between 1 and 25 explicit workstation targets.'
}
foreach ($target in $targetList) {
    if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$' -and $target -ne '.') {
        throw "Invalid explicit target name: $target"
    }
}

$localNames = @('.', 'localhost', $env:COMPUTERNAME) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }
if ($SkipNetworkGate) {
    foreach ($target in $targetList) {
        if ($localNames -notcontains $target.ToLowerInvariant()) {
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
    try { return [System.Management.ManagementDateTimeConverter]::ToDateTime($Value).ToUniversalTime().ToString('o') }
    catch { return $null }
}

function Invoke-SasReadOnlyWmiQuery {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $scopePath = "\\$Target\root\cimv2"
    $connection = New-Object System.Management.ConnectionOptions
    $connection.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $scope = New-Object System.Management.ManagementScope($scopePath, $connection)
    $scope.Connect()

    $objectQuery = New-Object System.Management.ObjectQuery($Query)
    $enumeration = New-Object System.Management.EnumerationOptions
    $enumeration.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $enumeration.ReturnImmediately = $true
    $searcher = New-Object System.Management.ManagementObjectSearcher($scope, $objectQuery, $enumeration)
    try {
        return @($searcher.Get())
    }
    finally {
        if ($searcher) { $searcher.Dispose() }
    }
}

function Get-SasFirstWmiResult {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    return Invoke-SasReadOnlyWmiQuery -Target $Target -Query $Query -TimeoutSeconds $TimeoutSeconds | Select-Object -First 1
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($target in $targetList) {
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
        QueryTimeoutSeconds = $QueryTimeoutSeconds
        Notes = $null
    }

    try {
        $computer = Get-SasFirstWmiResult -Target $target -Query 'SELECT Name,Manufacturer,Model,TotalPhysicalMemory FROM Win32_ComputerSystem' -TimeoutSeconds $QueryTimeoutSeconds
        $product = Get-SasFirstWmiResult -Target $target -Query 'SELECT Vendor,Name,IdentifyingNumber FROM Win32_ComputerSystemProduct' -TimeoutSeconds $QueryTimeoutSeconds
        $bios = Get-SasFirstWmiResult -Target $target -Query 'SELECT SerialNumber,SMBIOSBIOSVersion FROM Win32_BIOS' -TimeoutSeconds $QueryTimeoutSeconds
        $board = Get-SasFirstWmiResult -Target $target -Query 'SELECT Manufacturer,Product,SerialNumber FROM Win32_BaseBoard' -TimeoutSeconds $QueryTimeoutSeconds
        $os = Get-SasFirstWmiResult -Target $target -Query 'SELECT Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime FROM Win32_OperatingSystem' -TimeoutSeconds $QueryTimeoutSeconds
        $cpu = Get-SasFirstWmiResult -Target $target -Query 'SELECT Name FROM Win32_Processor' -TimeoutSeconds $QueryTimeoutSeconds
        $serialPorts = @(Invoke-SasReadOnlyWmiQuery -Target $target -Query 'SELECT DeviceID FROM Win32_SerialPort' -TimeoutSeconds $QueryTimeoutSeconds)
        $nics = @(Invoke-SasReadOnlyWmiQuery -Target $target -Query 'SELECT MACAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE' -TimeoutSeconds $QueryTimeoutSeconds)

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
        $row.Notes = "Bounded read-only WMI query failed: $message"
    }

    $result = [pscustomobject]$row
    [void]$results.Add($result)
    $result | Format-List RequestedTarget,ObservedHostName,Manufacturer,Model,BIOSSerial,OSCaption,OSBuild,ProcessorName,MemoryGB,COMPorts,MACs,ProbeStatus,ProfileSelection | Out-Host
}

# Windows PowerShell 5.1 can throw ArgumentException when a generic List[object]
# is passed directly through some serialization cmdlets. Materialize ordinary
# pipeline objects first so CSV/JSON evidence remains PS5.1-safe.
$resultArray = @($results | ForEach-Object { $_ })
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$csvPath = Join-Path $OutputRoot "workstation_profile_$stamp.csv"
$jsonPath = Join-Path $OutputRoot "workstation_profile_$stamp.json"
$resultArray | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$resultArray | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host "Comparison-ready CSV: $csvPath" -ForegroundColor Green
Write-Host "Structured evidence: $jsonPath" -ForegroundColor Green
Write-Host 'No deployment profile was selected and no target mutation was performed.' -ForegroundColor Green
Write-Host 'To compare Tangent and Cybernet hardware, run this same read-only probe against the explicit Tangent candidates and a separately proven Cybernet reference host.' -ForegroundColor Cyan

if (@($resultArray | Where-Object { $_.ProbeStatus -eq 'QueryFailed' }).Count -gt 0) { exit 20 }
if (@($resultArray | Where-Object { $_.ProbeStatus -eq 'IdentityIncomplete' }).Count -gt 0) { exit 21 }
exit 0
