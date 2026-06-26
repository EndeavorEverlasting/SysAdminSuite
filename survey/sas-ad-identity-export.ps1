<#
.SYNOPSIS
  Export read-only Active Directory identity evidence for approved SysAdminSuite targets.
.DESCRIPTION
  Uses bounded AD lookups only. It discovers domain/DC state before querying and classifies blocked,
  ambiguous, missing, stale, disabled, DNS, and permission states instead of collapsing them to pass/fail.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [Parameter(Mandatory=$true)][string]$Output,
  [switch]$SearchDescription,
  [switch]$IncludeComputerOU,
  [switch]$LookupHostnameAsUser,
  [switch]$ResolveDns,
  [int]$StaleDays = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoGuess = Split-Path -Parent $scriptRoot
$targetIntakeModule = Join-Path $repoGuess 'scripts/SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule -PathType Leaf)) {
  throw "Missing shared target intake module: $targetIntakeModule"
}
Import-Module $targetIntakeModule -Force
$repoRoot = Get-SasRepoRoot -StartPath $PSCommandPath

Assert-SasApprovedInputPath -Path $Manifest -RepoRoot $repoRoot -Role 'AD identity manifest' -AllowStaging -AllowGenerated
Assert-SasApprovedOutputPath -Path $Output -RepoRoot $repoRoot -Role 'AD identity output CSV'

$RequiredAdProbeStates = @(
  'AD_CONFIRMED','AD_OBJECT_FOUND_DNS_FOUND','AD_OBJECT_FOUND_DNS_MISSING','AD_OBJECT_FOUND_DNS_MISMATCH',
  'AD_OBJECT_FOUND_STALE','AD_OBJECT_FOUND_DISABLED','AD_OBJECT_FOUND_WRONG_OU','AD_DUPLICATE_CANDIDATES',
  'AD_NOT_FOUND','AD_QUERY_BLOCKED','DOMAIN_CONTEXT_UNKNOWN','DOMAIN_CONTROLLER_UNREACHABLE',
  'PERMISSION_BLOCKED','IMPORTED_STATIC_EVIDENCE','NOT_AD_VERIFIED','NEEDS_OPERATOR_REVIEW'
)

function Test-PermissionError([string]$Message) {
  $Message -match '(?i)access is denied|insufficient|permission|unauthorized|not authorized|privilege'
}

function ConvertTo-LdapEscapedValue([string]$Value) {
  if ($null -eq $Value) { return '' }
  return ($Value -replace '\\','\5c' -replace '\*','\2a' -replace '\(','\28' -replace '\)','\29' -replace "`0",'\00')
}

function ConvertTo-Hashtable($Object) {
  $h = @{}
  foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value }
  return $h
}

function Get-ShortHostname([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return (($Value.Trim() -split '\.')[0] -replace '\$$','').ToUpperInvariant()
}

function Get-FirstValue([hashtable]$Row,[string[]]$Names) {
  foreach ($n in $Names) {
    foreach ($k in $Row.Keys) {
      if ($k -and $k.Trim().ToLowerInvariant() -eq $n.Trim().ToLowerInvariant()) {
        $v = [string]$Row[$k]
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
      }
    }
  }
  return ''
}

function Get-ManifestIdentifier([hashtable]$Row) {
  Get-FirstValue $Row @('target','Target','Identifier','SurveyTargetHint','HostName','Hostname','ComputerName','Cybernet Hostname','Neuron Hostname','Cybernet Serial','Cybernet S/N','Neuron S/N','Neuron Serial','MACAddress','MAC')
}

function Get-IdentifierType([string]$Value) {
  $v = (($Value -as [string]).Trim() -replace '\s+','').ToUpperInvariant()
  if (-not $v) { return 'missing' }
  if ($v -match '^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$') { return 'mac' }
  if ($v -match '^(CYB|WNH|HOST|OPR|PC|WKST|WKS|LAP|DESK|DT|LT)[A-Z0-9._-]*$') { return 'hostname' }
  if ($v -match '[A-Z]' -and $v -match '\d') { return 'serial_or_asset' }
  return 'identifier'
}

function Get-ADComputerCandidates([string]$Identifier,[string]$IdentifierType) {
  if ($IdentifierType -ne 'hostname') { return @() }
  $short = Get-ShortHostname $Identifier
  @($Identifier.Trim(), $short, "$short$") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique -First 4
}

function Get-ComputerOUPath([string]$Dn) {
  if ([string]::IsNullOrWhiteSpace($Dn)) { return '' }
  $p = $Dn -split '(?<!\\),', 2
  if ($p.Count -lt 2) { return '' }
  return $p[1]
}

function Get-LegacyOUWarning([string]$OU) {
  if ([string]::IsNullOrWhiteSpace($OU)) { return '' }
  foreach ($p in @('\_Workstations\Legacy','\_Workstations\Old','FORBIDDEN','LEGACY')) {
    if ($OU -match [regex]::Escape($p)) { return 'Computer OU is forbidden or legacy; operator review required.' }
  }
  if ($OU -notmatch 'Managed_Shared' -and $OU -match 'Workstations') { return 'Computer OU is not under Managed_Shared' }
  return ''
}

function New-EvidenceRow {
  param(
    [string]$Target,
    [string]$IdentifierType,
    [string]$ADHostname = '',
    [string]$DNSHostName = '',
    [string]$ADEnabled = '',
    [string]$DirectoryPath = '',
    [string]$ComputerOU = '',
    [string]$LegacyOUWarning = '',
    [string]$ADUserFound = '',
    [string]$ADUserSamAccountName = '',
    [string]$ADUserStatus = '',
    [string]$ADStatus = '',
    [string]$ADProbeMethod = '',
    [string]$DomainContext = '',
    [string]$DomainControllerStatus = '',
    [string]$PermissionStatus = '',
    [string]$DNSStatus = '',
    [string]$Notes = ''
  )
  [pscustomobject]@{
    Target = $Target
    IdentifierType = $IdentifierType
    ADHostname = $ADHostname
    DNSHostName = $DNSHostName
    ADSerial = ''
    ADMAC = ''
    ADEnabled = $ADEnabled
    DirectoryPath = $DirectoryPath
    ComputerOU = $ComputerOU
    LegacyOUWarning = $LegacyOUWarning
    ADUserFound = $ADUserFound
    ADUserSamAccountName = $ADUserSamAccountName
    ADUserStatus = $ADUserStatus
    ADStatus = $ADStatus
    ADProbeMethod = $ADProbeMethod
    DomainContext = $DomainContext
    DomainControllerStatus = $DomainControllerStatus
    PermissionStatus = $PermissionStatus
    DNSStatus = $DNSStatus
    Notes = $Notes
  }
}

function Get-DomainProbeState {
  $s = [ordered]@{
    DomainContext = 'DOMAIN_CONTEXT_UNKNOWN'
    DomainControllerStatus = 'DOMAIN_CONTROLLER_UNREACHABLE'
    PermissionStatus = 'unknown'
    Notes = ''
  }
  try {
    if (Get-Command Get-ADDomain -ErrorAction SilentlyContinue) {
      $d = Get-ADDomain -ErrorAction Stop
      $s.DomainContext = [string]$d.DNSRoot
    } else {
      $d = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
      $s.DomainContext = [string]$d.Name
    }
    $s.PermissionStatus = 'query_allowed_or_not_yet_tested'
  } catch {
    $m = $_.Exception.Message
    if (Test-PermissionError $m) { $s.PermissionStatus = 'permission_blocked' }
    $s.Notes = $m
    return [pscustomobject]$s
  }
  try {
    if (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue) {
      $dc = Get-ADDomainController -Discover -ErrorAction Stop
      $s.DomainControllerStatus = [string]$dc.HostName
    } else {
      $d = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
      $s.DomainControllerStatus = [string]$d.FindDomainController().Name
    }
  } catch {
    $m = $_.Exception.Message
    if (Test-PermissionError $m) { $s.PermissionStatus = 'permission_blocked' }
    $s.Notes = if ($s.Notes) { "$($s.Notes) | $m" } else { $m }
  }
  return [pscustomobject]$s
}

function New-BlockedEvidenceRow([string]$Target,[string]$IdentifierType,[string]$Status,[string]$Method,[pscustomobject]$DomainState,[string]$Notes) {
  $p = $DomainState.PermissionStatus
  if ($Status -eq 'PERMISSION_BLOCKED') { $p = 'permission_blocked' }
  New-EvidenceRow -Target $Target -IdentifierType $IdentifierType -ADStatus $Status -ADProbeMethod $Method -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $p -Notes $Notes
}

function Resolve-AdDnsState([string]$DNSHostName,[switch]$Enabled) {
  if ([string]::IsNullOrWhiteSpace($DNSHostName)) { return @{ Status='AD_OBJECT_FOUND_DNS_MISSING'; DNSStatus='dns_missing'; Notes='AD object has no DNSHostName value.' } }
  if (-not $Enabled) { return @{ Status='AD_OBJECT_FOUND_DNS_FOUND'; DNSStatus='dns_not_resolved'; Notes='DNSHostName present; forward DNS resolution not requested.' } }
  if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { return @{ Status='AD_OBJECT_FOUND_DNS_FOUND'; DNSStatus='dns_resolution_unavailable'; Notes='Resolve-DnsName unavailable.' } }
  try {
    $a = @(Resolve-DnsName -Name $DNSHostName -Type A -ErrorAction Stop)
    if ($a.Count -gt 0) { return @{ Status='AD_OBJECT_FOUND_DNS_FOUND'; DNSStatus='dns_found'; Notes='Forward DNS resolves.' } }
    return @{ Status='AD_OBJECT_FOUND_DNS_MISSING'; DNSStatus='dns_missing'; Notes='Forward DNS returned no A records.' }
  } catch {
    return @{ Status='AD_OBJECT_FOUND_DNS_MISSING'; DNSStatus='dns_missing'; Notes=$_.Exception.Message }
  }
}

function Convert-ADComputerToEvidenceRow($Computer,[string]$Target,[string]$IdentifierType,[string]$Method,[pscustomobject]$DomainState,[switch]$DoDnsResolve,[int]$StaleAfterDays) {
  $enabled = if ($null -ne $Computer.Enabled) { [bool]$Computer.Enabled } else { $true }
  $dns = Resolve-AdDnsState ([string]$Computer.DNSHostName) -Enabled:$DoDnsResolve
  $status = [string]$dns.Status
  if (-not $enabled) {
    $status = 'AD_OBJECT_FOUND_DISABLED'
  } elseif ($null -ne $Computer.whenChanged -and ((Get-Date) - [datetime]$Computer.whenChanged).Days -gt $StaleAfterDays) {
    $status = 'AD_OBJECT_FOUND_STALE'
  }
  $notes = "whenChanged={0} | {1}" -f $Computer.whenChanged, $dns.Notes
  New-EvidenceRow -Target $Target -IdentifierType $IdentifierType -ADHostname ([string]$Computer.Name) -DNSHostName ([string]$Computer.DNSHostName) -ADEnabled ([string]$enabled) -DirectoryPath ([string]$Computer.DistinguishedName) -ADStatus $status -ADProbeMethod $Method -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -DNSStatus ([string]$dns.DNSStatus) -Notes $notes
}

function Find-WithADModule([string]$Identifier,[string]$IdentifierType,[switch]$AllowDescriptionSearch,[pscustomobject]$DomainState,[switch]$DoDnsResolve,[int]$StaleAfterDays) {
  $props = @('Enabled','DistinguishedName','DNSHostName','Description','Name','whenChanged')
  $matches = @()
  foreach ($c in Get-ADComputerCandidates $Identifier $IdentifierType) {
    try {
      $matches += Get-ADComputer -Identity $c -Properties $props -ErrorAction Stop
    } catch {
      $m = $_.Exception.Message
      if (Test-PermissionError $m) { return New-BlockedEvidenceRow $Identifier $IdentifierType 'PERMISSION_BLOCKED' 'active_directory_module_identity' $DomainState $m }
    }
  }
  if ($matches.Count -eq 0) {
    $clauses = @()
    foreach ($c in Get-ADComputerCandidates $Identifier $IdentifierType) {
      $safe = ConvertTo-LdapEscapedValue $c
      if ($safe) {
        $clauses += "(name=$safe)"
        $clauses += "(dNSHostName=$safe)"
      }
    }
    if ($AllowDescriptionSearch) {
      $safe = ConvertTo-LdapEscapedValue $Identifier
      if ($safe) { $clauses += "(description=$safe)" }
    }
    if ($clauses.Count -gt 0) {
      $filter = if ($clauses.Count -eq 1) { $clauses[0] } else { "(|$($clauses -join ''))" }
      try {
        $matches = @(Get-ADComputer -LDAPFilter $filter -Properties $props -ResultSetSize 10 -ErrorAction Stop)
      } catch {
        $m = $_.Exception.Message
        $st = if (Test-PermissionError $m) { 'PERMISSION_BLOCKED' } else { 'AD_QUERY_BLOCKED' }
        return New-BlockedEvidenceRow $Identifier $IdentifierType $st 'active_directory_module_exact_filter' $DomainState $m
      }
    }
  }
  $u = @{}
  foreach ($x in $matches) {
    if ($x.DistinguishedName -and -not $u.ContainsKey([string]$x.DistinguishedName)) { $u[[string]$x.DistinguishedName] = $x }
  }
  $d = @($u.Values)
  if ($d.Count -eq 1) { return Convert-ADComputerToEvidenceRow $d[0] $Identifier $IdentifierType 'active_directory_module_bounded_lookup' $DomainState -DoDnsResolve:$DoDnsResolve -StaleAfterDays $StaleAfterDays }
  if ($d.Count -gt 1) { return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_DUPLICATE_CANDIDATES' -ADProbeMethod 'active_directory_module_bounded_lookup' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes ("Multiple candidate AD computer objects found: {0}" -f (($d | Select-Object -ExpandProperty Name) -join ';')) }
  New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_NOT_FOUND' -ADProbeMethod 'active_directory_module_bounded_lookup' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes 'No matching AD computer object found with bounded candidate lookup.'
}

function Find-WithDsquery([string]$Identifier,[string]$IdentifierType,[pscustomobject]$DomainState) {
  if ($IdentifierType -ne 'hostname') { return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'NOT_AD_VERIFIED' -ADProbeMethod 'dsquery_hostname_only' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes 'dsquery fallback supports exact hostname lookup only.' }
  try {
    $raw = & dsquery.exe computer -name (Get-ShortHostname $Identifier) 2>&1
    if ($LASTEXITCODE -eq 0 -and $raw) {
      $lines = @($raw | Where-Object { $_ -and $_.ToString().Trim() })
      if ($lines.Count -gt 1) { return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_DUPLICATE_CANDIDATES' -ADProbeMethod 'dsquery_computer_exact_name' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes ($lines -join ';') }
      $host = if ($lines[0] -match '^"?CN=([^,"]+)') { $matches[1] } else { '' }
      return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADHostname $host -DirectoryPath ([string]$lines[0]) -ADStatus 'NOT_AD_VERIFIED' -ADProbeMethod 'dsquery_computer_exact_name' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes 'Resolved through dsquery fallback; DNS/enabled/stale fields unavailable.'
    }
    New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_NOT_FOUND' -ADProbeMethod 'dsquery_computer_exact_name' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes (($raw | Out-String).Trim())
  } catch {
    $m = $_.Exception.Message
    $st = if (Test-PermissionError $m) { 'PERMISSION_BLOCKED' } else { 'AD_QUERY_BLOCKED' }
    New-BlockedEvidenceRow $Identifier $IdentifierType $st 'dsquery_computer_exact_name' $DomainState $m
  }
}

function Expand-EvidenceRow([pscustomobject]$Row,[string]$Identifier,[switch]$WantComputerOU,[switch]$WantUserLookup) {
  $ou = ''
  $warn = ''
  $status = $Row.ADStatus
  $notes = $Row.Notes
  if ($WantComputerOU -and $Row.DirectoryPath) {
    $ou = Get-ComputerOUPath $Row.DirectoryPath
    $warn = Get-LegacyOUWarning $ou
    if ($warn) { $status = 'AD_OBJECT_FOUND_WRONG_OU' }
  }
  if ($WantUserLookup) {
    $notes = if ($notes) { "$notes | AD user lookup intentionally not run in this bounded probe." } else { 'AD user lookup intentionally not run in this bounded probe.' }
  }
  New-EvidenceRow -Target $Row.Target -IdentifierType $Row.IdentifierType -ADHostname $Row.ADHostname -DNSHostName $Row.DNSHostName -ADEnabled $Row.ADEnabled -DirectoryPath $Row.DirectoryPath -ComputerOU $ou -LegacyOUWarning $warn -ADStatus $status -ADProbeMethod $Row.ADProbeMethod -DomainContext $Row.DomainContext -DomainControllerStatus $Row.DomainControllerStatus -PermissionStatus $Row.PermissionStatus -DNSStatus $Row.DNSStatus -Notes $notes
}

function Write-AdProbeStateSummary([object[]]$Results,[pscustomobject]$DomainState,[string]$QueryMode,[string]$FallbackMode,[string]$OutputPath,[string]$SummaryPath) {
  $counts = @{}
  foreach ($s in $RequiredAdProbeStates) { $counts[$s] = 0 }
  foreach ($r in $Results) {
    $s = [string]$r.ADStatus
    if (-not $counts.ContainsKey($s)) { $counts[$s] = 0 }
    $counts[$s]++
  }
  $found = $counts['AD_CONFIRMED'] + $counts['AD_OBJECT_FOUND_DNS_FOUND'] + $counts['AD_OBJECT_FOUND_DNS_MISSING'] + $counts['AD_OBJECT_FOUND_DNS_MISMATCH'] + $counts['AD_OBJECT_FOUND_STALE'] + $counts['AD_OBJECT_FOUND_DISABLED'] + $counts['AD_OBJECT_FOUND_WRONG_OU'] + $counts['NOT_AD_VERIFIED']
  $blocked = $counts['AD_QUERY_BLOCKED'] + $counts['DOMAIN_CONTEXT_UNKNOWN'] + $counts['DOMAIN_CONTROLLER_UNREACHABLE'] + $counts['PERMISSION_BLOCKED']
  $dnsEnriched = @($Results | Where-Object { $_.DNSStatus }).Count
  Write-Host 'AD PROBE STATE SUMMARY:'
  Write-Host ("- Query mode used: {0}" -f $QueryMode)
  Write-Host ("- Fallback mode used: {0}" -f $FallbackMode)
  Write-Host ("- Domain context: {0}" -f $DomainState.DomainContext)
  Write-Host ("- Domain controller status: {0}" -f $DomainState.DomainControllerStatus)
  Write-Host ("- Permission status: {0}" -f $DomainState.PermissionStatus)
  Write-Host ("- Input target count: {0}" -f $Results.Count)
  Write-Host ("- AD objects found: {0}" -f $found)
  Write-Host ("- DNS enriched: {0}" -f $dnsEnriched)
  Write-Host ("- Stale objects: {0}" -f $counts['AD_OBJECT_FOUND_STALE'])
  Write-Host ("- Disabled objects: {0}" -f $counts['AD_OBJECT_FOUND_DISABLED'])
  Write-Host ("- Duplicate candidates: {0}" -f $counts['AD_DUPLICATE_CANDIDATES'])
  Write-Host ("- Not found: {0}" -f $counts['AD_NOT_FOUND'])
  Write-Host ("- Blocked / unknown: {0}" -f $blocked)
  Write-Host ("- Needs operator review: {0}" -f ($counts['NEEDS_OPERATOR_REVIEW'] + $counts['AD_DUPLICATE_CANDIDATES'] + $counts['AD_OBJECT_FOUND_WRONG_OU']))
  Write-Host ("- Local ignored log path: {0}" -f $SummaryPath)
  Write-Host '- Evidence committed: none, or sanitized fixture only'
  [ordered]@{
    query_mode_used = $QueryMode
    fallback_mode_used = $FallbackMode
    domain_context = $DomainState.DomainContext
    domain_controller_status = $DomainState.DomainControllerStatus
    permission_status = $DomainState.PermissionStatus
    input_target_count = $Results.Count
    ad_objects_found = $found
    dns_enriched = $dnsEnriched
    stale_objects = $counts['AD_OBJECT_FOUND_STALE']
    disabled_objects = $counts['AD_OBJECT_FOUND_DISABLED']
    duplicate_candidates = $counts['AD_DUPLICATE_CANDIDATES']
    not_found = $counts['AD_NOT_FOUND']
    blocked_unknown = $blocked
    needs_operator_review = ($counts['NEEDS_OPERATOR_REVIEW'] + $counts['AD_DUPLICATE_CANDIDATES'] + $counts['AD_OBJECT_FOUND_WRONG_OU'])
    output_path = $OutputPath
    evidence_committed = 'none; local operator evidence only'
    counts_by_state = $counts
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$manifestRows = Import-Csv -LiteralPath $Manifest
$hasADModule = $null -ne (Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1)
$hasDsquery = $null -ne (Get-Command dsquery.exe -ErrorAction SilentlyContinue)
$domainState = Get-DomainProbeState
$queryMode = if ($hasADModule) { 'active_directory_module_bounded_lookup' } elseif ($hasDsquery) { 'dsquery_exact_hostname_fallback' } else { 'no_live_ad_tooling_available' }
$fallbackMode = if ($hasADModule) { 'none' } elseif ($hasDsquery) { 'dsquery' } else { 'operator_manifest_required' }

$results = foreach ($raw in $manifestRows) {
  $row = ConvertTo-Hashtable $raw
  $id = Get-ManifestIdentifier $row
  $type = Get-IdentifierType $id
  if ([string]::IsNullOrWhiteSpace($id)) {
    New-EvidenceRow -Target '' -IdentifierType 'missing' -ADStatus 'NEEDS_OPERATOR_REVIEW' -ADProbeMethod 'none' -DomainContext $domainState.DomainContext -DomainControllerStatus $domainState.DomainControllerStatus -PermissionStatus $domainState.PermissionStatus -Notes 'Manifest row did not contain an identifier.'
    continue
  }
  if ($domainState.PermissionStatus -eq 'permission_blocked') {
    $e = New-BlockedEvidenceRow $id $type 'PERMISSION_BLOCKED' 'domain_discovery' $domainState $domainState.Notes
  } elseif ($domainState.DomainContext -eq 'DOMAIN_CONTEXT_UNKNOWN') {
    $e = New-BlockedEvidenceRow $id $type 'DOMAIN_CONTEXT_UNKNOWN' 'domain_discovery' $domainState 'Domain context could not be determined; run from a domain-joined or RSAT-equipped operator workstation.'
  } elseif ($domainState.DomainControllerStatus -eq 'DOMAIN_CONTROLLER_UNREACHABLE') {
    $e = New-BlockedEvidenceRow $id $type 'DOMAIN_CONTROLLER_UNREACHABLE' 'domain_controller_discovery' $domainState 'Domain context exists but no reachable domain controller was discovered.'
  } elseif ($hasADModule) {
    $e = Find-WithADModule $id $type -AllowDescriptionSearch:$SearchDescription -DomainState $domainState -DoDnsResolve:$ResolveDns -StaleAfterDays $StaleDays
  } elseif ($hasDsquery) {
    $e = Find-WithDsquery $id $type $domainState
  } else {
    $e = New-BlockedEvidenceRow $id $type 'AD_QUERY_BLOCKED' 'none' $domainState 'Neither ActiveDirectory PowerShell module nor dsquery.exe is available in this runtime.'
  }
  if ($IncludeComputerOU -or $LookupHostnameAsUser) {
    Expand-EvidenceRow $e $id -WantComputerOU:$IncludeComputerOU -WantUserLookup:$LookupHostnameAsUser
  } else {
    $e
  }
}

$results | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
$summaryPath = [System.IO.Path]::ChangeExtension($Output, '.summary.json')
Write-AdProbeStateSummary -Results @($results) -DomainState $domainState -QueryMode $queryMode -FallbackMode $fallbackMode -OutputPath $Output -SummaryPath $summaryPath
Write-Host ("AD identity evidence written: {0}" -f $Output)
