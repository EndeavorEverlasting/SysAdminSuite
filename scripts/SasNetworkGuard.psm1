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

function Get-SasNetworkGuardConfigPath {
    [CmdletBinding()]
    param()
    if ($env:SAS_NETWORK_GUARD_CONFIG) { return $env:SAS_NETWORK_GUARD_CONFIG }
    if ($env:SAS_REPO_ROOT) { return (Join-Path $env:SAS_REPO_ROOT 'Config/sas-network-guard.local.json') }
    return 'Config/sas-network-guard.local.json'
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

Export-ModuleMember -Function Get-SasCurrentWifiSsidFromNetshText, Get-SasCurrentWifiSsid, Test-SasNorthwellWifiSsid, Get-SasNetworkGuardConfig, Get-SasLocalNetworkText, Test-SasIpInCidr, Test-SasNorthwellWiredEvidence, Test-SasNorthwellNetworkPosture, Assert-SasNorthwellWifi
