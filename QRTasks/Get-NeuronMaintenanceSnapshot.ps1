<#
.SYNOPSIS
    Safe Neuron maintenance-console inspired snapshot.

.DESCRIPTION
    Captures the same class of information visible in the Neuron local maintenance UI:
    ping checks, IP configuration, service status, firewall state, netstat output,
    wireless profiles/interfaces/networks, and optional local subnet discovery.

    Default behavior is read-only. Potentially disruptive repair behavior, such as
    DHCP release/renew, requires explicit opt-in.

.PARAMETER OutDir
    Output directory for timestamped artifacts. Defaults to the current user's Desktop.

.PARAMETER ServerTargets
    Primary server targets to ping.

.PARAMETER FollowerTargets
    Follower/secondary server targets to ping.

.PARAMETER VpnTargets
    VPN targets to ping.

.PARAMETER ServiceNamePatterns
    Service name/display-name patterns to check.

.PARAMETER IncludeNetworkScan
    Include ARP table and lightweight local subnet scan hints.

.PARAMETER AllowNetworkReset
    Permit DHCP release/renew. Without this switch, release/renew is documented but not executed.

.PARAMETER ReleaseRenew
    Perform DHCP release/renew. Requires -AllowNetworkReset.

.EXAMPLE
    .\Get-NeuronMaintenanceSnapshot.ps1 -ServerTargets 10.8.0.1 -VpnTargets 10.8.0.1

.EXAMPLE
    .\Get-NeuronMaintenanceSnapshot.ps1 -IncludeNetworkScan

.EXAMPLE
    .\Get-NeuronMaintenanceSnapshot.ps1 -ReleaseRenew -AllowNetworkReset
#>
[CmdletBinding()]
param(
    [string]$OutDir = ([Environment]::GetFolderPath('Desktop')),

    [string[]]$ServerTargets = @(),

    [string[]]$FollowerTargets = @(),

    [string[]]$VpnTargets = @(),

    [string[]]$ServiceNamePatterns = @(
        'MSMQ',
        'OpenVPN',
        'DCIS',
        'SmartLynx',
        'SIS',
        'Epic',
        'Imprivata'
    ),

    [switch]$IncludeNetworkScan,

    [switch]$ReleaseRenew,

    [switch]$AllowNetworkReset
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

function New-SafeDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Section {
    param(
        [string]$Title,
        [scriptblock]$Body
    )

    $line = ('=' * 78)
    $script:ReportLines += ''
    $script:ReportLines += $line
    $script:ReportLines += $Title
    $script:ReportLines += $line

    try {
        $result = & $Body 2>&1 | Out-String -Width 220
        if ([string]::IsNullOrWhiteSpace($result)) {
            $script:ReportLines += '[no output]'
        } else {
            $script:ReportLines += $result.TrimEnd()
        }
    } catch {
        $script:ReportLines += "ERROR: $($_.Exception.Message)"
    }
}

function Test-TargetPing {
    param(
        [string]$Group,
        [string[]]$Targets
    )

    if (-not $Targets -or $Targets.Count -eq 0) {
        [pscustomobject]@{
            Group      = $Group
            Target     = '[not configured]'
            Reachable  = $null
            LatencyMs  = $null
            Notes      = 'No target configured yet. Add baseline config once real endpoints are known.'
        }
        return
    }

    foreach ($target in $Targets) {
        $ping = $null
        try {
            $ping = Test-Connection -ComputerName $target -Count 4 -ErrorAction Stop
            $avg = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 2)
            [pscustomobject]@{
                Group      = $Group
                Target     = $target
                Reachable  = $true
                LatencyMs  = $avg
                Notes      = "Replies: $($ping.Count)"
            }
        } catch {
            [pscustomobject]@{
                Group      = $Group
                Target     = $target
                Reachable  = $false
                LatencyMs  = $null
                Notes      = $_.Exception.Message
            }
        }
    }
}

function Get-ServiceMatches {
    param([string[]]$Patterns)

    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    foreach ($pattern in $Patterns) {
        $matches = $services | Where-Object {
            $_.Name -like "*$pattern*" -or $_.DisplayName -like "*$pattern*"
        }

        if (-not $matches) {
            [pscustomobject]@{
                Pattern     = $pattern
                Name        = '[not found]'
                DisplayName = '[not found]'
                State       = $null
                StartMode   = $null
                StartName   = $null
            }
        } else {
            $matches | Select-Object @{n='Pattern';e={$pattern}}, Name, DisplayName, State, StartMode, StartName
        }
    }
}

function Invoke-CmdText {
    param([string]$Command)
    cmd.exe /c $Command
}

New-SafeDirectory -Path $OutDir
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$baseName = "NeuronMaintenanceSnapshot_$env:COMPUTERNAME`_$stamp"
$textPath = Join-Path $OutDir "$baseName.txt"
$jsonPath = Join-Path $OutDir "$baseName.json"

$script:ReportLines = @()
$summary = [ordered]@{
    Timestamp       = (Get-Date).ToString('s')
    ComputerName    = $env:COMPUTERNAME
    UserName        = $env:USERNAME
    ReadOnlyDefault = $true
    OutputText      = $textPath
    OutputJson      = $jsonPath
}

Write-Host "`n  Neuron maintenance snapshot" -ForegroundColor Cyan
Write-Host "  Output: $textPath`n" -ForegroundColor DarkGray

Write-Section -Title 'Host Identity' -Body {
    Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, Name, Domain, TotalPhysicalMemory | Format-List
    Get-CimInstance Win32_BIOS | Select-Object SerialNumber, SMBIOSBIOSVersion, ReleaseDate | Format-List
}

$pingResults = @()
$pingResults += Test-TargetPing -Group 'Server' -Targets $ServerTargets
$pingResults += Test-TargetPing -Group 'Follower' -Targets $FollowerTargets
$pingResults += Test-TargetPing -Group 'VPN' -Targets $VpnTargets
$summary.PingResults = $pingResults

Write-Section -Title 'Ping Checks: Server / Follower / VPN' -Body {
    $pingResults | Format-Table -AutoSize
}

Write-Section -Title 'IP Configuration' -Body {
    Invoke-CmdText 'ipconfig /all'
}

Write-Section -Title 'Routes' -Body {
    route print
}

$serviceResults = @(Get-ServiceMatches -Patterns $ServiceNamePatterns)
$summary.ServiceResults = $serviceResults

Write-Section -Title 'Selected Service Checks' -Body {
    $serviceResults | Sort-Object Pattern, Name | Format-Table -AutoSize
}

Write-Section -Title 'All Services' -Body {
    Get-Service | Sort-Object Name | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
}

Write-Section -Title 'Firewall Profiles' -Body {
    if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Format-Table -AutoSize
    } else {
        Invoke-CmdText 'netsh advfirewall show allprofiles'
    }
}

Write-Section -Title 'NetStat' -Body {
    Invoke-CmdText 'netstat -ano'
}

Write-Section -Title 'Wireless Profiles' -Body {
    Invoke-CmdText 'netsh wlan show profiles'
}

Write-Section -Title 'Wireless Interfaces' -Body {
    Invoke-CmdText 'netsh wlan show interfaces'
}

Write-Section -Title 'Wireless Networks' -Body {
    Invoke-CmdText 'netsh wlan show networks mode=bssid'
}

if ($IncludeNetworkScan) {
    Write-Section -Title 'Network Device Scan: ARP Table' -Body {
        arp -a
    }

    Write-Section -Title 'Network Device Scan: Local Adapter Hint' -Body {
        Get-CimInstance Win32_NetworkAdapterConfiguration |
            Where-Object { $_.IPEnabled } |
            Select-Object Description, MACAddress, IPAddress, IPSubnet, DefaultIPGateway, DNSServerSearchOrder |
            Format-List
    }
}

if ($ReleaseRenew) {
    if (-not $AllowNetworkReset) {
        Write-Section -Title 'Release/Renew Requested But Blocked' -Body {
            'Release/Renew was requested, but -AllowNetworkReset was not supplied. No network reset was performed.'
        }
    } else {
        Write-Section -Title 'Release/Renew Executed' -Body {
            Invoke-CmdText 'ipconfig /release'
            Invoke-CmdText 'ipconfig /renew'
            Invoke-CmdText 'ipconfig'
        }
        $summary.NetworkResetExecuted = $true
    }
} else {
    $summary.NetworkResetExecuted = $false
}

$script:ReportLines | Set-Content -LiteralPath $textPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host "  Snapshot complete." -ForegroundColor Green
Write-Host "  Text: $textPath" -ForegroundColor Gray
Write-Host "  JSON: $jsonPath" -ForegroundColor Gray
