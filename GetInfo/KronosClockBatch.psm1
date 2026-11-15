#Requires -Version 5.1

$script:IdentityFields = @('IPAddress', 'HostName', 'MACAddress', 'SerialNumber', 'DeviceID', 'DeviceName')
$script:NetworkFields = @('SubnetMask', 'ScopeId', 'DefaultGateway')
$script:Aliases = @{
    IPAddress = @('IPAddress', 'IP')
    HostName = @('HostName', 'ReverseDns', 'SysName')
    MACAddress = @('MACAddress', 'MAC', 'ClientId')
    SerialNumber = @('SerialNumber', 'Serial')
    DeviceID = @('DeviceID', 'TerminalID')
    DeviceName = @('DeviceName')
    SubnetMask = @('SubnetMask')
    ScopeId = @('ScopeId', 'Subnet')
    DefaultGateway = @('DefaultGateway', 'Gateway')
    Model = @('Model')
    DHCPState = @('DHCPState', 'AddressState', 'DHCPStatus')
}

function ConvertTo-KronosIP {
    param([string]$Value)
    $address = $null
    if ($Value -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$' -and
        [Net.IPAddress]::TryParse($Value, [ref]$address) -and
        $address.ToString() -eq $Value) {
        return $Value
    }
}

function ConvertTo-KronosField {
    param([string]$Field, [string]$Value)
    $Value = $Value.Trim()
    if (-not $Value) { return }
    switch ($Field) {
        { $_ -in @('IPAddress', 'ScopeId', 'SubnetMask', 'DefaultGateway') } {
            $ip = ConvertTo-KronosIP $Value
            if ($ip -and $Field -eq 'SubnetMask') {
                $bits = ($ip.Split('.') | ForEach-Object { [Convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join ''
                if ($bits -notmatch '^1+0*$') { return }
            }
            return $ip
        }
        'MACAddress' {
            if ($Value -match '^(?:[a-f0-9]{12}|(?:[a-f0-9]{2}:){5}[a-f0-9]{2}|(?:[a-f0-9]{2}-){5}[a-f0-9]{2})$') {
                $hex = ($Value -replace '[:-]', '').ToUpperInvariant()
                if ($hex -notin @('000000000000', 'FFFFFFFFFFFF')) {
                    return [regex]::Replace($hex, '(.{2})(?!$)', '$1:')
                }
            }
            return
        }
        'HostName' {
            $Value = $Value.TrimEnd('.')
            if ($Value.Length -le 253 -and $Value -match '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$') {
                return $Value
            }
            return
        }
        default {
            if ($Value.Length -le 128 -and $Value -notmatch '[\x00-\x1f\x7f]') { return $Value }
        }
    }
}

function Test-KronosFieldMatch {
    param([string]$Field, [string]$Left, [string]$Right)
    if ($Left -eq $Right) { return $true }
    if ($Field -eq 'HostName' -and ($Left.Contains('.') -xor $Right.Contains('.'))) {
        return $Left.Split('.')[0] -eq $Right.Split('.')[0]
    }
    return $false
}

function Get-KronosMatches {
    param([System.Collections.IDictionary]$Hints, [object[]]$Candidates, [string[]]$Fields)
    foreach ($candidate in $Candidates) {
        $matched = $false
        $conflicting = $false
        foreach ($field in $Fields) {
            if (-not $Hints[$field] -or -not $candidate[$field]) { continue }
            if (Test-KronosFieldMatch $field $Hints[$field] $candidate[$field]) {
                $matched = $true
            } else {
                $conflicting = $true
            }
        }
        if ($matched) { [pscustomobject]@{ Data = $candidate; Conflict = $conflicting } }
    }
}


function Read-KronosFields {
    param([psobject]$Row, [string[]]$Fields, [switch]$Strict)
    $data = @{}
    foreach ($field in $Fields) {
        foreach ($alias in $script:Aliases[$field]) {
            $property = $Row.PSObject.Properties[$alias]
            if (-not $property -or -not ([string]$property.Value).Trim()) { continue }
            $value = ConvertTo-KronosField $field $property.Value
            if ($Strict -and (-not $value -or ($data[$field] -and
                -not (Test-KronosFieldMatch $field $value $data[$field])))) {
                throw "Invalid or conflicting $field."
            }
            if ($value -and -not $data[$field]) { $data[$field] = $value }
            if (-not $Strict) { break }
        }
    }
    return $data
}

function Set-KronosFields {
    param(
        [System.Collections.IDictionary]$Data, [System.Collections.IDictionary]$Sources,
        [System.Collections.IDictionary]$Incoming, [string]$Source
    )
    foreach ($field in $Incoming.Keys) {
        if (-not $Data[$field] -or ($field -eq 'HostName' -and -not $Data[$field].Contains('.') -and
            $Incoming[$field].Contains('.') -and (Test-KronosFieldMatch $field $Data[$field] $Incoming[$field]))) {
            $Data[$field] = $Incoming[$field]
            $Sources[$field] = $Source
        } elseif (-not (Test-KronosFieldMatch $field $Data[$field] $Incoming[$field])) {
            $Sources[$field] = 'Conflict'
        }
    }
}

function Join-KronosEvidence {
    param(
        [System.Collections.IDictionary]$Data, [System.Collections.IDictionary]$Sources,
        [object[]]$Candidates, [string[]]$Keys, [string]$Source, [string[]]$Fields
    )
    $matches = @(Get-KronosMatches $Data $Candidates $Keys)
    if ($matches.Count -eq 0) { return 'Unmatched' }
    $valid = @($matches | Where-Object { -not $_.Conflict })
    if ($valid.Count -eq 0) { return 'Conflict' }
    if ($valid.Count -gt 1) { return 'Ambiguous' }
    # Check each key independently so weak name matches cannot discard a conflicting exact identity.
    foreach ($match in $matches | Where-Object Conflict) {
        foreach ($key in $Keys) {
            if ($Data[$key] -and $match.Data[$key] -and (Test-KronosFieldMatch $key $Data[$key] $match.Data[$key]) -and
                (-not $valid[0].Data[$key] -or -not (Test-KronosFieldMatch $key $Data[$key] $valid[0].Data[$key]))) {
                return 'Conflict'
            }
        }
    }
    $incoming = @{}
    foreach ($field in $Fields) {
        if ($valid[0].Data[$field]) { $incoming[$field] = $valid[0].Data[$field] }
    }
    Set-KronosFields $Data $Sources $incoming $Source
    return 'Matched'
}

function Test-KronosScope {
    param([string]$IPAddress, [System.Collections.IDictionary]$Scope, [switch]$UsableHost)
    if (-not $Scope.ScopeId -or -not $Scope.SubnetMask) { return $false }
    $address = [Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    $mask = [Net.IPAddress]::Parse($Scope.SubnetMask).GetAddressBytes()
    $network = [Net.IPAddress]::Parse($Scope.ScopeId).GetAddressBytes()
    $hostBits = 0
    $hostCapacity = 0
    for ($i = 0; $i -lt 4; $i++) {
        if (($address[$i] -band $mask[$i]) -ne $network[$i]) { return $false }
        $hostBits += $address[$i] -band (255 -bxor $mask[$i])
        $hostCapacity += 255 -bxor $mask[$i]
    }
    if ($UsableHost) {
        # Reject special-use endpoints and scope/network addresses. RFC 3021 /31 hosts are usable.
        return ($address[0] -gt 0 -and $address[0] -ne 127 -and $address[0] -lt 224 -and
            -not ($address[0] -eq 169 -and $address[1] -eq 254) -and
            ($hostCapacity -le 1 -or ($hostBits -gt 0 -and $hostBits -lt $hostCapacity)))
    }
    return $true
}

function Resolve-KronosIPv4 {
    param([string]$HostName)
    if (-not $HostName.Contains('.')) { return }
    try {
        $lookup = [Net.Dns]::GetHostAddressesAsync("$HostName.")
        if ($lookup.Wait(2000)) {
            $lookup.Result | Where-Object AddressFamily -eq InterNetwork |
                ForEach-Object IPAddressToString | Sort-Object -Unique
        }
    } catch { }
}

function Test-KronosResponse {
    param([string]$IPAddress)
    $ping = New-Object Net.NetworkInformation.Ping
    try {
        if ($ping.Send($IPAddress, 1000).Status -eq 'Success') { return 'Responded to ICMP' }
        return 'No ICMP reply'
    } catch {
        return 'ICMP unavailable'
    } finally {
        $ping.Dispose()
    }
}

function Import-KronosEvidence {
    param([string]$Path, [string[]]$Fields, [switch]$ClockInventory)
    if (-not $Path) { return }
    $seen = @{}
    foreach ($row in Import-Csv -LiteralPath $Path -ErrorAction Stop) {
        $record = Read-KronosFields $row $Fields
        # Legacy inventories fall back to the model-level SNMP object ID for DeviceID.
        if ($ClockInventory -and $record.DeviceID -and
            ($record.DeviceID -eq $row.SysObjectID -or $record.DeviceID -match '^\.?[0-9]+(?:\.[0-9]+){3,}$')) {
            $record.Remove('DeviceID')
        }
        $signature = ConvertTo-Json -InputObject @($Fields | ForEach-Object { $record[$_] }) -Compress
        if (-not $seen.ContainsKey($signature)) {
            $seen[$signature] = $true
            $record
        }
    }
}

function Get-KronosBatchReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RequestPath,
        [string]$InventoryPath,
        [string]$LeasePath,
        [string]$ScopePath,
        [string]$ReservationPath,
        [switch]$Live,
        [string]$DnsDomain
    )
    $identity = $script:IdentityFields
    $network = $script:NetworkFields
    $dhcpKeys = @('IPAddress', 'MACAddress', 'HostName')
    $inventoryFields = $identity + $network + @('Model')
    $leaseFields = $dhcpKeys + $network + @('DHCPState')
    $scopes = @(Import-KronosEvidence $ScopePath $network | Where-Object { $_.ScopeId })
    $inventory = @(Import-KronosEvidence $InventoryPath $inventoryFields -ClockInventory)
    # Derive all known memberships consistently before using a network field as a selection hint.
    $networkInventory = @(
        foreach ($clock in $inventory) {
            $candidate = $clock.Clone()
            if ($clock.IPAddress) {
                $memberships = @($scopes | Where-Object { Test-KronosScope $clock.IPAddress $_ })
                if ($memberships.Count -eq 1) {
                    foreach ($field in $network) {
                        if (-not $candidate[$field] -and $memberships[0][$field]) {
                            $candidate[$field] = $memberships[0][$field]
                        }
                    }
                }
            }
            $candidate
        }
    )
    $leases = @(Import-KronosEvidence $LeasePath $leaseFields)
    $reservations = @(Import-KronosEvidence $ReservationPath ($dhcpKeys + @('ScopeId')) |
        Where-Object { $_.IPAddress -and $_.MACAddress })
    if ($Live -and -not @($scopes | Where-Object { $_.ScopeId -and $_.SubnetMask }).Count) {
        throw 'Live matching requires at least one valid approved site scope and subnet mask.'
    }
    if ($DnsDomain) {
        $DnsDomain = ConvertTo-KronosField HostName $DnsDomain
        if (-not $DnsDomain -or -not $DnsDomain.Contains('.')) { throw 'Invalid approved DNS suffix.' }
    }
    $requests = @(Import-Csv -LiteralPath $RequestPath -ErrorAction Stop | Select-Object -First 251)
    if ($requests.Count -eq 0 -or $requests.Count -gt 250) {
        throw 'Assignment CSV must contain between 1 and 250 clock rows.'
    }
    $probeCache = @{}
    $dnsCache = @{}
    $number = 0
    foreach ($row in $requests) {
        $number++
        $issues = New-Object 'Collections.Generic.List[string]'
        $data = @{}
        $sources = @{}
        $valid = $true
        $reservation = 'Unknown'
        $reservationResult = 'Unmatched'
        $reachability = 'Not checked'
        try {
            $hints = Read-KronosFields $row ($identity + $network) -Strict
            if ($hints.Count -eq 0) { throw 'Supply at least one recognized clock or network field.' }
            Set-KronosFields $data $sources $hints 'Technician input'
        } catch {
            $valid = $false
            $issues.Add($_.Exception.Message)
        }

        $matchingScopes = @()
        if ($valid) {
            # A network-only hint identifies a clock only when it is unique in the clock inventory.
            $hasIdentityHint = [bool]@($identity | Where-Object { $data[$_] }).Count
            if ($hasIdentityHint) {
                $inventoryResult = Join-KronosEvidence $data $sources $inventory $identity 'Clock inventory' $inventoryFields
            } else {
                $inventoryResult = 'Unmatched'
                if ($networkInventory.Count -and -not @($networkInventory | Where-Object {
                    $candidate = $_
                    @($network | Where-Object { $data[$_] -and -not $candidate[$_] }).Count -gt 0
                }).Count) {
                    $inventoryResult = Join-KronosEvidence $data $sources $networkInventory $network 'Clock inventory' ($identity + @('Model'))
                }
            }
            if ($inventoryResult -in @('Conflict', 'Ambiguous')) { $issues.Add("Clock inventory: $inventoryResult") }

            if (-not $issues.Count -and $Live -and $hasIdentityHint -and $DnsDomain -and $data.HostName) {
                $addresses = @()
                $name = $data.HostName
                if (-not $name.Contains('.')) { $name = "$name.$DnsDomain" }
                if (-not $name.EndsWith(".$DnsDomain", [StringComparison]::OrdinalIgnoreCase)) {
                    $issues.Add('Hostname is outside the approved DNS suffix.')
                } else {
                    if (-not $dnsCache.ContainsKey($name)) {
                        $dnsCache[$name] = @(Resolve-KronosIPv4 $name)
                    }
                    $addresses = $dnsCache[$name]
                }
                if ($addresses.Count -eq 1) {
                    Set-KronosFields $data $sources @{ IPAddress = $addresses[0]; HostName = $name } 'DNS'
                } elseif ($addresses.Count -gt 1) {
                    $issues.Add('DNS returned multiple IPv4 addresses.')
                }
            }

            if (-not $issues.Count -and -not ($sources.Values -contains 'Conflict')) {
                $leaseResult = Join-KronosEvidence $data $sources $leases $dhcpKeys 'DHCP lease export' $leaseFields
                if ($leaseResult -in @('Conflict', 'Ambiguous')) { $issues.Add("DHCP leases: $leaseResult") }
                $reservationKeys = @('IPAddress', 'MACAddress')
                if (-not $issues.Count -and ($data.IPAddress -or $data.MACAddress)) {
                    $reservationResult = Join-KronosEvidence $data $sources $reservations $reservationKeys 'DHCP reservation export' @('IPAddress', 'MACAddress', 'ScopeId')
                    if ($reservationResult -in @('Conflict', 'Ambiguous')) { $issues.Add("DHCP reservations: $reservationResult") }
                }
                # Try inventory again once DHCP has supplied an identity anchor, e.g. MAC -> IP -> clock record.
                if ($inventoryResult -eq 'Unmatched' -and -not $issues.Count) {
                    $inventoryResult = Join-KronosEvidence $data $sources $inventory $identity 'Clock inventory' $inventoryFields
                    if ($inventoryResult -in @('Conflict', 'Ambiguous')) { $issues.Add("Clock inventory: $inventoryResult") }
                }
                $matchingScopes = @($scopes | Where-Object {
                    if ($data.IPAddress) { Test-KronosScope $data.IPAddress $_ }
                    else { $data.ScopeId -and $_.ScopeId -eq $data.ScopeId }
                })
                if ($scopes.Count -and $data.IPAddress -and $data.ScopeId -and
                    -not ($matchingScopes | Where-Object ScopeId -eq $data.ScopeId)) {
                    $issues.Add('Reported DHCP scope does not contain this IPv4 address.')
                }
                if ($matchingScopes.Count -eq 1) {
                    Set-KronosFields $data $sources $matchingScopes[0] 'DHCP scope export'
                } elseif ($matchingScopes.Count -gt 1) {
                    $issues.Add('DHCP scopes: Ambiguous')
                }
            }

            foreach ($field in @($sources.Keys | Sort-Object)) {
                if ($sources[$field] -eq 'Conflict') {
                    $issues.Add("Evidence disagrees on $field.")
                    $data.Remove($field)
                }
            }

            if (-not $issues.Count -and $reservationResult -eq 'Matched') {
                $reservation = 'Reported by export'
            }
            if ($Live -and -not $issues.Count -and $data.IPAddress) {
                if (-not $hasIdentityHint -or ($inventoryResult -ne 'Matched' -and -not $hints.IPAddress)) {
                    $issues.Add('Live check needs a clock inventory match or an explicit assigned IPv4 address.')
                } elseif ($matchingScopes.Count -ne 1 -or
                    -not (Test-KronosScope $data.IPAddress $matchingScopes[0] -UsableHost)) {
                    $issues.Add('IPv4 address is outside the supplied site scopes or is not a usable host address.')
                } elseif (-not $probeCache.ContainsKey($data.IPAddress)) {
                    $probeCache[$data.IPAddress] = Test-KronosResponse $data.IPAddress
                }
                if (-not $issues.Count) { $reachability = $probeCache[$data.IPAddress] }
            }
        }

        $missing = @(@('IPAddress', 'HostName', 'MACAddress', 'SerialNumber', 'SubnetMask') |
            Where-Object { -not $data[$_] })
        $status = if (-not $valid) { 'Invalid input' }
            elseif ($issues.Count) { 'Review evidence' }
            elseif ($missing.Count) { 'Incomplete' }
            else { 'Complete' }
        $result = [ordered]@{ Row = $number; Status = $status; Reachability = $reachability; Reservation = $reservation }
        foreach ($field in ($inventoryFields + @('DHCPState'))) { $result[$field] = $data[$field] }
        $result['Missing'] = $missing -join ', '
        $result['Notes'] = $issues -join ' '
        $result['Sources'] = ($sources.Keys | Sort-Object | ForEach-Object { "$_ = $($sources[$_])" }) -join ' | '
        [pscustomobject]$result
    }
}

Export-ModuleMember -Function Get-KronosBatchReport
