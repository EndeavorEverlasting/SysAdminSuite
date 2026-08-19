#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $ConfirmRepair) { throw 'VPN network-authority runtime repair requires -ConfirmRepair.' }

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$targetPath = Join-Path $RuntimeRoot 'scripts\SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "Network guard runtime surface missing: $targetPath"
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $RuntimeRoot 'runs\field-repair'
    } else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes'
    }
    $EvidenceRoot = Join-Path $base ('vpn-domain-auth-precedence-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$backupPath = Join-Path $EvidenceRoot 'SasNetworkGuard.before.psm1'
$resultPath = Join-Path $EvidenceRoot 'vpn-domain-auth-precedence-repair-result.json'

function Get-RepairHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-Parse([string]$Text) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ('Repaired network guard does not parse: ' + (($errors | ForEach-Object { $_.Message }) -join '; '))
    }
}

function Test-RepairPresent([string]$Text) {
    return ($Text.Contains("`$script:SasNetworkGuardDomainAuthPrecedence = 'live_domain_authenticated_non_wifi_v1'") -and
        $Text.Contains('Live Windows domain authentication is stronger than the physical uplink label') -and
        $Text.Contains('domain_authenticated_interface=$alias;interface_index=$interfaceIndex;local_ip=$ip') -and
        -not $Text.Contains('if (@($config.allowedLocalIpCidrs).Count -eq 0) { return $false }'))
}

function Replace-FunctionBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$NextMarker,
        [Parameter(Mandatory = $true)][string]$Replacement
    )
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    $next = $Text.IndexOf($NextMarker, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $next -le $start) {
        throw "Network guard repair boundaries were not found: $StartMarker -> $NextMarker"
    }
    if ($Text.IndexOf($StartMarker, $start + 1, [StringComparison]::Ordinal) -ge 0 -or
        $Text.IndexOf($NextMarker, $next + 1, [StringComparison]::Ordinal) -ge 0) {
        throw "Network guard repair boundaries are ambiguous: $StartMarker -> $NextMarker"
    }
    return $Text.Substring(0, $start) + $Replacement + $Text.Substring($next)
}

$source = [IO.File]::ReadAllText($targetPath)
$beforeSha = Get-RepairHash $targetPath
$changed = $false
$classification = 'VPN_DOMAIN_AUTH_PRECEDENCE_RUNTIME_REPAIR_ALREADY_PRESENT'

if (-not (Test-RepairPresent $source)) {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force -ErrorAction Stop
    $newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $source.Replace("`r`n","`n").Replace("`r","`n")

    $marker = "`$script:SasNetworkGuardDomainAuthPrecedence = 'live_domain_authenticated_non_wifi_v1'`n"
    if (-not $text.Contains('$script:SasNetworkGuardConfigError =')) {
        throw 'Network guard config marker was not found.'
    }
    if (-not $text.Contains('$script:SasNetworkGuardDomainAuthPrecedence')) {
        $configLineEnd = $text.IndexOf("`n", $text.IndexOf('$script:SasNetworkGuardConfigError =', [StringComparison]::Ordinal), [StringComparison]::Ordinal)
        if ($configLineEnd -lt 0) { throw 'Network guard config line ending was not found.' }
        $text = $text.Insert($configLineEnd + 1, $marker)
    }

    $domainAuth = @'
function Test-SasNorthwellDomainAuthenticatedEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$ConnectionProfiles,
        [AllowNull()][scriptblock]$AddressResolver
    )

    if (-not $PSBoundParameters.ContainsKey('ConnectionProfiles')) {
        try { $ConnectionProfiles = @(Get-NetConnectionProfile -ErrorAction Stop) }
        catch { return $false }
    }
    if ($null -eq $AddressResolver) {
        $AddressResolver = {
            param($InterfaceIndex)
            @(Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        }
    }

    $usableConnectivity = @('Subnet','LocalNetwork','Internet')
    foreach ($profile in @($ConnectionProfiles)) {
        if ($null -eq $profile) { continue }
        $alias = [string]$profile.InterfaceAlias
        if ([string]$profile.NetworkCategory -ne 'DomainAuthenticated') { continue }
        if ($alias -match '(?i)(wi-?fi|wireless|wlan)') { continue }
        if (([string]$profile.IPv4Connectivity -notin $usableConnectivity) -and
            ([string]$profile.IPv6Connectivity -notin $usableConnectivity)) { continue }

        $interfaceIndex = [int]$profile.InterfaceIndex
        try { $addresses = @(& $AddressResolver $interfaceIndex) }
        catch { continue }

        foreach ($address in $addresses) {
            if ($null -eq $address) { continue }
            $ip = if ($address -is [string]) { [string]$address } else { [string]$address.IPAddress }
            $ip = $ip.Trim()
            if ([string]::IsNullOrWhiteSpace($ip) -or $ip -match '^127\.' -or $ip -match '^169\.254\.') { continue }
            $script:SasNetworkGuardLastWiredEvidence = "domain_authenticated_interface=$alias;interface_index=$interfaceIndex;local_ip=$ip"
            return $true
        }
    }
    return $false
}

'@

    $wired = @'
function Test-SasNorthwellWiredEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$NetworkText,
        [AllowNull()][object[]]$ConnectionProfiles,
        [AllowNull()][scriptblock]$AddressResolver
    )
    $script:SasNetworkGuardLastWiredEvidence = 'none'

    # Live Windows domain authentication is stronger than the physical uplink label. A workstation
    # may legitimately remain on guest/Internet Wi-Fi while a corporate VPN supplies the protected
    # route. Evaluate that live non-Wi-Fi authority before any optional static allowlist.
    $liveEvidenceArgs = @{}
    if ($PSBoundParameters.ContainsKey('ConnectionProfiles')) { $liveEvidenceArgs.ConnectionProfiles = $ConnectionProfiles }
    if ($PSBoundParameters.ContainsKey('AddressResolver')) { $liveEvidenceArgs.AddressResolver = $AddressResolver }
    if (Test-SasNorthwellDomainAuthenticatedEvidence @liveEvidenceArgs) { return $true }

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

'@

    $text = Replace-FunctionBlock -Text $text `
        -StartMarker 'function Test-SasNorthwellDomainAuthenticatedEvidence {' `
        -NextMarker 'function Test-SasNorthwellWiredEvidence {' `
        -Replacement $domainAuth
    $text = Replace-FunctionBlock -Text $text `
        -StartMarker 'function Test-SasNorthwellWiredEvidence {' `
        -NextMarker 'function Test-SasNorthwellNetworkPosture {' `
        -Replacement $wired

    if ($newline -eq "`r`n") { $text = $text.Replace("`n","`r`n") }

    try {
        Assert-Parse $text
        if (-not (Test-RepairPresent $text)) {
            throw 'VPN DomainAuthenticated precedence repair semantic verification failed.'
        }
        [IO.File]::WriteAllText($targetPath, $text, (New-Object Text.UTF8Encoding($false)))
        $changed = $true
        $classification = 'VPN_DOMAIN_AUTH_PRECEDENCE_RUNTIME_REPAIR_APPLIED'
    }
    catch {
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force -ErrorAction SilentlyContinue
        throw "VPN DOMAIN-AUTH PRECEDENCE REPAIR FAILED; ORIGINAL RESTORED. $($_.Exception.Message)"
    }
}

$final = [IO.File]::ReadAllText($targetPath)
Assert-Parse $final
if (-not (Test-RepairPresent $final)) {
    throw 'VPN DomainAuthenticated precedence repair markers are absent after repair.'
}
$afterSha = Get-RepairHash $targetPath
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-vpn-domain-auth-precedence-runtime-repair/v1'
    status = 'COMPLETED'
    classification = $classification
    runtime_root = $RuntimeRoot
    target_path = $targetPath
    changed = $changed
    before_sha256 = $beforeSha
    after_sha256 = $afterSha
    authority = 'live_windows_domain_authenticated_non_wifi_interface'
    guest_wifi_may_coexist = $true
    exact_local_ip_allowlist_required_for_domain_authenticated_vpn = $false
    powershell_parse_passed = $true
    semantic_verification = $true
    git_performed = $false
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    evidence_path = $resultPath
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($PassThru) { return $result }
Write-Host $result.classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"
