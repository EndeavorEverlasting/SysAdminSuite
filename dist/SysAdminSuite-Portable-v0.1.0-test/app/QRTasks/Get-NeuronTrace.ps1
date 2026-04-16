<#
.SYNOPSIS
    Attempts to infer which neuron is upstream of this Cybernet workstation.

.DESCRIPTION
    Runs locally on a Cybernet workstation and performs a best-effort, read-only
    topology trace:
      1) Capture local NIC, route, and neighbor context.
      2) Capture local COM/serial evidence (Cybernet -> anesthesia/peripherals path).
      3) Identify likely anesthesia workstation peer(s) from local neighbor cache.
      4) Query the anesthesia workstation for NIC + serial topology (WMI/CIM).
      5) If WinRM is available, read its neighbor table and rank likely neurons.

    This script does not make changes to remote systems.

.PARAMETER AnesthesiaHost
    Optional explicit anesthesia workstation host or IP.

.PARAMETER NeuronNamePattern
    Regex used to detect neuron hostnames in reverse DNS or WinRM neighbor data.

.PARAMETER SkipRemote
    Skip querying the anesthesia workstation and only emit local observations.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Designed for PowerShell 5.1+.
#>
param(
    [string]$AnesthesiaHost = '',
    [string]$NeuronNamePattern = '(?i)(neuron|nrn)',
    [int]$RemoteStepTimeoutSec = 25,
    [switch]$ResolveNames,
    [switch]$SkipRemote
)

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path -LiteralPath $_outDir)) {
    New-Item -ItemType Directory -Path $_outDir -Force | Out-Null
}
$outFile = Join-Path $_outDir "NeuronTrace_$($env:COMPUTERNAME).txt"

$script:_phaseTimers = @{}
$script:_phaseElapsedMs = @{}
function Start-PhaseTimer {
    param([string]$Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $script:_phaseTimers[$Name] = $sw
}
function Stop-PhaseTimer {
    param([string]$Name)
    if ($script:_phaseTimers.ContainsKey($Name)) {
        $script:_phaseTimers[$Name].Stop()
        $script:_phaseElapsedMs[$Name] = [int][math]::Round($script:_phaseTimers[$Name].Elapsed.TotalMilliseconds, 0)
    }
}

function Invoke-WithTimeout {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutSec = 25,
        [string]$OperationName = 'Operation'
    )

    if ($TimeoutSec -lt 5) { $TimeoutSec = 5 }

    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    try {
        if (Wait-Job -Job $job -Timeout $TimeoutSec) {
            $data = Receive-Job -Job $job -ErrorAction Stop
            return [PSCustomObject]@{
                Succeeded = $true
                TimedOut = $false
                Data = $data
                ErrorMessage = ''
                Operation = $OperationName
            }
        }

        Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        return [PSCustomObject]@{
            Succeeded = $false
            TimedOut = $true
            Data = @()
            ErrorMessage = "$OperationName timed out after $TimeoutSec second(s)."
            Operation = $OperationName
        }
    } catch {
        return [PSCustomObject]@{
            Succeeded = $false
            TimedOut = $false
            Data = @()
            ErrorMessage = "$OperationName failed: $($_.Exception.Message)"
            Operation = $OperationName
        }
    } finally {
        Remove-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    }
}

function ConvertTo-IPv4Int {
    param([string]$IPv4)
    try {
        $bytes = [System.Net.IPAddress]::Parse($IPv4).GetAddressBytes()
        [array]::Reverse($bytes)
        return [BitConverter]::ToUInt32($bytes, 0)
    } catch {
        return $null
    }
}

function Test-IPv4InCidr {
    param(
        [string]$IPv4,
        [string]$Prefix,
        [int]$PrefixLength
    )
    $ipInt = ConvertTo-IPv4Int -IPv4 $IPv4
    $prefixInt = ConvertTo-IPv4Int -IPv4 $Prefix
    if ($null -eq $ipInt -or $null -eq $prefixInt) { return $false }
    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) { return $false }
    if ($PrefixLength -eq 0) { return $true }
    $mask = ([uint32]0xFFFFFFFF) -shl (32 - $PrefixLength)
    return (($ipInt -band $mask) -eq ($prefixInt -band $mask))
}

function Resolve-HostNameSafe {
    param([string]$Address)
    if (-not $ResolveNames) { return '' }
    try {
        if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
            $dns = Resolve-DnsName -Name $Address -Type PTR -QuickTimeout -ErrorAction Stop | Select-Object -First 1
            if ($dns -and $dns.NameHost) { return $dns.NameHost.TrimEnd('.') }
        }
    } catch {}
    return ''
}

function Get-NeighborCandidates {
    param([string[]]$LocalIPv4List)

    $raw = @()
    try {
        if (Get-Command -Name Get-NetNeighbor -ErrorAction SilentlyContinue) {
            $raw = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -and
                    $_.IPAddress -notmatch '^169\.254\.' -and
                    $_.IPAddress -notmatch '^127\.' -and
                    $_.IPAddress -ne '255.255.255.255' -and
                    $_.State -notin @('Unreachable','Invalid')
                } |
                Select-Object IPAddress, LinkLayerAddress, InterfaceAlias, State
        }
    } catch {}

    if (-not $raw -or $raw.Count -eq 0) {
        try {
            $arpLines = arp -a 2>$null
            foreach ($line in $arpLines) {
                if ($line -match '^\s*(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F\-]{17})\s+(\w+)\s*$') {
                    $raw += [PSCustomObject]@{
                        IPAddress        = $matches[1]
                        LinkLayerAddress = $matches[2]
                        InterfaceAlias   = ''
                        State            = $matches[3]
                    }
                }
            }
        } catch {}
    }

    $exclude = @{}
    foreach ($ip in $LocalIPv4List) { $exclude[$ip] = $true }
    $out = @()
    foreach ($row in $raw) {
        if ($exclude.ContainsKey($row.IPAddress)) { continue }
        $out += [PSCustomObject]@{
            IPAddress        = $row.IPAddress
            LinkLayerAddress = $row.LinkLayerAddress
            InterfaceAlias   = $row.InterfaceAlias
            State            = $row.State
            HostName         = (Resolve-HostNameSafe -Address $row.IPAddress)
        }
    }
    $out | Sort-Object IPAddress -Unique
}

function Get-LocalSerialEvidence {
    $ports = @()
    $serialMap = @()

    try {
        $ports = Get-CimInstance Win32_SerialPort -ErrorAction Stop |
            Select-Object DeviceID, Caption, Description, PNPDeviceID, ProviderType, MaxBaudRate, Status
    } catch {
        $ports = @()
    }

    try {
        $regPath = 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM'
        if (Test-Path -LiteralPath $regPath) {
            $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -in @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')) { continue }
                $serialMap += [PSCustomObject]@{
                    KernelDevice = $p.Name
                    ComPort = "$($p.Value)"
                }
            }
        }
    } catch {}

    $pnpCom = @()
    try {
        $pnpCom = Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.Name -match '\(COM\d+\)' } |
            Select-Object Name, PNPDeviceID, Manufacturer, Status
    } catch {}

    return [PSCustomObject]@{
        SerialPorts = @($ports)
        SerialMap = @($serialMap)
        PnpComDevices = @($pnpCom)
    }
}

# --- Local identity snapshot ---
Start-PhaseTimer -Name 'LocalNetworkSnapshot'
$localNics = @()
try {
    $localNics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop
} catch {
    $localNics = @()
}

$localRows = @()
$localIPv4 = @()
foreach ($nic in $localNics) {
    $ip4 = @($nic.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
    $gw = @($nic.DefaultIPGateway | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
    foreach ($ip in $ip4) {
        $localIPv4 += $ip
        $prefixLen = $null
        $prefix = ''
        if ($nic.IPSubnet) {
            $idx = [array]::IndexOf($nic.IPAddress, $ip)
            if ($idx -ge 0 -and $idx -lt $nic.IPSubnet.Count) {
                $mask = $nic.IPSubnet[$idx]
                if ($mask -match '^\d{1,3}(\.\d{1,3}){3}$') {
                    $maskBytes = [System.Net.IPAddress]::Parse($mask).GetAddressBytes()
                    $bits = 0
                    foreach ($b in $maskBytes) {
                        switch ($b) {
                            255 { $bits += 8 }
                            254 { $bits += 7 }
                            252 { $bits += 6 }
                            248 { $bits += 5 }
                            240 { $bits += 4 }
                            224 { $bits += 3 }
                            192 { $bits += 2 }
                            128 { $bits += 1 }
                            default { }
                        }
                    }
                    $prefixLen = $bits
                    $prefix = "$ip/$prefixLen"
                }
            }
        }

        $localRows += [PSCustomObject]@{
            Description = $nic.Description
            IPv4 = $ip
            Prefix = $prefix
            Gateway = ($gw -join '; ')
            MAC = $nic.MACAddress
            DNS = (($nic.DNSServerSearchOrder | Where-Object { $_ }) -join '; ')
        }
    }
}

$neighborCandidates = Get-NeighborCandidates -LocalIPv4List $localIPv4
Stop-PhaseTimer -Name 'LocalNetworkSnapshot'

Start-PhaseTimer -Name 'LocalSerialEvidence'
$localSerial = Get-LocalSerialEvidence
Stop-PhaseTimer -Name 'LocalSerialEvidence'

# --- Identify likely anesthesia peer ---
Start-PhaseTimer -Name 'AnesthesiaPeerSelection'
$anesCandidates = @()
foreach ($n in $neighborCandidates) {
    $score = 0
    if ($n.HostName -match '(?i)(anes|anesth|anesthesia|workstation|wks)') { $score += 80 }
    if ($n.IPAddress -match '^10\.|^172\.(1[6-9]|2\d|3[0-1])\.|^192\.168\.') { $score += 10 }
    if ($n.LinkLayerAddress) { $score += 5 }
    $anesCandidates += [PSCustomObject]@{
        HostName = $n.HostName
        IPAddress = $n.IPAddress
        MAC = $n.LinkLayerAddress
        Interface = $n.InterfaceAlias
        State = $n.State
        Score = $score
    }
}
$anesCandidates = $anesCandidates | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, HostName, IPAddress

$selectedAnes = $null
if ($AnesthesiaHost) {
    $selectedAnes = $AnesthesiaHost
} elseif ($anesCandidates.Count -gt 0) {
    $best = $anesCandidates[0]
    $selectedAnes = if ($best.HostName) { $best.HostName } else { $best.IPAddress }
}
Stop-PhaseTimer -Name 'AnesthesiaPeerSelection'

# --- Remote anesthesia topology and neighbor sampling ---
Start-PhaseTimer -Name 'RemoteQueries'
$remoteNicRows = @()
$remoteSerialRows = @()
$remoteNeighborRows = @()
$remoteErrors = @()

if (-not $SkipRemote -and $selectedAnes) {
    $remoteNicResult = Invoke-WithTimeout -TimeoutSec $RemoteStepTimeoutSec -OperationName 'Remote NIC WMI query' -ArgumentList @($selectedAnes) -ScriptBlock {
        param([string]$target)
        $rows = @()
        $remoteNics = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $target -Filter "IPEnabled=TRUE" -ErrorAction Stop
        foreach ($rn in $remoteNics) {
            $rnIPv4 = @($rn.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
            foreach ($ip in $rnIPv4) {
                $rows += [PSCustomObject]@{
                    Description = $rn.Description
                    IPv4 = $ip
                    Gateway = (($rn.DefaultIPGateway | Where-Object { $_ }) -join '; ')
                    MAC = $rn.MACAddress
                    DNS = (($rn.DNSServerSearchOrder | Where-Object { $_ }) -join '; ')
                }
            }
        }
        $rows
    }
    if ($remoteNicResult.Succeeded) {
        $remoteNicRows = @($remoteNicResult.Data)
    } else {
        $remoteErrors += "$($remoteNicResult.ErrorMessage) Target=[$selectedAnes]"
    }

    $remoteSerialResult = Invoke-WithTimeout -TimeoutSec $RemoteStepTimeoutSec -OperationName 'Remote SerialPort WMI query' -ArgumentList @($selectedAnes) -ScriptBlock {
        param([string]$target)
        Get-WmiObject -Class Win32_SerialPort -ComputerName $target -ErrorAction Stop |
            Select-Object DeviceID, Caption, Description, PNPDeviceID, ProviderType, MaxBaudRate, Status
    }
    if ($remoteSerialResult.Succeeded) {
        $remoteSerialRows = @($remoteSerialResult.Data)
    } else {
        $remoteErrors += "$($remoteSerialResult.ErrorMessage) Target=[$selectedAnes]"
    }

    $remoteNeighborResult = Invoke-WithTimeout -TimeoutSec $RemoteStepTimeoutSec -OperationName 'Remote neighbor query (WinRM)' -ArgumentList @($selectedAnes) -ScriptBlock {
        param([string]$target)
        Invoke-Command -ComputerName $target -ScriptBlock {
            $items = @()
            if (Get-Command -Name Get-NetNeighbor -ErrorAction SilentlyContinue) {
                $items = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.IPAddress -and
                        $_.IPAddress -notmatch '^169\.254\.' -and
                        $_.IPAddress -notmatch '^127\.' -and
                        $_.State -notin @('Unreachable','Invalid')
                    } |
                    Select-Object IPAddress, LinkLayerAddress, InterfaceAlias, State
            }
            if (-not $items -or $items.Count -eq 0) {
                $arpLines = arp -a 2>$null
                foreach ($line in $arpLines) {
                    if ($line -match '^\s*(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F\-]{17})\s+(\w+)\s*$') {
                        $items += [PSCustomObject]@{
                            IPAddress = $matches[1]
                            LinkLayerAddress = $matches[2]
                            InterfaceAlias = ''
                            State = $matches[3]
                        }
                    }
                }
            }
            $items | Sort-Object IPAddress -Unique
        } -ErrorAction Stop
    }
    if ($remoteNeighborResult.Succeeded) {
        $remoteNeighborRows = @($remoteNeighborResult.Data)
    } else {
        $remoteErrors += "$($remoteNeighborResult.ErrorMessage) Target=[$selectedAnes]"
    }
}
Stop-PhaseTimer -Name 'RemoteQueries'

# --- Score likely neuron candidates ---
Start-PhaseTimer -Name 'NeuronScoring'
$localPrefixes = @()
foreach ($lr in $localRows) {
    if ($lr.Prefix -match '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        $localPrefixes += [PSCustomObject]@{
            Prefix = $matches[1]
            PrefixLength = [int]$matches[2]
        }
    }
}

$neuronCandidates = @()
foreach ($rn in $remoteNeighborRows) {
    $resolvedHost = Resolve-HostNameSafe -Address $rn.IPAddress
    $score = 0
    if ($resolvedHost -match $NeuronNamePattern) { $score += 70 }
    if ($rn.LinkLayerAddress) { $score += 15 }
    if ($rn.State -in @('Reachable','Stale','Delay','Probe')) { $score += 10 }

    $isInLocalSubnet = $false
    foreach ($lp in $localPrefixes) {
        if (Test-IPv4InCidr -IPv4 $rn.IPAddress -Prefix $lp.Prefix -PrefixLength $lp.PrefixLength) {
            $isInLocalSubnet = $true
            break
        }
    }
    if (-not $isInLocalSubnet) { $score += 10 }

    $neuronCandidates += [PSCustomObject]@{
        HostName = $resolvedHost
        IPAddress = $rn.IPAddress
        MAC = $rn.LinkLayerAddress
        Interface = $rn.InterfaceAlias
        State = $rn.State
        Score = $score
    }
}
$neuronCandidates = $neuronCandidates | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, HostName, IPAddress
$topNeuron = if ($neuronCandidates.Count -gt 0) { $neuronCandidates[0] } else { $null }
Stop-PhaseTimer -Name 'NeuronScoring'

# --- Build textual report ---
Start-PhaseTimer -Name 'ReportBuild'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Neuron Trace -- $env:COMPUTERNAME -- $timestamp")
$lines.Add(('=' * 80))
$lines.Add('')
$lines.Add('Goal: infer likely neuron upstream of Cybernet -> Anesthesia chain')
$lines.Add('')

$lines.Add('LOCAL CYBERNET SNAPSHOT')
if ($localRows.Count -gt 0) {
    foreach ($row in $localRows) {
        $lines.Add("  IPv4: $($row.IPv4)  Prefix: $($row.Prefix)")
        $lines.Add("  GW  : $($row.Gateway)")
        $lines.Add("  MAC : $($row.MAC)")
        $lines.Add("  NIC : $($row.Description)")
        $lines.Add('')
    }
} else {
    $lines.Add('  No local IP-enabled adapters were returned.')
    $lines.Add('')
}

$lines.Add('LOCAL COM / SERIAL EVIDENCE (Cybernet physical links)')
if ($localSerial.SerialPorts.Count -gt 0) {
    foreach ($sp in $localSerial.SerialPorts) {
        $lines.Add("  Port=$($sp.DeviceID)  Status=$($sp.Status)  Baud=$($sp.MaxBaudRate)")
        $lines.Add("  Name=$($sp.Caption)")
        $lines.Add("  PNP =$($sp.PNPDeviceID)")
    }
} else {
    $lines.Add('  No Win32_SerialPort devices reported.')
}

if ($localSerial.SerialMap.Count -gt 0) {
    $lines.Add('  SERIALCOMM map:')
    foreach ($sm in $localSerial.SerialMap) {
        $lines.Add("    $($sm.ComPort) <= $($sm.KernelDevice)")
    }
}

if ($localSerial.PnpComDevices.Count -gt 0) {
    $lines.Add('  PnP COM devices:')
    foreach ($pd in ($localSerial.PnpComDevices | Select-Object -First 20)) {
        $lines.Add("    $($pd.Name)  Mfg=$($pd.Manufacturer)  Status=$($pd.Status)")
    }
}
$lines.Add('')

$lines.Add('LIKELY ANESTHESIA PEERS (from local neighbor cache)')
if ($anesCandidates.Count -gt 0) {
    foreach ($c in ($anesCandidates | Select-Object -First 10)) {
        $nameText = if ($c.HostName) { $c.HostName } else { '(no reverse DNS)' }
        $lines.Add("  Score=$($c.Score)  $($c.IPAddress)  Host=$nameText  MAC=$($c.MAC)")
    }
} else {
    $lines.Add('  No neighbor entries found. Run traffic (RDP/ping) to anesthesia first, then rerun.')
}
$lines.Add('')
$lines.Add("SELECTED ANESTHESIA TARGET: $(if ($selectedAnes) { $selectedAnes } else { '(none)' })")
$lines.Add('')

$lines.Add('ANESTHESIA REMOTE NIC TOPOLOGY (WMI)')
if ($remoteNicRows.Count -gt 0) {
    foreach ($r in $remoteNicRows) {
        $lines.Add("  IPv4: $($r.IPv4)  GW: $($r.Gateway)  MAC: $($r.MAC)")
        $lines.Add("  NIC : $($r.Description)")
    }
} else {
    $lines.Add('  No remote NIC data available.')
}
$lines.Add('')

$lines.Add('ANESTHESIA REMOTE COM / SERIAL TOPOLOGY (WMI)')
if ($remoteSerialRows.Count -gt 0) {
    foreach ($sp in $remoteSerialRows) {
        $lines.Add("  Port=$($sp.DeviceID)  Status=$($sp.Status)  Baud=$($sp.MaxBaudRate)")
        $lines.Add("  Name=$($sp.Caption)")
        $lines.Add("  PNP =$($sp.PNPDeviceID)")
    }
} else {
    $lines.Add('  No remote serial-port data available.')
}
$lines.Add('')

$lines.Add('LIKELY NEURON CANDIDATES (from anesthesia neighbor table via WinRM)')
if ($neuronCandidates.Count -gt 0) {
    foreach ($n in ($neuronCandidates | Select-Object -First 10)) {
        $nameText = if ($n.HostName) { $n.HostName } else { '(no reverse DNS)' }
        $lines.Add("  Score=$($n.Score)  $($n.IPAddress)  Host=$nameText  MAC=$($n.MAC)  If=$($n.Interface)  State=$($n.State)")
    }
} else {
    $lines.Add('  No remote neighbor candidates available.')
}
$lines.Add('')

$lines.Add('BEST GUESS')
if ($topNeuron) {
    $nameText = if ($topNeuron.HostName) { $topNeuron.HostName } else { '(no reverse DNS)' }
    $lines.Add("  $($topNeuron.IPAddress)  Host=$nameText  MAC=$($topNeuron.MAC)  Score=$($topNeuron.Score)")
} else {
    $lines.Add('  Unable to determine neuron candidate with current visibility.')
}
$lines.Add('')

if ($remoteErrors.Count -gt 0) {
    $lines.Add('REMOTE QUERY NOTES / ERRORS')
    foreach ($err in $remoteErrors) { $lines.Add("  $err") }
    $lines.Add('')
}

$lines.Add('TIMING (ms)')
foreach ($phase in @('LocalNetworkSnapshot','LocalSerialEvidence','AnesthesiaPeerSelection','RemoteQueries','NeuronScoring')) {
    $ms = if ($script:_phaseElapsedMs.ContainsKey($phase)) { $script:_phaseElapsedMs[$phase] } else { 0 }
    $lines.Add("  $phase : $ms")
}
$lines.Add('')

$lines.Add('SAFETY')
$lines.Add("  Remote step timeout (seconds): $RemoteStepTimeoutSec")
$lines.Add('  Dispatcher-level timeout is available via Invoke-TechTask -TaskTimeoutSec.')
$lines.Add('')

$lines.Add('NEXT STEPS IF EMPTY')
$lines.Add('  1) Ensure Cybernet can resolve/ping anesthesia workstation.')
$lines.Add('  2) Ensure admin access to anesthesia (WMI/DCOM and/or WinRM).')
$lines.Add('  3) Generate anesthesia->neuron traffic (launch app/session), rerun NeuronTrace.')
$lines.Add('')

$lines | Out-File -FilePath $outFile -Encoding UTF8
Stop-PhaseTimer -Name 'ReportBuild'

# Console echo
Write-Host "`n  === Neuron Trace -- $env:COMPUTERNAME ===" -ForegroundColor Cyan
if ($topNeuron) {
    $hn = if ($topNeuron.HostName) { $topNeuron.HostName } else { '(no reverse DNS)' }
    Write-Host "  Best guess neuron: $($topNeuron.IPAddress)  Host=$hn  Score=$($topNeuron.Score)" -ForegroundColor Green
} else {
    Write-Host "  Best guess neuron: none (insufficient data)" -ForegroundColor Yellow
}
if ($selectedAnes) {
    Write-Host "  Anesthesia target: $selectedAnes" -ForegroundColor White
}
Write-Host '  Timers (ms):' -ForegroundColor DarkGray
foreach ($phase in @('LocalNetworkSnapshot','LocalSerialEvidence','AnesthesiaPeerSelection','RemoteQueries','NeuronScoring','ReportBuild')) {
    $ms = if ($script:_phaseElapsedMs.ContainsKey($phase)) { $script:_phaseElapsedMs[$phase] } else { 0 }
    Write-Host ("    {0,-24} {1,6}" -f $phase, $ms) -ForegroundColor DarkGray
}
Write-Host "  Saved to: $outFile" -ForegroundColor Green

# HTML output
Start-PhaseTimer -Name 'HtmlBuild'
$suiteHtmlHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\ConvertTo-SuiteHtml.ps1'
if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $htmlPath = [IO.Path]::ChangeExtension($outFile, '.html')
    $summary = [PSCustomObject]@{
        CybernetHost = $env:COMPUTERNAME
        SelectedAnesthesiaTarget = $selectedAnes
        LocalComPortCount = $localSerial.SerialPorts.Count
        RemoteComPortCount = $remoteSerialRows.Count
        BestGuessNeuronIP = if ($topNeuron) { $topNeuron.IPAddress } else { '' }
        BestGuessNeuronHost = if ($topNeuron) { $topNeuron.HostName } else { '' }
        BestGuessScore = if ($topNeuron) { $topNeuron.Score } else { 0 }
        Timestamp = $timestamp
    }
    $body = @()
    $body += $summary | ConvertTo-Html -Fragment -PreContent '<h2>Summary</h2>'
    if ($anesCandidates.Count -gt 0) {
        $body += ($anesCandidates | Select-Object -First 10) | ConvertTo-Html -Fragment -PreContent '<h2>Likely Anesthesia Peers</h2>'
    }
    if ($remoteNicRows.Count -gt 0) {
        $body += $remoteNicRows | ConvertTo-Html -Fragment -PreContent '<h2>Anesthesia NIC Topology</h2>'
    }
    if ($localSerial.SerialPorts.Count -gt 0) {
        $body += $localSerial.SerialPorts | ConvertTo-Html -Fragment -PreContent '<h2>Local COM / Serial Evidence</h2>'
    }
    if ($remoteSerialRows.Count -gt 0) {
        $body += $remoteSerialRows | ConvertTo-Html -Fragment -PreContent '<h2>Anesthesia COM / Serial Topology</h2>'
    }
    if ($neuronCandidates.Count -gt 0) {
        $body += ($neuronCandidates | Select-Object -First 10) | ConvertTo-Html -Fragment -PreContent '<h2>Likely Neuron Candidates</h2>'
    }
    $timingRows = @()
    foreach ($phase in @('LocalNetworkSnapshot','LocalSerialEvidence','AnesthesiaPeerSelection','RemoteQueries','NeuronScoring','ReportBuild')) {
        $timingRows += [PSCustomObject]@{
            Phase = $phase
            Milliseconds = if ($script:_phaseElapsedMs.ContainsKey($phase)) { $script:_phaseElapsedMs[$phase] } else { 0 }
        }
    }
    $body += $timingRows | ConvertTo-Html -Fragment -PreContent '<h2>Timing (ms)</h2>'
    ($body -join "`n") |
        ConvertTo-SuiteHtml -Title "Neuron Trace - $env:COMPUTERNAME" -Subtitle $env:COMPUTERNAME -OutputPath $htmlPath
}
Stop-PhaseTimer -Name 'HtmlBuild'
