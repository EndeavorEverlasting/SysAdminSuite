Set-StrictMode -Version 2.0

$script:SasNetworkGuardRequiredPrefix = if ($env:SAS_NETWORK_GUARD_PREFIX) { $env:SAS_NETWORK_GUARD_PREFIX } else { 'NSLIJHS-WAB' }

function Get-SasCurrentWifiSsidFromNetshText {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)][AllowNull()][string]$Text)

    begin { $lines = New-Object System.Collections.Generic.List[string] }
    process {
        if ($null -ne $Text) {
            foreach ($line in ($Text -split "`r?`n")) { [void]$lines.Add($line) }
        }
    }
    end {
        foreach ($line in $lines) {
            if ($line -match '^\s*SSID\s*:\s*(.*)\s*$') {
                $ssid = $Matches[1].Trim()
                if ([string]::IsNullOrWhiteSpace($ssid)) { return 'unknown' }
                return $ssid
            }
        }
        return 'unknown'
    }
}

function Get-SasCurrentWifiSsid {
    [CmdletBinding()]
    param()
    try {
        $output = & netsh wlan show interfaces 2>$null | Out-String
        return Get-SasCurrentWifiSsidFromNetshText -Text $output
    } catch {
        return 'unknown'
    }
}

function Test-SasNorthwellWifiSsid {
    [CmdletBinding()]
    param([AllowNull()][string]$Ssid)
    return (-not [string]::IsNullOrWhiteSpace($Ssid)) -and ($Ssid -ne 'unknown') -and $Ssid.StartsWith($script:SasNetworkGuardRequiredPrefix, [System.StringComparison]::Ordinal)
}

function Assert-SasNorthwellWifi {
    [CmdletBinding()]
    param()
    $ssid = Get-SasCurrentWifiSsid
    if (-not (Test-SasNorthwellWifiSsid -Ssid $ssid)) {
        throw "Network check failed: this script must be run while connected to a Northwell Wi-Fi network starting with $script:SasNetworkGuardRequiredPrefix. Current SSID: $ssid. Connect to $script:SasNetworkGuardRequiredPrefix and rerun."
    }
}

Export-ModuleMember -Function Get-SasCurrentWifiSsidFromNetshText, Get-SasCurrentWifiSsid, Test-SasNorthwellWifiSsid, Assert-SasNorthwellWifi
