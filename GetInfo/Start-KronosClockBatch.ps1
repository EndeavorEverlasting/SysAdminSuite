#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoOpen)

$ErrorActionPreference = 'Stop'

try {
    if (-not $env:LOCALAPPDATA) { throw 'The Windows user profile is unavailable.' }
    $workspace = Join-Path $env:LOCALAPPDATA 'SysAdminSuite/KronosClock'
    $collector = Join-Path $PSScriptRoot 'Get-KronosClockInfo.ps1'
    Write-Host 'SysAdminSuite | Kronos Clock Batch'
    Write-Host "Default private input folder: $workspace"
    $evidenceFolder = (Read-Host 'Approved site evidence folder [Enter for default]').Trim().Trim('"')
    if (-not $evidenceFolder) { $evidenceFolder = $workspace }
    $evidenceFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($evidenceFolder)
    $inputValue = (Read-Host 'Assignment CSV path or one identifier (for example SerialNumber=SERIAL)').Trim().Trim('"')
    if (-not $inputValue) { throw 'Provide a CSV path or one typed identifier.' }
    $argsForBatch = @{}
    $singleRequest = $null
    try {
        if ($inputValue -match '^(IPAddress|HostName|MACAddress|SerialNumber|DeviceID|DeviceName|SubnetMask|ScopeId|DefaultGateway)=(.+)$') {
            $field = $Matches[1]
            $value = $Matches[2]
            $singleRequest = [IO.Path]::GetTempFileName()
            [pscustomobject]@{ $field = $value } | Export-Csv -LiteralPath $singleRequest -NoTypeInformation -Encoding UTF8
            $argsForBatch.RequestPath = $singleRequest
        } else {
            if (-not (Test-Path -LiteralPath $inputValue -PathType Leaf)) { throw 'Could not read the assignment CSV.' }
            $argsForBatch.RequestPath = $inputValue
        }

        foreach ($file in @{
            ClockInventoryPath = 'ClockInventory.csv'
            LeasePath = 'DhcpLeases.csv'
            ScopePath = 'DhcpScopes.csv'
            ReservationPath = 'DhcpReservations.csv'
        }.GetEnumerator()) {
            $path = Join-Path $evidenceFolder $file.Value
            if (Test-Path -LiteralPath $path -PathType Leaf) { $argsForBatch[$file.Key] = $path }
        }

        $choice = (Read-Host 'Press Enter for local evidence only or type LIVE for an approved Northwell reachability check').Trim()
        if ($choice -eq 'LIVE') {
            if (-not $argsForBatch.ScopePath) { throw 'Live mode requires DhcpScopes.csv from the approved site.' }
            $argsForBatch.Live = $true
            $argsForBatch.DnsDomain = (Read-Host 'Approved site DNS suffix [Enter to skip DNS]').Trim()
        } elseif ($choice) {
            throw 'Choose Enter or LIVE.'
        }
        $null = & $collector @argsForBatch -OpenReport:(-not $NoOpen)
    } finally {
        if ($singleRequest) { Remove-Item -LiteralPath $singleRequest -ErrorAction Ignore }
    }
    exit 0
} catch {
    Write-Host "BLOCKED: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
