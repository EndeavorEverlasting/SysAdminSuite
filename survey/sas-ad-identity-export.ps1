<#
.SYNOPSIS
  Export read-only Active Directory identity evidence for approved SysAdminSuite targets.
.DESCRIPTION
  Uses bounded AD lookups only. It discovers domain/DC state before querying and classifies blocked,
  ambiguous, missing, stale, disabled, DNS, and permission states instead of collapsing them to pass/fail.

  Hostname variance is handled as bounded doctrine candidate generation, not generic fuzzy search.
  Variant matches are candidate discovery only and remain serial_unverified until a privileged identity
  source proves the physical device identity.
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

$HostnameVariantStatusTokens = @(
  'ad_exact_match','ad_variant_match','ad_prefix_variant_match','ad_known_prefix_substitution',
  'ad_prefix_site_mismatch','ad_number_transposition_candidate','ad_letter_transposition_candidate',
  'serial_unverified','needs_site_context_review','needs_privileged_identity','not_found_in_ad',
  'wildcard_prefix_review_only'
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

function Get-CompactHostname([string]$Value) {
  $short = Get-ShortHostname $Value
  if ([string]::IsNullOrWhiteSpace($short)) { return '' }
  return ($short -replace '[-_\s]','').ToUpperInvariant()
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
  Get-FirstValue $Row @('target','Target','Identifier','SurveyTargetHint','HostName','Hostname','ComputerName','ExpectedHostname','Cybernet Hostname','Neuron Hostname','Cybernet Serial','Cybernet S/N','Neuron S/N','Neuron Serial','MACAddress','MAC')
}

function Get-ManifestSite([hashtable]$Row) {
  Get-FirstValue $Row @('Site','Facility','Location','Hospital','SourceSite')
}

function Get-IdentifierType([string]$Value) {
  $v = (($Value -as [string]).Trim() -replace '\s+','').ToUpperInvariant()
  if (-not $v) { return 'missing' }
  if ($v -match '^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$') { return 'mac' }
  if ($v -match '^(CYB|WNH|WMH|HOST|OPR|PC|WKST|WKS|LAP|DESK|DT|LT)[A-Z0-9._-]*$') { return 'hostname' }
  if ($v -match '[A-Z]' -and $v -match '\d') { return 'serial_or_asset' }
  return 'identifier'
}

function Get-SitePrefixDisposition([string]$Candidate,[string]$Site) {
  $prefix = (Get-CompactHostname $Candidate)
  if ($prefix.Length -ge 3) { $prefix = $prefix.Substring(0,3) }
  $siteText = if ($Site) { $Site.Trim() } else { '' }
  $status = 'ad_known_prefix_substitution'
  $confidence = 'medium'
  $reviewRequired = $false
  $notes = 'known WNH/WMH substitution; verify against Site before trusting.'

  if ([string]::IsNullOrWhiteSpace($siteText)) {
    return @{ Status='needs_site_context_review'; Confidence='low'; ReviewRequired=$true; Notes='Site is missing; prefix substitution requires operator review.' }
  }

  $lijLike = $siteText -match '(?i)\bLIJ\b|Long Island Jewish|Forest Hills|Valley Stream|Cohen'
  $nsuhLike = $siteText -match '(?i)\bNSUH\b|North Shore|Manhasset|Marcus'

  if (($prefix -eq 'WNH' -and $lijLike) -or ($prefix -eq 'WMH' -and $nsuhLike)) {
    return @{ Status=$status; Confidence=$confidence; ReviewRequired=$false; Notes=$notes }
  }

  return @{ Status='ad_prefix_site_mismatch'; Confidence='low'; ReviewRequired=$true; Notes='Substituted prefix conflicts with available site context; needs_site_context_review.' }
}

function Get-AdjacentNumericTranspositions([string]$CompactHostname) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($CompactHostname, '\d+')) {
    $block = [string]$m.Value
    if ($block.Length -lt 2) { continue }
    for ($i = 0; $i -lt ($block.Length - 1); $i++) {
      $chars = $block.ToCharArray()
      $tmp = $chars[$i]
      $chars[$i] = $chars[$i + 1]
      $chars[$i + 1] = $tmp
      $swapped = -join $chars
      if ($swapped -ne $block) {
        $candidate = $CompactHostname.Substring(0,$m.Index) + $swapped + $CompactHostname.Substring($m.Index + $m.Length)
        $out.Add($candidate) | Out-Null
      }
    }
  }
  $out | Select-Object -Unique
}

function Get-PrefixLetterTranspositions([string]$CompactHostname) {
  if ($CompactHostname.Length -lt 4) { return @() }
  $prefix = $CompactHostname.Substring(0,3)
  if ($prefix -notmatch '^[A-Z]{3}$') { return @() }
  $suffix = $CompactHostname.Substring(3)
  $c = $prefix.ToCharArray()
  @(
    "$($c[0])$($c[2])$($c[1])$suffix",
    "$($c[1])$($c[0])$($c[2])$suffix",
    "$($c[1])$($c[2])$($c[0])$suffix",
    "$($c[2])$($c[0])$($c[1])$suffix",
    "$($c[2])$($c[1])$($c[0])$suffix"
  ) | Where-Object { $_ -ne $CompactHostname } | Select-Object -Unique
}

function Get-ADComputerCandidateRecords([string]$Identifier,[string]$IdentifierType,[string]$Site) {
  if ($IdentifierType -ne 'hostname') { return @() }

  $records = New-Object System.Collections.Generic.List[object]
  $seen = @{}

  function Add-CandidateRecord {
    param(
      [string]$Candidate,
      [string]$VariantClass,
      [string]$Confidence,
      [string]$CandidateStatus,
      [bool]$SearchAllowed,
      [bool]$ReviewRequired,
      [string]$Notes
    )
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return }
    $value = $Candidate.Trim().ToUpperInvariant()
    $key = "{0}|{1}" -f $value, $VariantClass
    if ($seen.ContainsKey($key)) { return }
    $seen[$key] = $true
    $records.Add([pscustomobject]@{
      Candidate = $value
      VariantClass = $VariantClass
      Confidence = $Confidence
      CandidateStatus = $CandidateStatus
      SearchAllowed = $SearchAllowed
      ReviewRequired = $ReviewRequired
      Notes = $Notes
    }) | Out-Null
  }

  $short = Get-ShortHostname $Identifier
  $compact = Get-CompactHostname $Identifier
  if ([string]::IsNullOrWhiteSpace($compact)) { return @() }

  Add-CandidateRecord -Candidate $short -VariantClass 'exact_hostname' -Confidence 'highest' -CandidateStatus 'ad_exact_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Exact manifest hostname candidate.'
  Add-CandidateRecord -Candidate $compact -VariantClass 'separator_only_variant' -Confidence 'high' -CandidateStatus 'ad_variant_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Separator-only normalized hostname candidate.'
  Add-CandidateRecord -Candidate "$compact$" -VariantClass 'sam_account_name' -Confidence 'highest' -CandidateStatus 'ad_exact_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Computer sAMAccountName candidate.'

  if ($compact -match '^([A-Z]{3})(\d+)([A-Z]+)(\d+)$') {
    Add-CandidateRecord -Candidate ("{0}-{1}-{2}-{3}" -f $matches[1],$matches[2],$matches[3],$matches[4]) -VariantClass 'separator_only_variant' -Confidence 'high' -CandidateStatus 'ad_variant_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Separator-only dashed hostname candidate.'
    Add-CandidateRecord -Candidate ("{0}{1}-{2}{3}" -f $matches[1],$matches[2],$matches[3],$matches[4]) -VariantClass 'separator_only_variant' -Confidence 'high' -CandidateStatus 'ad_variant_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Separator-only partial-dash hostname candidate.'
  }

  if ($compact -match '(OPR|0PR|O0R|OP0R)') {
    $chars = $compact.ToCharArray()
    $added = 0
    for ($i = 0; $i -lt $chars.Length -and $added -lt 8; $i++) {
      if ($chars[$i] -eq 'O' -or $chars[$i] -eq '0') {
        $copy = $compact.ToCharArray()
        $copy[$i] = if ($copy[$i] -eq 'O') { '0' } else { 'O' }
        $candidate = -join $copy
        Add-CandidateRecord -Candidate $candidate -VariantClass 'o0_swap_variant' -Confidence 'medium-high' -CandidateStatus 'ad_variant_match' -SearchAllowed $true -ReviewRequired $false -Notes 'O/0 swap in OPR-like hostname segment.'
        $added++
      }
    }
  }

  if ($compact -match '^(.+?)(\d+)$') {
    $head = $matches[1]
    $suffix = $matches[2]
    if ($suffix.Length -gt 1 -and $suffix.StartsWith('0')) {
      Add-CandidateRecord -Candidate ($head + $suffix.Substring(1)) -VariantClass 'zero_count_drift' -Confidence 'medium' -CandidateStatus 'ad_variant_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Missing leading zero in numeric suffix.'
    }
    Add-CandidateRecord -Candidate ($head + '0' + $suffix) -VariantClass 'zero_count_drift' -Confidence 'medium' -CandidateStatus 'ad_variant_match' -SearchAllowed $true -ReviewRequired $false -Notes 'Extra leading zero in numeric suffix.'
  }

  if ($compact.StartsWith('WNH') -or $compact.StartsWith('WMH')) {
    $sub = if ($compact.StartsWith('WNH')) { 'WMH' + $compact.Substring(3) } else { 'WNH' + $compact.Substring(3) }
    $siteDisposition = Get-SitePrefixDisposition -Candidate $sub -Site $Site
    Add-CandidateRecord -Candidate $sub -VariantClass 'known_wnh_wmh_substitution' -Confidence $siteDisposition.Confidence -CandidateStatus $siteDisposition.Status -SearchAllowed $true -ReviewRequired $siteDisposition.ReviewRequired -Notes $siteDisposition.Notes
  }

  foreach ($candidate in Get-PrefixLetterTranspositions $compact) {
    Add-CandidateRecord -Candidate $candidate -VariantClass 'prefix_letter_transposition' -Confidence 'low' -CandidateStatus 'ad_letter_transposition_candidate' -SearchAllowed $true -ReviewRequired $true -Notes 'Prefix-letter transposition; candidate discovery only.'
  }

  foreach ($candidate in Get-AdjacentNumericTranspositions $compact) {
    Add-CandidateRecord -Candidate $candidate -VariantClass 'numeric_block_transposition' -Confidence 'low' -CandidateStatus 'ad_number_transposition_candidate' -SearchAllowed $true -ReviewRequired $true -Notes 'Adjacent numeric-block transposition; candidate discovery only.'
  }

  Add-CandidateRecord -Candidate $compact -VariantClass 'wildcard_prefix_review_only' -Confidence 'review' -CandidateStatus 'wildcard_prefix_review_only' -SearchAllowed $false -ReviewRequired $true -Notes 'Wildcard prefix matching is review-only and is never used as an AD query.'

  @($records | Select-Object -First 50)
}

function Get-ADComputerCandidates([string]$Identifier,[string]$IdentifierType,[string]$Site = '') {
  Get-ADComputerCandidateRecords $Identifier $IdentifierType $Site |
    Where-Object { $_.SearchAllowed } |
    Select-Object -ExpandProperty Candidate -Unique
}

function Format-CandidatePool([object[]]$CandidateRecords) {
  if (-not $CandidateRecords) { return '' }
  (@($CandidateRecords) | ForEach-Object {
    "{0}:{1}:{2}:{3}:query={4}" -f $_.Candidate,$_.VariantClass,$_.Confidence,$_.CandidateStatus,$_.SearchAllowed
  }) -join ';'
}

function Select-BestCandidateForComputer($Computer,[object[]]$CandidateRecords) {
  if (-not $CandidateRecords) { return $null }
  $computerName = Get-ShortHostname ([string]$Computer.Name)
  $dnsName = Get-ShortHostname ([string]$Computer.DNSHostName)
  foreach ($r in @($CandidateRecords | Where-Object { $_.SearchAllowed })) {
    $candidateShort = Get-ShortHostname ([string]$r.Candidate)
    if ($candidateShort -and ($candidateShort -eq $computerName -or $candidateShort -eq $dnsName)) { return $r }
  }
  return @($CandidateRecords | Where-Object { $_.SearchAllowed } | Select-Object -First 1)[0]
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
    [string]$CandidateValue = '',
    [string]$CandidateVariantClass = '',
    [string]$CandidateConfidence = '',
    [string]$CandidateStatus = '',
    [string]$CandidateReviewRequired = '',
    [string]$CandidatePool = '',
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
    CandidateValue = $CandidateValue
    CandidateVariantClass = $CandidateVariantClass
    CandidateConfidence = $CandidateConfidence
    CandidateStatus = $CandidateStatus
    CandidateReviewRequired = $CandidateReviewRequired
    CandidatePool = $CandidatePool
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

function Convert-ADComputerToEvidenceRow($Computer,[string]$Target,[string]$IdentifierType,[string]$Method,[pscustomobject]$DomainState,[switch]$DoDnsResolve,[int]$StaleAfterDays,$CandidateRecord,[string]$CandidatePool) {
  $enabled = if ($null -ne $Computer.Enabled) { [bool]$Computer.Enabled } else { $true }
  $dns = Resolve-AdDnsState ([string]$Computer.DNSHostName) -Enabled:$DoDnsResolve
  $status = [string]$dns.Status
  if (-not $enabled) {
    $status = 'AD_OBJECT_FOUND_DISABLED'
  } elseif ($null -ne $Computer.whenChanged -and ((Get-Date) - [datetime]$Computer.whenChanged).Days -gt $StaleAfterDays) {
    $status = 'AD_OBJECT_FOUND_STALE'
  }
  $candidateValue = ''
  $candidateVariantClass = ''
  $candidateConfidence = ''
  $candidateStatus = ''
  $candidateReviewRequired = ''
  $candidateNotes = ''
  if ($CandidateRecord) {
    $candidateValue = [string]$CandidateRecord.Candidate
    $candidateVariantClass = [string]$CandidateRecord.VariantClass
    $candidateConfidence = [string]$CandidateRecord.Confidence
    $candidateStatus = [string]$CandidateRecord.CandidateStatus
    $candidateReviewRequired = [string]$CandidateRecord.ReviewRequired
    $candidateNotes = [string]$CandidateRecord.Notes
  }
  $notes = "whenChanged={0} | {1} | candidate_status={2} | serial_unverified | needs_privileged_identity | {3}" -f $Computer.whenChanged, $dns.Notes, $candidateStatus, $candidateNotes
  New-EvidenceRow -Target $Target -IdentifierType $IdentifierType -ADHostname ([string]$Computer.Name) -DNSHostName ([string]$Computer.DNSHostName) -ADEnabled ([string]$enabled) -DirectoryPath ([string]$Computer.DistinguishedName) -ADStatus $status -ADProbeMethod $Method -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -DNSStatus ([string]$dns.DNSStatus) -CandidateValue $candidateValue -CandidateVariantClass $candidateVariantClass -CandidateConfidence $candidateConfidence -CandidateStatus $candidateStatus -CandidateReviewRequired $candidateReviewRequired -CandidatePool $CandidatePool -Notes $notes
}

function Find-WithADModule([string]$Identifier,[string]$IdentifierType,[string]$Site,[switch]$AllowDescriptionSearch,[pscustomobject]$DomainState,[switch]$DoDnsResolve,[int]$StaleAfterDays) {
  $props = @('Enabled','DistinguishedName','DNSHostName','Description','Name','whenChanged')
  $candidateRecords = @(Get-ADComputerCandidateRecords $Identifier $IdentifierType $Site)
  $queryRecords = @($candidateRecords | Where-Object { $_.SearchAllowed })
  $candidatePool = Format-CandidatePool $candidateRecords
  $matches = @()

  foreach ($record in $queryRecords) {
    try {
      $matches += Get-ADComputer -Identity ([string]$record.Candidate) -Properties $props -ErrorAction Stop
    } catch {
      $m = $_.Exception.Message
      if (Test-PermissionError $m) { return New-BlockedEvidenceRow $Identifier $IdentifierType 'PERMISSION_BLOCKED' 'active_directory_module_identity' $DomainState $m }
    }
  }

  if ($matches.Count -eq 0) {
    $clauses = @()
    foreach ($record in $queryRecords) {
      $safe = ConvertTo-LdapEscapedValue ([string]$record.Candidate)
      if ($safe) {
        $clauses += "(name=$safe)"
        $clauses += "(dNSHostName=$safe)"
        $clauses += "(sAMAccountName=$safe)"
      }
    }
    if ($AllowDescriptionSearch) {
      $safe = ConvertTo-LdapEscapedValue $Identifier
      if ($safe) { $clauses += "(description=$safe)" }
    }
    if ($clauses.Count -gt 0) {
      $filter = if ($clauses.Count -eq 1) { $clauses[0] } else { "(|$($clauses -join ''))" }
      try {
        $matches = @(Get-ADComputer -LDAPFilter $filter -Properties $props -ResultSetSize 25 -ErrorAction Stop)
      } catch {
        $m = $_.Exception.Message
        $st = if (Test-PermissionError $m) { 'PERMISSION_BLOCKED' } else { 'AD_QUERY_BLOCKED' }
        return New-BlockedEvidenceRow $Identifier $IdentifierType $st 'active_directory_module_bounded_variant_filter' $DomainState $m
      }
    }
  }

  $u = @{}
  foreach ($x in $matches) {
    if ($x.DistinguishedName -and -not $u.ContainsKey([string]$x.DistinguishedName)) { $u[[string]$x.DistinguishedName] = $x }
  }
  $d = @($u.Values)
  if ($d.Count -eq 1) {
    $candidate = Select-BestCandidateForComputer $d[0] $candidateRecords
    return Convert-ADComputerToEvidenceRow $d[0] $Identifier $IdentifierType 'active_directory_module_bounded_variant_lookup' $DomainState -DoDnsResolve:$DoDnsResolve -StaleAfterDays $StaleAfterDays -CandidateRecord $candidate -CandidatePool $candidatePool
  }
  if ($d.Count -gt 1) {
    return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_DUPLICATE_CANDIDATES' -ADProbeMethod 'active_directory_module_bounded_variant_lookup' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -CandidatePool $candidatePool -Notes ("Multiple candidate AD computer objects found: {0} | serial_unverified | needs_privileged_identity" -f (($d | Select-Object -ExpandProperty Name) -join ';'))
  }
  New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_NOT_FOUND' -ADProbeMethod 'active_directory_module_bounded_variant_lookup' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -CandidatePool $candidatePool -Notes 'No matching AD computer object found with bounded doctrine candidate lookup; not_found_in_ad.'
}

function Find-WithDsquery([string]$Identifier,[string]$IdentifierType,[pscustomobject]$DomainState) {
  if ($IdentifierType -ne 'hostname') { return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'NOT_AD_VERIFIED' -ADProbeMethod 'dsquery_hostname_only' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes 'dsquery fallback supports exact hostname lookup only.' }
  try {
    $raw = & dsquery.exe computer -name (Get-ShortHostname $Identifier) 2>&1
    if ($LASTEXITCODE -eq 0 -and $raw) {
      $lines = @($raw | Where-Object { $_ -and $_.ToString().Trim() })
      if ($lines.Count -gt 1) { return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADStatus 'AD_DUPLICATE_CANDIDATES' -ADProbeMethod 'dsquery_computer_exact_name' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -Notes ($lines -join ';') }
      $host = if ($lines[0] -match '^"?CN=([^,"]+)') { $matches[1] } else { '' }
      return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType -ADHostname $host -DirectoryPath ([string]$lines[0]) -ADStatus 'NOT_AD_VERIFIED' -ADProbeMethod 'dsquery_computer_exact_name' -DomainContext $DomainState.DomainContext -DomainControllerStatus $DomainState.DomainControllerStatus -PermissionStatus $DomainState.PermissionStatus -CandidateStatus 'ad_exact_match' -CandidateReviewRequired 'False' -Notes 'Resolved through dsquery fallback; DNS/enabled/stale fields unavailable; serial_unverified.'
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
  New-EvidenceRow -Target $Row.Target -IdentifierType $Row.IdentifierType -ADHostname $Row.ADHostname -DNSHostName $Row.DNSHostName -ADEnabled $Row.ADEnabled -DirectoryPath $Row.DirectoryPath -ComputerOU $ou -LegacyOUWarning $warn -ADStatus $status -ADProbeMethod $Row.ADProbeMethod -DomainContext $Row.DomainContext -DomainControllerStatus $Row.DomainControllerStatus -PermissionStatus $Row.PermissionStatus -DNSStatus $Row.DNSStatus -CandidateValue $Row.CandidateValue -CandidateVariantClass $Row.CandidateVariantClass -CandidateConfidence $Row.CandidateConfidence -CandidateStatus $Row.CandidateStatus -CandidateReviewRequired $Row.CandidateReviewRequired -CandidatePool $Row.CandidatePool -Notes $notes
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
  $candidateReview = @($Results | Where-Object { $_.CandidateReviewRequired -match 'True|true' }).Count
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
  Write-Host ("- Needs operator review: {0}" -f ($counts['NEEDS_OPERATOR_REVIEW'] + $counts['AD_DUPLICATE_CANDIDATES'] + $counts['AD_OBJECT_FOUND_WRONG_OU'] + $candidateReview))
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
    needs_operator_review = ($counts['NEEDS_OPERATOR_REVIEW'] + $counts['AD_DUPLICATE_CANDIDATES'] + $counts['AD_OBJECT_FOUND_WRONG_OU'] + $candidateReview)
    candidate_review_required = $candidateReview
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
$queryMode = if ($hasADModule) { 'active_directory_module_bounded_variant_lookup' } elseif ($hasDsquery) { 'dsquery_exact_hostname_fallback' } else { 'no_live_ad_tooling_available' }
$fallbackMode = if ($hasADModule) { 'none' } elseif ($hasDsquery) { 'dsquery' } else { 'operator_manifest_required' }

$results = foreach ($raw in $manifestRows) {
  $row = ConvertTo-Hashtable $raw
  $id = Get-ManifestIdentifier $row
  $site = Get-ManifestSite $row
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
    $e = Find-WithADModule $id $type $site -AllowDescriptionSearch:$SearchDescription -DomainState $domainState -DoDnsResolve:$ResolveDns -StaleAfterDays $StaleDays
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
