# SysAdminSuite - Cybernet / Neuron survey resolver
# Accepts typed arguments plus TXT, CSV, and JSON target files.
# Safe default: read-only WMI/CIM collection. No target modification.

[CmdletBinding()]
param(
    [string[]]$Targets = @(),
    [string[]]$TargetFile = @(),
    [string[]]$CsvPath = @(),
    [string[]]$JsonPath = @(),
    [string[]]$TxtPath = @(),
    [string[]]$InventoryPath = @(),
    [ValidateSet('Cybernet','Neuron','Workstation','Unknown')]
    [string]$DeviceType = 'Unknown',
    [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\DeviceSurvey\DeviceSurvey_Output.csv'),
    [int]$Throttle = 15,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Normalize-MacAddress {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $hex = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($hex.Length -ne 12) { return $Value.Trim().ToUpperInvariant() }
    return (($hex -split '(.{2})' | Where-Object { $_ }) -join ':')
}

function Normalize-Serial {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ($Value.Trim() -replace '\s+', '').ToUpperInvariant()
}

function Normalize-HostName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().ToUpperInvariant()
}

function Get-IdentifierType {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Unknown' }
    $trimmed = $Value.Trim()
    $macHex = ($trimmed -replace '[^0-9A-Fa-f]', '')
    if ($macHex.Length -eq 12 -and $trimmed -match '[:\-\.]|^[0-9A-Fa-f]{12}$') { return 'MAC' }
    if ($trimmed -match '^[A-Za-z]{2,6}\d{2,}[A-Za-z0-9\-]*$' -or $trimmed -match '^[A-Za-z0-9]+[-_][A-Za-z0-9]+') { return 'HostName' }
    return 'Serial'
}

function New-TargetRecord {
    param(
        [string]$Identifier,
        [string]$HostName = '',
        [string]$Serial = '',
        [string]$MACAddress = '',
        [string]$DeviceType = $script:RequestedDeviceType,
        [string]$Source = 'Typed'
    )

    $identifierText = if ($Identifier) { $Identifier.Trim() } elseif ($HostName) { $HostName.Trim() } elseif ($Serial) { $Serial.Trim() } elseif ($MACAddress) { $MACAddress.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($identifierText)) { return $null }

    $detectedType = Get-IdentifierType -Value $identifierText
    if (-not $HostName -and $detectedType -eq 'HostName') { $HostName = $identifierText }
    if (-not $Serial -and $detectedType -eq 'Serial') { $Serial = $identifierText }
    if (-not $MACAddress -and $detectedType -eq 'MAC') { $MACAddress = $identifierText }

    [pscustomobject]@{
        Identifier       = $identifierText
        IdentifierType   = $detectedType
        DeviceType       = if ($DeviceType) { $DeviceType } else { 'Unknown' }
        HostName         = Normalize-HostName $HostName
        Serial           = Normalize-Serial $Serial
        MACAddress       = Normalize-MacAddress $MACAddress
        Source           = $Source
    }
}

function Import-TextTargets {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Target text file not found: $Path" }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        foreach ($piece in ($line -split '[,;\t]')) {
            $value = $piece.Trim()
            if ($value) { New-TargetRecord -Identifier $value -Source "TXT:$Path" }
        }
    }
}

function Import-CsvTargets {
    param([string]$Path, [string]$SourcePrefix = 'CSV')
    if (-not (Test-Path -LiteralPath $Path)) { throw "Target CSV file not found: $Path" }
    $rows = @(Import-Csv -LiteralPath $Path)
    foreach ($row in $rows) {
        $props = $row.PSObject.Properties
        $host = @('HostName','Hostname','Host','ComputerName','Computer','Name','Target') | ForEach-Object { ($props[$_]).Value } | Where-Object { $_ } | Select-Object -First 1
        $serial = @('Serial','SerialNumber','ServiceTag','AssetSerial') | ForEach-Object { ($props[$_]).Value } | Where-Object { $_ } | Select-Object -First 1
        $mac = @('MACAddress','MacAddress','MAC','Mac','EthernetMAC','WifiMAC') | ForEach-Object { ($props[$_]).Value } | Where-Object { $_ } | Select-Object -First 1
        $id = @('Identifier','Target','KnownIdentifier','LookupValue') | ForEach-Object { ($props[$_]).Value } | Where-Object { $_ } | Select-Object -First 1
        $type = @('DeviceType','Type','DeviceClass') | ForEach-Object { ($props[$_]).Value } | Where-Object { $_ } | Select-Object -First 1
        if (-not $type) { $type = $script:RequestedDeviceType }
        New-TargetRecord -Identifier $id -HostName $host -Serial $serial -MACAddress $mac -DeviceType $type -Source "${SourcePrefix}:$Path"
    }
}

function Import-JsonTargets {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Target JSON file not found: $Path" }
    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $items = if ($json.targets) { $json.targets } else { $json }
    foreach ($item in @($items)) {
        if ($item -is [string]) {
            New-TargetRecord -Identifier $item -Source "JSON:$Path"
            continue
        }
        $host = $item.HostName; if (-not $host) { $host = $item.hostname }; if (-not $host) { $host = $item.host }; if (-not $host) { $host = $item.ComputerName }
        $serial = $item.Serial; if (-not $serial) { $serial = $item.SerialNumber }; if (-not $serial) { $serial = $item.ServiceTag }
        $mac = $item.MACAddress; if (-not $mac) { $mac = $item.MAC }; if (-not $mac) { $mac = $item.mac }
        $id = $item.Identifier; if (-not $id) { $id = $item.Target }; if (-not $id) { $id = $item.KnownIdentifier }
        $type = $item.DeviceType; if (-not $type) { $type = $item.Type }; if (-not $type) { $type = $script:RequestedDeviceType }
        New-TargetRecord -Identifier $id -HostName $host -Serial $serial -MACAddress $mac -DeviceType $type -Source "JSON:$Path"
    }
}

function Resolve-TargetsFromInventory {
    param([object[]]$TargetRows, [string[]]$InventoryPaths)
    if (-not $InventoryPaths -or $InventoryPaths.Count -eq 0) { return $TargetRows }

    $inventoryRows = @()
    foreach ($path in $InventoryPaths) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Inventory CSV not found: $path" }
        $inventoryRows += Import-CsvTargets -Path $path -SourcePrefix 'Inventory'
    }

    foreach ($target in $TargetRows) {
        if ($target.HostName) { $target; continue }
        $match = $null
        if ($target.Serial) {
            $match = $inventoryRows | Where-Object { $_.Serial -and $_.Serial -eq $target.Serial } | Select-Object -First 1
        }
        if (-not $match -and $target.MACAddress) {
            $match = $inventoryRows | Where-Object { $_.MACAddress -and $_.MACAddress -eq $target.MACAddress } | Select-Object -First 1
        }
        if (-not $match -and $target.IdentifierType -eq 'HostName') {
            $match = $inventoryRows | Where-Object { $_.HostName -and $_.HostName -eq (Normalize-HostName $target.Identifier) } | Select-Object -First 1
        }

        if ($match) {
            [pscustomobject]@{
                Identifier       = $target.Identifier
                IdentifierType   = $target.IdentifierType
                DeviceType       = if ($target.DeviceType -ne 'Unknown') { $target.DeviceType } else { $match.DeviceType }
                HostName         = $match.HostName
                Serial           = if ($target.Serial) { $target.Serial } else { $match.Serial }
                MACAddress       = if ($target.MACAddress) { $target.MACAddress } else { $match.MACAddress }
                Source           = "$($target.Source);ResolvedFromInventory"
            }
        } else {
            $target
        }
    }
}

function Get-RemoteDeviceSurvey {
    param([object]$Target)

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if (-not $Target.HostName) {
        return [pscustomobject]@{
            Timestamp          = $timestamp
            DeviceType         = $Target.DeviceType
            InputIdentifier    = $Target.Identifier
            InputType          = $Target.IdentifierType
            QueryHost          = ''
            ResolvedHostName   = ''
            BIOSSerial         = ''
            Manufacturer       = ''
            Model              = ''
            IPAddress          = ''
            MACAddress         = $Target.MACAddress
            KnownSerial        = $Target.Serial
            KnownMACAddress    = $Target.MACAddress
            HostnameMatched    = $false
            SerialMatched      = $false
            MACMatched         = $false
            Status             = 'Needs HostName or Inventory Match'
            ErrorMessage       = 'Serial/MAC-only targets require InventoryPath mapping or a hostname-capable identifier.'
            Source             = $Target.Source
        }
    }

    $computer = $Target.HostName
    $isLocal = $computer -eq $env:COMPUTERNAME -or $computer -eq 'LOCALHOST' -or $computer -eq '127.0.0.1' -or $computer -eq '.'
    $reachable = if ($isLocal) { $true } else { Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue }

    if (-not $reachable) {
        return [pscustomobject]@{
            Timestamp          = $timestamp
            DeviceType         = $Target.DeviceType
            InputIdentifier    = $Target.Identifier
            InputType          = $Target.IdentifierType
            QueryHost          = $computer
            ResolvedHostName   = ''
            BIOSSerial         = ''
            Manufacturer       = ''
            Model              = ''
            IPAddress          = ''
            MACAddress         = ''
            KnownSerial        = $Target.Serial
            KnownMACAddress    = $Target.MACAddress
            HostnameMatched    = $false
            SerialMatched      = $false
            MACMatched         = $false
            Status             = 'Offline'
            ErrorMessage       = ''
            Source             = $Target.Source
        }
    }

    try {
        $cs = if ($isLocal) { Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop } else { Get-WmiObject -Class Win32_ComputerSystem -ComputerName $computer -ErrorAction Stop }
        $bios = if ($isLocal) { Get-WmiObject -Class Win32_BIOS -ErrorAction Stop } else { Get-WmiObject -Class Win32_BIOS -ComputerName $computer -ErrorAction Stop }
        $nics = if ($isLocal) { Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue } else { Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $computer -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue }

        $ipv4s = @()
        $macs = @()
        foreach ($nic in @($nics)) {
            $ipv4 = @($nic.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' }) | Select-Object -First 1
            if ($ipv4) { $ipv4s += $ipv4 }
            if ($nic.MACAddress) { $macs += (Normalize-MacAddress $nic.MACAddress) }
        }

        $biosSerial = Normalize-Serial $bios.SerialNumber
        $knownMac = Normalize-MacAddress $Target.MACAddress
        $knownSerial = Normalize-Serial $Target.Serial
        $macMatched = $false
        if ($knownMac) { $macMatched = @($macs | Where-Object { $_ -eq $knownMac }).Count -gt 0 }

        [pscustomobject]@{
            Timestamp          = $timestamp
            DeviceType         = $Target.DeviceType
            InputIdentifier    = $Target.Identifier
            InputType          = $Target.IdentifierType
            QueryHost          = $computer
            ResolvedHostName   = Normalize-HostName $cs.Name
            BIOSSerial         = $biosSerial
            Manufacturer       = $cs.Manufacturer
            Model              = $cs.Model
            IPAddress          = (($ipv4s | Sort-Object -Unique) -join ';')
            MACAddress         = (($macs | Sort-Object -Unique) -join ';')
            KnownSerial        = $knownSerial
            KnownMACAddress    = $knownMac
            HostnameMatched    = ((Normalize-HostName $computer) -eq (Normalize-HostName $cs.Name))
            SerialMatched      = if ($knownSerial) { $knownSerial -eq $biosSerial } else { $false }
            MACMatched         = $macMatched
            Status             = 'OK'
            ErrorMessage       = ''
            Source             = $Target.Source
        }
    }
    catch {
        [pscustomobject]@{
            Timestamp          = $timestamp
            DeviceType         = $Target.DeviceType
            InputIdentifier    = $Target.Identifier
            InputType          = $Target.IdentifierType
            QueryHost          = $computer
            ResolvedHostName   = ''
            BIOSSerial         = ''
            Manufacturer       = ''
            Model              = ''
            IPAddress          = ''
            MACAddress         = ''
            KnownSerial        = $Target.Serial
            KnownMACAddress    = $Target.MACAddress
            HostnameMatched    = $false
            SerialMatched      = $false
            MACMatched         = $false
            Status             = 'Query Failed'
            ErrorMessage       = $_.Exception.Message
            Source             = $Target.Source
        }
    }
}

$script:RequestedDeviceType = $DeviceType

$allTargets = @()
foreach ($target in $Targets) { $allTargets += New-TargetRecord -Identifier $target -Source 'Typed' }
foreach ($path in ($TargetFile + $TxtPath)) { $allTargets += Import-TextTargets -Path $path }
foreach ($path in $CsvPath) { $allTargets += Import-CsvTargets -Path $path }
foreach ($path in $JsonPath) { $allTargets += Import-JsonTargets -Path $path }

$allTargets = @($allTargets | Where-Object { $_ -ne $null })
if (-not $allTargets -or $allTargets.Count -eq 0) {
    throw 'No targets provided. Use -Targets, -TxtPath, -CsvPath, -JsonPath, or -TargetFile.'
}

$resolvedTargets = @(Resolve-TargetsFromInventory -TargetRows $allTargets -InventoryPaths $InventoryPath)
$dedupedTargets = @($resolvedTargets | Sort-Object HostName,Serial,MACAddress,Identifier -Unique)

$jobs = @()
$directResults = @()
foreach ($target in $dedupedTargets) {
    if (-not $target.HostName) {
        $directResults += Get-RemoteDeviceSurvey -Target $target
        continue
    }

    while (@($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $Throttle) {
        Wait-Job -Any ($jobs | Where-Object { $_.State -eq 'Running' }) | Out-Null
    }

    $jobs += Start-Job -Name "Survey_$($target.HostName)" -ScriptBlock ${function:Get-RemoteDeviceSurvey} -ArgumentList $target
}

if ($jobs.Count -gt 0) { Wait-Job -Job $jobs | Out-Null }
$jobResults = if ($jobs.Count -gt 0) { $jobs | Receive-Job } else { @() }
if ($jobs.Count -gt 0) { $jobs | Remove-Job -Force | Out-Null }

$results = @($directResults + $jobResults) | Sort-Object DeviceType, QueryHost, InputIdentifier
$dir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($dir)) { $dir = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

$suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $htmlPath = [IO.Path]::ChangeExtension($OutputPath, '.html')
    $subtitle = "$($results.Count) target(s), $(@($results | Where-Object Status -eq 'OK').Count) OK"
    $results |
        Select-Object DeviceType,InputIdentifier,InputType,QueryHost,ResolvedHostName,BIOSSerial,IPAddress,MACAddress,SerialMatched,MACMatched,Status,ErrorMessage |
        ConvertTo-Html -Fragment -PreContent '<h2>Cybernet / Neuron Device Survey</h2>' |
        ConvertTo-SuiteHtml -Title 'Device Survey' -Subtitle $subtitle -OutputPath $htmlPath
}

Write-Host "Done. Output saved to $OutputPath" -ForegroundColor Green
if ($PassThru) { $results }
