#Requires -Version 5.1
<#
.SYNOPSIS
  Cybernet subnet discovery — serial inventory to approved scanner scope.

.DESCRIPTION
  Imports Cybernet serial inventory, normalizes identity fields, optionally resolves DNS,
  maps IPs to approved site subnets, and emits technician-readable artifacts plus
  deterministic Naabu/Nmap command strings (recorded only, never executed).

.EXAMPLE
  .\Invoke-SASCybernetSubnetDiscovery.ps1 `
    -Site "SSUH" `
    -SerialInventoryPath ".\input\cybernet-serials.example.csv" `
    -SiteSubnetsPath ".\input\site-subnets.example.csv" `
    -UseDns `
    -GenerateSurveyTargets `
    -OutDir ".\evidence\CybernetSubnetDiscovery\SSUH"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Site,

    [Parameter(Mandatory = $true)]
    [string]$SerialInventoryPath,

    [Parameter(Mandatory = $true)]
    [string]$SiteSubnetsPath,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$KnownHostsPath,
    [string]$KnownMacsPath,
    [string]$ApprovedSubnetsPath,
    [string]$DnsSuffix,

    [switch]$UseDns,
    [switch]$GenerateSurveyTargets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)

. (Join-Path $moduleRoot 'Import-CybernetSerialInventory.ps1')
. (Join-Path $moduleRoot 'Convert-IpToSubnetCandidate.ps1')
. (Join-Path $moduleRoot 'Resolve-CybernetDnsIdentity.ps1')
. (Join-Path $moduleRoot 'New-CybernetSubnetDiscoveryReport.ps1')

$rulesPath = Join-Path $repoRoot 'Config/cybernet-subnet-rules.json'
$portProfilePath = Join-Path $repoRoot 'Config/cybernet-port-profile.json'
$rules = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json
$requireApprovedSubnet = [bool]$rules.subnetInference.requireApprovedSubnet
$whatIfMode = [bool]$WhatIfPreference

$evidenceLog = New-Object System.Collections.Generic.List[string]
Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'Start' -Action 'InvokeDiscovery' -Detail "Site=$Site OutDir=$OutDir"

$importResult = Import-CybernetSerialInventory -Path $SerialInventoryPath -Site $Site
$inventory = @($importResult.Rows)
Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'Import' -Action 'SerialInventory' -Detail "Imported $(@($inventory).Count) row(s); duplicates=$(@($importResult.DuplicateSerials).Count)"

$inventory = Merge-CybernetKnownData -InventoryRows $inventory -KnownHostsPath $KnownHostsPath -KnownMacsPath $KnownMacsPath

$siteSubnets = Import-CybernetSiteSubnets -Path $SiteSubnetsPath -Site $Site
if ($ApprovedSubnetsPath) {
    $jsonSubnets = Import-CybernetApprovedSubnetsJson -Path $ApprovedSubnetsPath -Site $Site
    $siteSubnets = @($siteSubnets + $jsonSubnets)
}
Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'Import' -Action 'SiteSubnets' -Detail "Loaded $(@($siteSubnets).Count) subnet row(s)"

$dnsResolvedCount = 0
if ($UseDns) {
    $beforeIps = @($inventory | Where-Object { $_.IP } | Measure-Object).Count
    $inventory = Apply-CybernetDnsToInventory -InventoryRows $inventory -DnsSuffix $DnsSuffix
    $afterIps = @($inventory | Where-Object { $_.IP } | Measure-Object).Count
    $dnsResolvedCount = $afterIps - $beforeIps
    Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'DNS' -Action 'ForwardResolve' -Detail "Resolved $dnsResolvedCount new IP(s)"
}

$subnetMatches = New-Object System.Collections.Generic.List[object]
foreach ($row in $inventory) {
    $match = Convert-IpToSubnetCandidate -IPv4 $row.IP -ApprovedSubnets $siteSubnets -RequireApprovedSubnet $requireApprovedSubnet
    $subnetMatches.Add($match) | Out-Null

    if ($match.IsPublic) {
        Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'Safety' -Action 'RejectPublicIp' -Detail "Serial=$($row.Serial) IP=$($row.IP)"
    } elseif ($match.Matched -and -not $match.ApprovedForScan) {
        Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'Safety' -Action 'RejectUnapprovedSubnet' -Detail "Serial=$($row.Serial) IP=$($row.IP) Subnet=$($match.SubnetCandidate)"
    }
}

$identityMap = New-CybernetIdentityMapRows -InventoryRows $inventory -SubnetMatches $subnetMatches.ToArray()
$subnetsToSurvey = New-CybernetSubnetsToSurveyRows -IdentityMapRows $identityMap
$targetIps = New-CybernetTargetIpList -IdentityMapRows $identityMap
$actionItems = New-CybernetActionItemsMarkdown -IdentityMapRows $identityMap -DuplicateSerials $importResult.DuplicateSerials

$scannerCommands = @()
if ($GenerateSurveyTargets -and @($targetIps).Count -gt 0) {
    . (Join-Path $repoRoot 'modules/CybernetSurvey/New-CybernetScannerCommand.ps1')
    $targetFile = Join-Path $OutDir 'CybernetSubnetDiscovery_TargetIPs.txt'
    $surveyOutDir = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $OutDir)) 'CybernetSurvey') $Site
    $scannerCommands = New-CybernetScannerCommands -TargetFile $targetFile -SurveyOutDir $surveyOutDir -PortProfilePath $portProfilePath
    foreach ($cmd in $scannerCommands) {
        Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'ScannerHandoff' -Action 'GenerateCommand' -Detail "$($cmd.Scanner) command prepared (not executed)" -Command $cmd.Command
    }
}

$summary = New-CybernetDiscoverySummary -Site $Site -IdentityMapRows $identityMap -TargetIps $targetIps -DuplicateSerials $importResult.DuplicateSerials -DnsResolvedCount $dnsResolvedCount -Extra @{
    scannerCommandsGenerated = @($scannerCommands).Count
    whatIf                   = $whatIfMode
}

$normalizedSerials = foreach ($row in $identityMap) {
    [pscustomobject]@{
        Site             = $row.Site
        Serial           = $row.Serial
        ExpectedHostname = $row.Hostname
        ExpectedMAC      = $row.MAC
        IP               = $row.IP
        SubnetCandidate  = $row.SubnetCandidate
        Confidence       = $row.Confidence
    }
}

Write-CybernetEvidenceLogEntry -LogEntries $evidenceLog -Stage 'Complete' -Action 'ExportArtifacts' -Detail "WhatIf=$whatIfMode"

$result = Export-CybernetSubnetDiscoveryArtifacts `
    -OutDir $OutDir `
    -NormalizedSerials @($normalizedSerials) `
    -IdentityMapRows $identityMap `
    -SubnetsToSurveyRows $subnetsToSurvey `
    -TargetIps $targetIps `
    -Summary $summary `
    -ActionItemsMarkdown $actionItems `
    -EvidenceLogEntries $evidenceLog.ToArray() `
    -WhatIf:$whatIfMode

Write-Output $summary
return $result
