#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CybernetIdentityConfidence {
    param(
        [object]$Row,
        [object]$SubnetMatch
    )

    $hasSerial = -not [string]::IsNullOrWhiteSpace($Row.Serial)
    $hasHostname = -not [string]::IsNullOrWhiteSpace($Row.ExpectedHostname)
    $hasMac = -not [string]::IsNullOrWhiteSpace($Row.ExpectedMAC)
    $hasIp = -not [string]::IsNullOrWhiteSpace($Row.IP)
    $subnetApproved = $SubnetMatch -and $SubnetMatch.Matched -and $SubnetMatch.ApprovedForScan
    $subnetMatched = $SubnetMatch -and $SubnetMatch.Matched
    $isPublic = $SubnetMatch -and $SubnetMatch.IsPublic

    if ($isPublic -or ($hasIp -and $subnetMatched -and -not $subnetApproved)) {
        return 'Blocked'
    }

    if ($hasSerial -and ($hasHostname -or $hasMac) -and $hasIp -and $subnetApproved) {
        return 'Confirmed'
    }

    if ($hasHostname -and $hasIp -and $subnetApproved) {
        return 'High'
    }

    if (($hasMac -or $hasIp) -and $subnetApproved) {
        return 'Medium'
    }

    if ($hasIp -and -not $subnetApproved) {
        return 'Weak'
    }

    if ($hasSerial -and -not $hasHostname -and -not $hasMac -and -not $hasIp) {
        return 'Missing'
    }

    if (-not $hasIp -and -not $hasHostname -and -not $hasMac) {
        return 'Missing'
    }

    return 'Missing'
}

function New-CybernetIdentityMapRows {
    param(
        [object[]]$InventoryRows,
        [object[]]$SubnetMatches
    )

    $rows = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt @($InventoryRows).Count; $i++) {
        $row = $InventoryRows[$i]
        $match = $SubnetMatches[$i]
        $confidence = Get-CybernetIdentityConfidence -Row $row -SubnetMatch $match

        $evidence = $row.Evidence
        if ($match.IsPublic) {
            $evidence = 'Public IP rejected by default'
        } elseif ($match.Matched -and -not $match.ApprovedForScan) {
            $evidence = 'Subnet found but not approved for scan'
        } elseif ($confidence -eq 'Missing') {
            $evidence = 'Serial has no hostname, MAC, IP, or subnet bridge'
        } elseif ([string]::IsNullOrWhiteSpace($evidence)) {
            $evidence = "Classified as $confidence"
        }

        $rows.Add([pscustomobject]@{
            Site             = $row.Site
            Serial           = $row.Serial
            Hostname         = $row.ExpectedHostname
            MAC              = $row.ExpectedMAC
            IP               = $row.IP
            SubnetCandidate  = $match.SubnetCandidate
            SubnetSource     = $match.SubnetSource
            Confidence       = $confidence
            Evidence         = $evidence
        }) | Out-Null
    }

    return $rows.ToArray()
}

function New-CybernetSubnetsToSurveyRows {
    param([object[]]$IdentityMapRows)

    $grouped = $IdentityMapRows |
        Where-Object { $_.SubnetCandidate -and $_.Confidence -in @('Confirmed', 'High', 'Medium') } |
        Group-Object -Property SubnetCandidate

    $output = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($grouped)) {
        $bestConfidence = ($group.Group.Confidence | Sort-Object -Unique)[0]
        $output.Add([pscustomobject]@{
            Site             = ($group.Group | Select-Object -First 1).Site
            Subnet           = $group.Name
            Reason           = "Matched known Cybernet DNS/IP evidence $(@($group.Group).Count) record(s)"
            Confidence       = $bestConfidence
            ApprovedForScan  = 'true'
        }) | Out-Null
    }

    return @($output.ToArray() | Sort-Object Subnet)
}

function New-CybernetTargetIpList {
    param([object[]]$IdentityMapRows)

    $ips = @($IdentityMapRows |
        Where-Object { $_.IP -and $_.Confidence -in @('Confirmed', 'High', 'Medium') } |
        Select-Object -ExpandProperty IP -Unique |
        Sort-Object)

    if (@($ips).Count -eq 0) {
        return @()
    }

    return [string[]]$ips
}

function New-CybernetActionItemsMarkdown {
    param(
        [object[]]$IdentityMapRows,
        [string[]]$DuplicateSerials
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Cybernet Subnet Discovery Action Items') | Out-Null
    $lines.Add('') | Out-Null

    foreach ($serial in @($DuplicateSerials)) {
        $lines.Add("- **Duplicate serial**: Review inventory for serial '$serial' - multiple rows share this identity anchor.") | Out-Null
    }

    foreach ($row in $IdentityMapRows) {
        if ($row.Confidence -eq 'Missing') {
            $lines.Add("- **Missing bridge** [$($row.Serial)]: Add hostname, MAC, or infrastructure export to connect serial to approved subnet scope.") | Out-Null
        }
        if ($row.Confidence -eq 'Blocked') {
            $lines.Add("- **Blocked scope** [$($row.Serial)]: $($row.Evidence). Do not scan until subnet is approved or IP is corrected.") | Out-Null
        }
    }

    if ($lines.Count -le 2) {
        $lines.Add('- No action items. Approved scope is ready for technician review.') | Out-Null
    }

    return ($lines -join [Environment]::NewLine)
}

function New-CybernetDiscoverySummary {
    param(
        [string]$Site,
        [object[]]$IdentityMapRows,
        [object[]]$TargetIps,
        [string[]]$DuplicateSerials,
        [int]$DnsResolvedCount,
        [hashtable]$Extra = @{}
    )

    $IdentityMapRows = @($IdentityMapRows)
    $TargetIps = @($TargetIps)
    $DuplicateSerials = @($DuplicateSerials)

    $confidenceCounts = @{}
    foreach ($level in @('Confirmed', 'High', 'Medium', 'Weak', 'Blocked', 'Missing')) {
        $confidenceCounts[$level] = ($IdentityMapRows | Where-Object { $_.Confidence -eq $level } | Measure-Object).Count
    }

    $summary = [ordered]@{
        site               = $Site
        generatedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
        recordCount        = ($IdentityMapRows | Measure-Object).Count
        targetIpCount      = ($TargetIps | Measure-Object).Count
        duplicateSerials   = @($DuplicateSerials)
        dnsResolvedCount   = $DnsResolvedCount
        confidenceCounts   = $confidenceCounts
        blockedPublicCount = ($IdentityMapRows | Where-Object { $_.Evidence -like '*Public IP*' } | Measure-Object).Count
        blockedSubnetCount = ($IdentityMapRows | Where-Object { $_.Evidence -like '*not approved*' } | Measure-Object).Count
    }

    foreach ($key in $Extra.Keys) {
        $summary[$key] = $Extra[$key]
    }

    return [pscustomobject]$summary
}

function Write-CybernetEvidenceLogEntry {
    param(
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$LogEntries,

        [Parameter(Mandatory = $true)]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [string]$Detail,
        [string]$Command
    )

    $entry = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        stage     = $Stage
        action    = $Action
        detail    = $Detail
    }
    if ($Command) { $entry.command = $Command }

    $LogEntries.Add(($entry | ConvertTo-Json -Compress)) | Out-Null
}

function Export-CybernetSubnetDiscoveryArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutDir,

        [object[]]$NormalizedSerials,
        [object[]]$IdentityMapRows,
        [object[]]$SubnetsToSurveyRows,
        [string[]]$TargetIps,
        [object]$Summary,
        [string]$ActionItemsMarkdown,
        [string[]]$EvidenceLogEntries,

        [switch]$WhatIf
    )

    $files = @{
        NormalizedSerials = Join-Path $OutDir 'CybernetSubnetDiscovery_NormalizedSerials.csv'
        IdentityMap       = Join-Path $OutDir 'CybernetSubnetDiscovery_IdentityMap.csv'
        SubnetsToSurvey   = Join-Path $OutDir 'CybernetSubnetDiscovery_SubnetsToSurvey.csv'
        TargetIPs         = Join-Path $OutDir 'CybernetSubnetDiscovery_TargetIPs.txt'
        Summary           = Join-Path $OutDir 'CybernetSubnetDiscovery_Summary.json'
        ActionItems       = Join-Path $OutDir 'CybernetSubnetDiscovery_ActionItems.md'
        EvidenceLog       = Join-Path $OutDir 'CybernetSubnetDiscovery_EvidenceLog.jsonl'
    }

    if ($WhatIf) {
        return [pscustomobject]@{
            OutDir = $OutDir
            Files  = $files
            WhatIf = $true
        }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    @($NormalizedSerials) | Export-Csv -LiteralPath $files.NormalizedSerials -NoTypeInformation
    @($IdentityMapRows) | Export-Csv -LiteralPath $files.IdentityMap -NoTypeInformation
    if (($SubnetsToSurveyRows | Measure-Object).Count -gt 0) {
        @($SubnetsToSurveyRows) | Export-Csv -LiteralPath $files.SubnetsToSurvey -NoTypeInformation
    } else {
        'Site,Subnet,Reason,Confidence,ApprovedForScan' | Set-Content -LiteralPath $files.SubnetsToSurvey -Encoding UTF8
    }
    if (($TargetIps | Measure-Object).Count -gt 0) {
        @($TargetIps) | Set-Content -LiteralPath $files.TargetIPs -Encoding UTF8
    } else {
        '' | Set-Content -LiteralPath $files.TargetIPs -Encoding UTF8
    }
    ($Summary | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $files.Summary -Encoding UTF8
    $ActionItemsMarkdown | Set-Content -LiteralPath $files.ActionItems -Encoding UTF8
    @($EvidenceLogEntries) | Set-Content -LiteralPath $files.EvidenceLog -Encoding UTF8

    return [pscustomobject]@{
        OutDir = $OutDir
        Files  = $files
        WhatIf = $false
    }
}
