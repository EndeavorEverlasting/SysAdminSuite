<#
.SYNOPSIS
    Interactive technician front-end for reversible Northwell printer management.
#>

[CmdletBinding()]
param(
    [ValidateSet('Map','Unmap')][string]$Action = 'Map',
    [string[]]$ComputerName,
    [string[]]$Printer,
    [string]$PrintServer,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$localDefaultsPath = Join-Path $repoRoot 'Config\northwell-printer-defaults.local.json'

function Split-SasFieldList {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Label)
    $items = @($Value -split '\s*[,;\r\n]+\s*' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) { throw "$Label cannot be blank." }
    return $items
}

function Get-SasNorthwellPrinterLocalDefaults {
    if (-not (Test-Path -LiteralPath $localDefaultsPath -PathType Leaf)) { return $null }
    try { $data = Get-Content -LiteralPath $localDefaultsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Local Northwell printer defaults are malformed: $localDefaultsPath. $($_.Exception.Message)" }
    $server = [string]$data.PrintServer
    $queue = [string]$data.QueueName
    if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($queue)) {
        throw "Local Northwell printer defaults must contain nonblank PrintServer and QueueName values: $localDefaultsPath"
    }
    if ($server -match '(?i)REPLACE-WITH|EXAMPLE' -or $queue -match '(?i)REPLACE-WITH|EXAMPLE') { return $null }
    return [pscustomobject]@{ PrintServer = $server.Trim(); QueueName = $queue.Trim() }
}

function Read-SasNorthwellPrinterSets {
    param([AllowNull()][string]$InitialPrintServer,[AllowNull()]$LocalDefaults)
    $collected = New-Object System.Collections.Generic.List[string]
    $setNumber = 0
    $firstSet = $true
    do {
        $setNumber++
        $serverDefault = ''
        $queueDefault = ''
        if ($firstSet -and -not [string]::IsNullOrWhiteSpace($InitialPrintServer)) {
            $serverDefault = $InitialPrintServer.Trim()
            if ($null -ne $LocalDefaults -and $serverDefault.Equals([string]$LocalDefaults.PrintServer,[System.StringComparison]::OrdinalIgnoreCase)) {
                $queueDefault = [string]$LocalDefaults.QueueName
            }
        }
        elseif ($firstSet -and $null -ne $LocalDefaults) {
            $serverDefault = [string]$LocalDefaults.PrintServer
            $queueDefault = [string]$LocalDefaults.QueueName
        }

        Write-Host ''
        Write-Host "Printer set $setNumber" -ForegroundColor Cyan
        if ($firstSet -and $null -ne $LocalDefaults) { Write-Host 'Operator-local default is configured. Press Enter to accept the bracketed value.' -ForegroundColor Green }
        elseif ($firstSet) { Write-Host 'No operator-local printer default is configured. Use Edit-NorthwellPrinter-Defaults.cmd if you want one.' -ForegroundColor DarkGray }
        Write-Host 'Type AD as the server to resolve queue-only names through Active Directory.' -ForegroundColor DarkGray

        $serverPrompt = if ([string]::IsNullOrWhiteSpace($serverDefault)) { 'Print server hostname (or AD)' } else { "Print server hostname [$serverDefault]" }
        $rawServer = Read-Host $serverPrompt
        if ([string]::IsNullOrWhiteSpace($rawServer)) {
            if ([string]::IsNullOrWhiteSpace($serverDefault)) { throw 'Print server cannot be blank. Enter a hostname or type AD for queue-only directory resolution.' }
            $server = $serverDefault
        }
        elseif ($rawServer.Trim().Equals('AD',[System.StringComparison]::OrdinalIgnoreCase)) { $server = '' }
        else { $server = $rawServer.Trim() }

        $queuePrompt = if ([string]::IsNullOrWhiteSpace($queueDefault)) { 'Queue name(s), comma-separated' } else { "Queue name(s), comma-separated [$queueDefault]" }
        $rawQueues = Read-Host $queuePrompt
        if ([string]::IsNullOrWhiteSpace($rawQueues)) {
            if ([string]::IsNullOrWhiteSpace($queueDefault)) { throw 'Printer queue cannot be blank.' }
            $rawQueues = $queueDefault
        }
        $queues = @(Split-SasFieldList -Value $rawQueues -Label 'Printer queue')
        foreach ($queue in $queues) {
            if ($queue.StartsWith('\\') -or $queue.StartsWith('//')) { $collected.Add($queue) }
            elseif ([string]::IsNullOrWhiteSpace($server)) { $collected.Add($queue) }
            else { $collected.Add(('\\{0}\{1}' -f $server,$queue)) }
        }
        $firstSet = $false
        Write-Host ''
        $more = Read-Host 'Add another print server / queue set? [y/N]'
    } while ($more -match '^(?i:y|yes)$')
    return $collected.ToArray()
}

if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    Write-Host ''
    Write-Host "Northwell System-Wide Printer $Action" -ForegroundColor Cyan
    Write-Host '-------------------------------------' -ForegroundColor Cyan
    Write-Host 'Enter target PC hostnames only (not IP addresses).' -ForegroundColor Yellow
    Write-Host 'This controller can be any authorized Windows admin workstation on WAB, hardwire, or authenticated VPN.' -ForegroundColor DarkGray
    $rawComputers = Read-Host 'Target PC hostname(s), comma/semicolon-separated'
    $ComputerName = @(Split-SasFieldList -Value $rawComputers -Label 'Target PC hostname')
}

if (-not $Printer -or $Printer.Count -eq 0) {
    $localDefaults = Get-SasNorthwellPrinterLocalDefaults
    $Printer = @(Read-SasNorthwellPrinterSets -InitialPrintServer $PrintServer -LocalDefaults $localDefaults)
    $PrintServer = $null
}

$authorityModule = Join-Path $repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
if (-not (Test-Path -LiteralPath $authorityModule -PathType Leaf)) { throw "Northwell network authority module not found: $authorityModule" }
if (-not $WhatIf) {
    Import-Module $authorityModule -Force -ErrorAction Stop
    $authority = Assert-SasNorthwellNetwork
    Write-Host ("Approved Northwell network authority: {0} ({1})" -f $authority.Route,$authority.Evidence) -ForegroundColor Green
    Write-Host 'Accepted protected paths include WAB Wi-Fi and DomainAuthenticated non-Wi-Fi routes such as hardwire or authenticated VPN.' -ForegroundColor Green
}

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterState.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical reversible printer engine not found: $engine" }
$desiredState = if ($Action -eq 'Map') { 'Present' } else { 'Absent' }
$invokeParameters = @{ ComputerName = $ComputerName; Printer = $Printer; DesiredState = $desiredState }
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) { $invokeParameters.PrintServer = $PrintServer }
if ($WhatIf) { $invokeParameters.WhatIf = $true }

Write-Host ''
Write-Host ("Action  : {0}" -f $Action) -ForegroundColor Cyan
Write-Host ('Targets : {0}' -f ($ComputerName -join ', ')) -ForegroundColor Cyan
Write-Host ('Printers: {0}' -f ($Printer -join ', ')) -ForegroundColor Cyan
Write-Host 'Scope is SYSTEM-WIDE for all users; no test page is printed.' -ForegroundColor Green
Write-Host 'A successful live run writes UndoPlan.json containing only state transitions that actually occurred.' -ForegroundColor Green
Write-Host ''

& $engine @invokeParameters
