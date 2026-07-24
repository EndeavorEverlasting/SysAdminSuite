Set-StrictMode -Version 2.0

$script:SasNetworkGuardRequiredPrefix = if ($env:SAS_NETWORK_GUARD_PREFIX) { $env:SAS_NETWORK_GUARD_PREFIX } else { 'NSLIJHS-WAB' }
$script:SasNetworkGuardLastWiredEvidence = 'none'
$script:SasNetworkGuardConfigError = ''

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

function Get-SasWifiSsidFromConnectionProfiles {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Profiles)

    $items = @($Profiles)
    foreach ($profile in $items) {
        if ($null -eq $profile) { continue }
        $name = [string]$profile.Name
        $alias = [string]$profile.InterfaceAlias
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($alias -match '(?i)(wi-?fi|wireless|wlan)' -and (Test-SasNorthwellWifiSsid -Ssid $name)) {
            return $name
        }
    }

    foreach ($profile in $items) {
        if ($null -eq $profile) { continue }
        $name = [string]$profile.Name
        $alias = [string]$profile.InterfaceAlias
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($alias -match '(?i)(wi-?fi|wireless|wlan)') { return $name }
    }

    return 'unknown'
}

function Get-SasWlanConnectionFromEventXml {
    [CmdletBinding()]
    param([AllowNull()][string]$XmlText)

    if ([string]::IsNullOrWhiteSpace($XmlText)) { return $null }
    try {
        [xml]$document = $XmlText
        $values = @{}
        foreach ($node in @($document.Event.EventData.Data)) {
            $name = [string]$node.GetAttribute('Name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $values[$name] = [string]$node.InnerText
        }
        return [pscustomobject][ordered]@{
            ssid = [string]$values['SSID']
            profile_name = [string]$values['ProfileName']
            interface_guid = [string]$values['InterfaceGuid']
        }
    }
    catch {
        return $null
    }
}

function Get-SasCurrentWifiSsidFromWlanEventLog {
    [CmdletBinding()]
    param([ValidateRange(1,20)][int]$MaxEvents = 8)

    try {
        $profiles = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object {
            ([string]$_.InterfaceAlias) -match '(?i)(wi-?fi|wireless|wlan)' -and (
                ([string]$_.IPv4Connectivity) -in @('Subnet','LocalNetwork','Internet') -or
                ([string]$_.IPv6Connectivity) -in @('Subnet','LocalNetwork','Internet')
            )
        })
        if ($profiles.Count -eq 0) { return 'unknown' }

        $activeProfile = $profiles[0]
        $activeGuid = ''
        try {
            $adapter = Get-NetAdapter -InterfaceIndex $activeProfile.InterfaceIndex -ErrorAction Stop
            $activeGuid = ([string]$adapter.InterfaceGuid).Trim('{}')
        }
        catch {}

        $events = @(Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'
            Id = 8001
        } -MaxEvents $MaxEvents -ErrorAction Stop)

        foreach ($event in $events) {
            $connection = Get-SasWlanConnectionFromEventXml -XmlText $event.ToXml()
            if ($null -eq $connection) { continue }
            $eventGuid = ([string]$connection.interface_guid).Trim('{}')
            if (-not [string]::IsNullOrWhiteSpace($activeGuid) -and -not [string]::IsNullOrWhiteSpace($eventGuid) -and -not $activeGuid.Equals($eventGuid, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$connection.ssid)) { return [string]$connection.ssid }
            if (-not [string]::IsNullOrWhiteSpace([string]$connection.profile_name)) { return [string]$connection.profile_name }
        }
    }
    catch {}

    return 'unknown'
}

function Get-SasCurrentWifiSsid {
    [CmdletBinding()]
    param()

    try {
        $output = & netsh wlan show interfaces 2>$null | Out-String
        $ssid = Get-SasCurrentWifiSsidFromNetshText -Text $output
        if ($ssid -ne 'unknown') { return $ssid }
    }
    catch {}

    # Windows 11 can withhold WLAN interface details from netsh when location access is restricted.
    # The WLAN-AutoConfig operational log records successful WLAN connections with ProfileName/SSID.
    # Use the newest success event for the currently connected Wi-Fi adapter before falling back to
    # the generic Windows connection-profile label (which may be a domain such as nslijhs.net).
    $eventSsid = Get-SasCurrentWifiSsidFromWlanEventLog
    if ($eventSsid -ne 'unknown') { return $eventSsid }

    try {
        $profiles = @(Get-NetConnectionProfile -ErrorAction Stop)
        $ssid = Get-SasWifiSsidFromConnectionProfiles -Profiles $profiles
        if ($ssid -ne 'unknown') { return $ssid }
    }
    catch {}

    return 'unknown'
}

function Test-SasNorthwellWifiSsid {
    [CmdletBinding()]
    param([AllowNull()][string]$Ssid)
    return (-not [string]::IsNullOrWhiteSpace($Ssid)) -and ($Ssid -ne 'unknown') -and $Ssid.StartsWith($script:SasNetworkGuardRequiredPrefix, [System.StringComparison]::Ordinal)
}

function Get-SasNetworkGuardConfigPath {
    [CmdletBinding()]
    param()
    if ($env:SAS_NETWORK_GUARD_CONFIG) { return $env:SAS_NETWORK_GUARD_CONFIG }
    if ($env:SAS_REPO_ROOT) { return (Join-Path $env:SAS_REPO_ROOT 'Config\sas-network-guard.local.json') }
    $moduleRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    return (Join-Path $moduleRepoRoot 'Config\sas-network-guard.local.json')
}

function Split-SasCsvEnv {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-SasNetworkGuardConfig {
    [CmdletBinding()]
    param()
    $script:SasNetworkGuardConfigError = ''
    $config = [ordered]@{
        allowedDnsSuffixes = @(Split-SasCsvEnv $env:SAS_NETWORK_GUARD_ALLOWED_DNS_SUFFIXES)
        allowedWindowsDomains = @(Split-SasCsvEnv $env:SAS_NETWORK_GUARD_ALLOWED_WINDOWS_DOMAINS)
        allowedLocalIpCidrs = @(Split-SasCsvEnv $env:SAS_NETWORK_GUARD_ALLOWED_LOCAL_IP_CIDRS)
        allowedGatewayCidrs = @(Split-SasCsvEnv $env:SAS_NETWORK_GUARD_ALLOWED_GATEWAY_CIDRS)
        allowedDnsServerCidrs = @(Split-SasCsvEnv $env:SAS_NETWORK_GUARD_ALLOWED_DNS_SERVER_CIDRS)
    }
    $path = Get-SasNetworkGuardConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]$config }
    try {
        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $script:SasNetworkGuardConfigError = "malformed_config:$($_.Exception.Message)"
        return $null
    }
    foreach ($name in @('allowedDnsSuffixes','allowedWindowsDomains','allowedLocalIpCidrs','allowedGatewayCidrs','allowedDnsServerCidrs')) {
        if ($null -eq $json.PSObject.Properties[$name]) { continue }
        $values = @($json.$name)
        foreach ($value in $values) {
            if ($null -eq $value -or $value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
                $script:SasNetworkGuardConfigError = "malformed_config:${name}_must_be_string_array"
                return $null
            }
            $config[$name] += $value.Trim()
        }
    }
    return [pscustomobject]$config
}

function Get-SasLocalNetworkText {
    [CmdletBinding()]
    param()
    if ($env:SAS_NETWORK_GUARD_IPCONFIG_FIXTURE) {
        return (Get-Content -LiteralPath $env:SAS_NETWORK_GUARD_IPCONFIG_FIXTURE -Raw)
    }
    try { return (& ipconfig /all 2>$null | Out-String) } catch { return '' }
}

function Test-SasIpInCidr {
    param([string]$Ip, [string]$Cidr)
    try {
        $addr = [System.Net.IPAddress]::Parse(($Ip -split '%')[0]).GetAddressBytes()
        $parts = $Cidr -split '/'
        $net = [System.Net.IPAddress]::Parse($parts[0]).GetAddressBytes()
        $prefix = if ($parts.Count -gt 1) { [int]$parts[1] } else { $addr.Length * 8 }
        if ($addr.Length -ne $net.Length) { return $false }
        for ($i = 0; $i -lt $addr.Length; $i++) {
            $bits = [Math]::Min(8, [Math]::Max(0, $prefix - ($i * 8)))
            if ($bits -eq 0) { continue }
            $mask = (0xff -shl (8 - $bits)) -band 0xff
            if (($addr[$i] -band $mask) -ne ($net[$i] -band $mask)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Test-SasNorthwellWiredEvidence {
    [CmdletBinding()]
    param([AllowNull()][string]$NetworkText)
    $script:SasNetworkGuardLastWiredEvidence = 'none'
    $config = Get-SasNetworkGuardConfig
    if ($null -eq $config) {
        $script:SasNetworkGuardLastWiredEvidence = "config_error:$script:SasNetworkGuardConfigError"
        return $false
    }
    $hasAny = @($config.allowedDnsSuffixes + $config.allowedWindowsDomains + $config.allowedLocalIpCidrs + $config.allowedGatewayCidrs + $config.allowedDnsServerCidrs).Count -gt 0
    if (-not $hasAny) { return $false }
    $text = if ($null -eq $NetworkText) { '' } else { $NetworkText }
    $lower = $text.ToLowerInvariant()
    foreach ($suffix in $config.allowedDnsSuffixes) {
        if ($lower.Contains($suffix.ToLowerInvariant())) { $script:SasNetworkGuardLastWiredEvidence = "dns_suffix=$suffix"; return $true }
    }
    foreach ($domain in $config.allowedWindowsDomains) {
        if ($lower.Contains($domain.ToLowerInvariant())) { $script:SasNetworkGuardLastWiredEvidence = "windows_domain=$domain"; return $true }
    }
    $localIps = New-Object System.Collections.Generic.List[string]
    $gatewayIps = New-Object System.Collections.Generic.List[string]
    $dnsIps = New-Object System.Collections.Generic.List[string]
    $inDns = $false
    foreach ($line in ($text -split "`r?`n")) {
        $lineLower = $line.ToLowerInvariant()
        $ips = @([regex]::Matches($line, '([0-9]{1,3}\.){3}[0-9]{1,3}') | ForEach-Object { $_.Value })
        if ($lineLower.Contains('ipv4 address') -or $lineLower.Contains('ip address')) {
            foreach ($ip in $ips) { [void]$localIps.Add($ip) }
            $inDns = $false
        } elseif ($lineLower.Contains('default gateway')) {
            foreach ($ip in $ips) { [void]$gatewayIps.Add($ip) }
            $inDns = $false
        } elseif ($lineLower.Contains('dns servers')) {
            foreach ($ip in $ips) { [void]$dnsIps.Add($ip) }
            $inDns = $true
        } elseif ($inDns -and $line -match '^\s+') {
            foreach ($ip in $ips) { [void]$dnsIps.Add($ip) }
        } else {
            $inDns = $false
        }
    }
    foreach ($ip in $localIps) { foreach ($cidr in $config.allowedLocalIpCidrs) { if (Test-SasIpInCidr -Ip $ip -Cidr $cidr) { $script:SasNetworkGuardLastWiredEvidence = "local_ip_cidr=$cidr"; return $true } } }
    foreach ($ip in $gatewayIps) { foreach ($cidr in $config.allowedGatewayCidrs) { if (Test-SasIpInCidr -Ip $ip -Cidr $cidr) { $script:SasNetworkGuardLastWiredEvidence = "gateway_cidr=$cidr"; return $true } } }
    foreach ($ip in $dnsIps) { foreach ($cidr in $config.allowedDnsServerCidrs) { if (Test-SasIpInCidr -Ip $ip -Cidr $cidr) { $script:SasNetworkGuardLastWiredEvidence = "dns_server_cidr=$cidr"; return $true } } }
    return $false
}

function Test-SasNorthwellNetworkPosture {
    [CmdletBinding()]
    param([AllowNull()][string]$Ssid, [AllowNull()][string]$NetworkText)
    if (Test-SasNorthwellWifiSsid -Ssid $Ssid) { return $true }
    return (Test-SasNorthwellWiredEvidence -NetworkText $NetworkText)
}

function Assert-SasNorthwellWifi {
    [CmdletBinding()]
    param()
    $ssid = Get-SasCurrentWifiSsid
    if (Test-SasNorthwellWifiSsid -Ssid $ssid) { return }
    $networkText = Get-SasLocalNetworkText
    if (Test-SasNorthwellWiredEvidence -NetworkText $networkText) { return }
    throw "Network check failed: this script must be run from an approved Northwell network. Connect to Wi-Fi SSID starting with $script:SasNetworkGuardRequiredPrefix or approved Northwell wired Ethernet and rerun. Current SSID: $ssid. Wired evidence: $script:SasNetworkGuardLastWiredEvidence."
}

Export-ModuleMember -Function Get-SasCurrentWifiSsidFromNetshText, Get-SasWifiSsidFromConnectionProfiles, Get-SasWlanConnectionFromEventXml, Get-SasCurrentWifiSsidFromWlanEventLog, Get-SasCurrentWifiSsid, Test-SasNorthwellWifiSsid, Get-SasNetworkGuardConfig, Get-SasLocalNetworkText, Test-SasIpInCidr, Test-SasNorthwellWiredEvidence, Test-SasNorthwellNetworkPosture, Assert-SasNorthwellWifi
