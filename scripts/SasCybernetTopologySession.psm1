#Requires -Version 5.1
<#
.SYNOPSIS
  Local, offline session engine for the Cybernet deployment topology survey loop.

.DESCRIPTION
  Turns each probe result into context for the next probe. The session keeps one
  cumulative local registry, merges newly ingested evidence and bundles shared by
  other technicians, recomputes targeted-pass eligibility, and writes a probe plan
  plus an operator handoff.

  This engine performs no network activity. It never decides whether a host is a
  Cybernet; it only answers which CIDRs deserve a bounded targeted pass.

  All session state lives under a gitignored evidence root.
#>

Set-StrictMode -Version Latest

$script:SessionSchemaVersion = 'sas-cybernet-deployment-topology-registry/v1'
$script:BundleSchemaVersion = 'sas-cybernet-topology-evidence-bundle/v1'
$script:SummarySchemaVersion = 'sas-cybernet-topology-iteration-summary/v1'

function Get-SasCybernetTopologySessionPath {
  <#
  .SYNOPSIS
    Resolve every path the session uses. Does not create anything.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$SessionRoot
  )

  if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    $SessionRoot = Join-Path $RepoRoot 'evidence\CybernetTopology'
  }

  return [pscustomobject]@{
    RepoRoot     = $RepoRoot
    SessionRoot  = $SessionRoot
    RegistryPath = Join-Path $SessionRoot 'registry.local.json'
    StatePath    = Join-Path $SessionRoot 'session-state.json'
    InboxDir     = Join-Path $SessionRoot 'inbox'
    OutboxDir    = Join-Path $SessionRoot 'outbox'
    IngestDir    = Join-Path $SessionRoot 'ingest'
    RunsDir      = Join-Path $SessionRoot 'runs'
    ArchiveDir   = Join-Path $SessionRoot 'inbox\imported'
    RejectedDir  = Join-Path $SessionRoot 'inbox\rejected'
  }
}

function ConvertTo-SasTopologyMutable {
  <#
  .SYNOPSIS
    Convert parsed JSON into nested ordered hashtables so merges are simple.
  #>
  param([object]$InputObject)

  if ($null -eq $InputObject) { return $null }

  if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
    $map = [ordered]@{}
    foreach ($prop in $InputObject.PSObject.Properties) {
      $map[$prop.Name] = ConvertTo-SasTopologyMutable -InputObject $prop.Value
    }
    return $map
  }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $map = [ordered]@{}
    foreach ($key in $InputObject.Keys) {
      $map[[string]$key] = ConvertTo-SasTopologyMutable -InputObject $InputObject[$key]
    }
    return $map
  }

  if ($InputObject -is [string]) { return $InputObject }

  # ConvertFrom-Json revives ISO timestamps as [datetime]. Re-emit them as canonical
  # UTC strings so repeated merges never drift the format or the timezone.
  if ($InputObject -is [datetime]) {
    return ([datetime]$InputObject).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }

  if ($InputObject -is [System.Collections.IEnumerable]) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in $InputObject) {
      [void]$list.Add((ConvertTo-SasTopologyMutable -InputObject $item))
    }
    return , $list.ToArray()
  }

  return $InputObject
}

function ConvertTo-SasTopologyObject {
  <#
  .SYNOPSIS
    Rebuild a mutable structure as PSCustomObject form for the evaluator.

  .DESCRIPTION
    Built directly rather than round-tripped through JSON. A JSON round-trip would
    revive ISO timestamps as [datetime] and silently rewrite their format on every
    merge, and it would also be bounded by a serializer depth limit.
  #>
  param([object]$InputObject)

  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [string]) { return $InputObject }
  if ($InputObject -is [datetime]) {
    return ([datetime]$InputObject).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }

  if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
    $ordered = [ordered]@{}
    foreach ($prop in $InputObject.PSObject.Properties) {
      $ordered[$prop.Name] = ConvertTo-SasTopologyObject -InputObject $prop.Value
    }
    return [pscustomobject]$ordered
  }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $ordered = [ordered]@{}
    foreach ($key in $InputObject.Keys) {
      $ordered[[string]$key] = ConvertTo-SasTopologyObject -InputObject $InputObject[$key]
    }
    return [pscustomobject]$ordered
  }

  if ($InputObject -is [System.Collections.IEnumerable]) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in $InputObject) {
      [void]$list.Add((ConvertTo-SasTopologyObject -InputObject $item))
    }
    return , $list.ToArray()
  }

  return $InputObject
}

function Read-SasTopologyJsonFile {
  param([Parameter(Mandatory)][string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  if ([string]::IsNullOrWhiteSpace($raw)) {
    throw "File contains no JSON content: $Path"
  }
  return ($raw | ConvertFrom-Json)
}

function Write-SasTopologyJsonFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][object]$InputObject
  )
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $json = ConvertTo-Json -InputObject $InputObject -Depth 32
  Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function New-SasCybernetTopologyRunId {
  param([datetime]$AsOf = (Get-Date).ToUniversalTime())
  return $AsOf.ToString('yyyyMMddTHHmmssZ')
}

function New-SasCybernetTopologyEmptyRegistry {
  <#
  .SYNOPSIS
    Seed an empty working registry that carries policy but claims no locations.
  #>
  param([datetime]$AsOf = (Get-Date).ToUniversalTime())

  return [ordered]@{
    schema_version = $script:SessionSchemaVersion
    generated_at   = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
    policy         = [ordered]@{
      targeted_pass = [ordered]@{
        allowed_confidence                              = @('HIGH', 'MEDIUM')
        medium_requires_independent_corroboration       = $true
        require_last_observed                           = $true
        max_observation_age_days                        = 365
        reject_if_relocation_evidence_exists            = $true
        reject_if_subnet_is_only_inferred_from_hostname = $true
        reject_if_only_network_discovery_supports_subnet = $true
      }
    }
    sites          = @()
  }
}

function Initialize-SasCybernetTopologySession {
  <#
  .SYNOPSIS
    Idempotent bootstrap. Safe on the first click and on every later click.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$SessionRoot,
    [datetime]$AsOf = (Get-Date).ToUniversalTime()
  )

  $paths = Get-SasCybernetTopologySessionPath -RepoRoot $RepoRoot -SessionRoot $SessionRoot
  $created = $false

  foreach ($dir in @($paths.SessionRoot, $paths.InboxDir, $paths.OutboxDir, $paths.IngestDir, $paths.RunsDir, $paths.ArchiveDir, $paths.RejectedDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
      $created = $true
    }
  }

  if (-not (Test-Path -LiteralPath $paths.RegistryPath)) {
    Write-SasTopologyJsonFile -Path $paths.RegistryPath -InputObject (New-SasCybernetTopologyEmptyRegistry -AsOf $AsOf)
    $created = $true
  }

  return [pscustomobject]@{
    Paths          = $paths
    CreatedThisRun = $created
    FirstRun       = $created
  }
}

function Get-SasTopologyEvidenceObservedAt {
  param([object]$Evidence)
  $value = $null
  if ($Evidence -is [System.Collections.IDictionary] -and $Evidence.Contains('observed_at')) {
    $value = [string]$Evidence['observed_at']
  }
  if ([string]::IsNullOrWhiteSpace($value)) { return [datetime]::MinValue }
  $parsed = [datetime]::MinValue
  if ([datetime]::TryParse(
      $value,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal,
      [ref]$parsed)) {
    return $parsed
  }
  return [datetime]::MinValue
}

function Compare-SasTopologyTimestamp {
  <#
  .SYNOPSIS
    Order two timestamps by instant rather than by text.

  .DESCRIPTION
    Returns 1 when Left is later, -1 when earlier, 0 when equal. Raw string ordering
    would rank an offset-bearing timestamp such as 2026-08-31T20:00:00-05:00 against a
    UTC one incorrectly, which could let an older confidence overwrite a newer one.
  #>
  param(
    [string]$Left,
    [string]$Right
  )

  $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
  $culture = [System.Globalization.CultureInfo]::InvariantCulture
  $leftValue = [datetime]::MinValue
  $rightValue = [datetime]::MinValue

  $leftOk = -not [string]::IsNullOrWhiteSpace($Left) -and [datetime]::TryParse($Left, $culture, $styles, [ref]$leftValue)
  $rightOk = -not [string]::IsNullOrWhiteSpace($Right) -and [datetime]::TryParse($Right, $culture, $styles, [ref]$rightValue)

  if ($leftOk -and $rightOk) { return $leftValue.CompareTo($rightValue) }
  if ($leftOk) { return 1 }
  if ($rightOk) { return -1 }
  return 0
}

function Merge-SasTopologyEvidenceList {
  <#
  .SYNOPSIS
    Merge evidence arrays keyed by evidence_id. Newest observed_at wins.
  #>
  param(
    [object[]]$Existing,
    [object[]]$Incoming
  )

  $byId = [ordered]@{}
  $added = 0
  $updated = 0

  foreach ($ev in @($Existing)) {
    if ($null -eq $ev) { continue }
    $id = [string]$ev['evidence_id']
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $byId[$id] = $ev
  }

  foreach ($ev in @($Incoming)) {
    if ($null -eq $ev) { continue }
    $id = [string]$ev['evidence_id']
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    if (-not $byId.Contains($id)) {
      $byId[$id] = $ev
      $added++
      continue
    }
    $existingAt = Get-SasTopologyEvidenceObservedAt -Evidence $byId[$id]
    $incomingAt = Get-SasTopologyEvidenceObservedAt -Evidence $ev
    if ($incomingAt -gt $existingAt) {
      $byId[$id] = $ev
      $updated++
    }
  }

  $merged = New-Object System.Collections.Generic.List[object]
  foreach ($key in $byId.Keys) { [void]$merged.Add($byId[$key]) }

  return [pscustomobject]@{
    Evidence = $merged.ToArray()
    Added    = $added
    Updated  = $updated
  }
}

function Update-SasTopologyLastObserved {
  <#
  .SYNOPSIS
    Refresh last_observed from the newest merged evidence so accumulated probe
    results actually renew subnet freshness instead of going stale silently.
  #>
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Subnet)

  $newest = [datetime]::MinValue
  $ids = New-Object System.Collections.Generic.List[string]

  foreach ($ev in @($Subnet['deployment_evidence'])) {
    if ($null -eq $ev) { continue }
    $at = Get-SasTopologyEvidenceObservedAt -Evidence $ev
    if ($at -eq [datetime]::MinValue) { continue }
    if ($at.Date -gt $newest.Date) {
      $newest = $at
      $ids.Clear()
      [void]$ids.Add([string]$ev['evidence_id'])
    }
    elseif ($at.Date -eq $newest.Date) {
      [void]$ids.Add([string]$ev['evidence_id'])
    }
  }

  if ($newest -eq [datetime]::MinValue) { return }

  $Subnet['last_observed'] = [ordered]@{
    date                = $newest.ToString('yyyy-MM-dd')
    source_evidence_ids = $ids.ToArray()
  }
}

function Initialize-SasTopologyIncomingSubnet {
  <#
  .SYNOPSIS
    Apply the evidence-id merge contract to a subnet adopted wholesale.

  .DESCRIPTION
    A brand new site or subnet is taken from the incoming payload directly. Its own
    evidence still has to be deduplicated by evidence_id and have last_observed
    derived, otherwise a colleague's duplicate ids would survive into the registry.
  #>
  param([System.Collections.IDictionary]$Subnet)

  if ($null -eq $Subnet) { return $null }
  $deduped = Merge-SasTopologyEvidenceList -Existing @() -Incoming @($Subnet['deployment_evidence'])
  $Subnet['deployment_evidence'] = $deduped.Evidence
  Update-SasTopologyLastObserved -Subnet $Subnet
  return $Subnet
}

function Measure-SasTopologyEvidenceCount {
  param([System.Collections.IDictionary]$Subnet)
  if ($null -eq $Subnet) { return 0 }
  $count = 0
  foreach ($ev in @($Subnet['deployment_evidence'])) {
    if ($null -ne $ev) { $count++ }
  }
  return $count
}

function Merge-SasCybernetTopologyRegistry {
  <#
  .SYNOPSIS
    Merge incoming registry-shaped content into the working registry.

  .DESCRIPTION
    Sites merge by site_id, subnets by subnet_id, evidence by evidence_id.
    A declared subnet_confidence only replaces the current one when its
    calculated_at is strictly newer; classifications are never invented here.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Registry,
    [Parameter(Mandatory)][object]$Incoming,
    [string]$SourceLabel = 'unknown'
  )

  $target = ConvertTo-SasTopologyMutable -InputObject $Registry
  $source = ConvertTo-SasTopologyMutable -InputObject $Incoming

  $stats = [ordered]@{
    source            = $SourceLabel
    sites_added       = 0
    subnets_added     = 0
    evidence_added    = 0
    evidence_updated  = 0
    confidence_updated = 0
  }

  $sitesById = [ordered]@{}
  foreach ($site in @($target['sites'])) {
    if ($null -eq $site) { continue }
    $sitesById[[string]$site['site_id']] = $site
  }

  foreach ($incomingSite in @($source['sites'])) {
    if ($null -eq $incomingSite) { continue }
    $siteId = [string]$incomingSite['site_id']
    if ([string]::IsNullOrWhiteSpace($siteId)) { continue }

    if (-not $sitesById.Contains($siteId)) {
      $sitesById[$siteId] = $incomingSite
      $stats['sites_added'] = [int]$stats['sites_added'] + 1
      foreach ($newSubnet in @($incomingSite['subnets'])) {
        if ($null -eq $newSubnet) { continue }
        $prepared = Initialize-SasTopologyIncomingSubnet -Subnet $newSubnet
        $stats['subnets_added'] = [int]$stats['subnets_added'] + 1
        $stats['evidence_added'] = [int]$stats['evidence_added'] + (Measure-SasTopologyEvidenceCount -Subnet $prepared)
      }
      continue
    }

    $site = $sitesById[$siteId]
    $subnetsById = [ordered]@{}
    foreach ($subnet in @($site['subnets'])) {
      if ($null -eq $subnet) { continue }
      $subnetsById[[string]$subnet['subnet_id']] = $subnet
    }

    foreach ($incomingSubnet in @($incomingSite['subnets'])) {
      if ($null -eq $incomingSubnet) { continue }
      $subnetId = [string]$incomingSubnet['subnet_id']
      if ([string]::IsNullOrWhiteSpace($subnetId)) { continue }

      if (-not $subnetsById.Contains($subnetId)) {
        $prepared = Initialize-SasTopologyIncomingSubnet -Subnet $incomingSubnet
        $subnetsById[$subnetId] = $prepared
        $stats['subnets_added'] = [int]$stats['subnets_added'] + 1
        $stats['evidence_added'] = [int]$stats['evidence_added'] + (Measure-SasTopologyEvidenceCount -Subnet $prepared)
        continue
      }

      $subnet = $subnetsById[$subnetId]
      $mergeResult = Merge-SasTopologyEvidenceList `
        -Existing @($subnet['deployment_evidence']) `
        -Incoming @($incomingSubnet['deployment_evidence'])
      $subnet['deployment_evidence'] = $mergeResult.Evidence
      $stats['evidence_added'] = [int]$stats['evidence_added'] + $mergeResult.Added
      $stats['evidence_updated'] = [int]$stats['evidence_updated'] + $mergeResult.Updated

      if ($incomingSubnet.Contains('subnet_confidence') -and $null -ne $incomingSubnet['subnet_confidence']) {
        $incomingCalc = [string]$incomingSubnet['subnet_confidence']['calculated_at']
        $currentCalc = ''
        if ($subnet.Contains('subnet_confidence') -and $null -ne $subnet['subnet_confidence']) {
          $currentCalc = [string]$subnet['subnet_confidence']['calculated_at']
        }
        if ([string]::IsNullOrWhiteSpace($currentCalc) -or
          ((Compare-SasTopologyTimestamp -Left $incomingCalc -Right $currentCalc) -gt 0)) {
          $subnet['subnet_confidence'] = $incomingSubnet['subnet_confidence']
          $stats['confidence_updated'] = [int]$stats['confidence_updated'] + 1
        }
      }

      if ($incomingSubnet.Contains('superseded_by_subnet_id') -and
        -not [string]::IsNullOrWhiteSpace([string]$incomingSubnet['superseded_by_subnet_id'])) {
        $subnet['superseded_by_subnet_id'] = $incomingSubnet['superseded_by_subnet_id']
      }

      if ($incomingSubnet.Contains('targeted_pass_budget') -and -not $subnet.Contains('targeted_pass_budget')) {
        $subnet['targeted_pass_budget'] = $incomingSubnet['targeted_pass_budget']
      }

      Update-SasTopologyLastObserved -Subnet $subnet
    }

    $rebuilt = New-Object System.Collections.Generic.List[object]
    foreach ($key in $subnetsById.Keys) { [void]$rebuilt.Add($subnetsById[$key]) }
    $site['subnets'] = $rebuilt.ToArray()
  }

  $rebuiltSites = New-Object System.Collections.Generic.List[object]
  foreach ($key in $sitesById.Keys) {
    $site = $sitesById[$key]
    foreach ($subnet in @($site['subnets'])) {
      if ($null -ne $subnet) { Update-SasTopologyLastObserved -Subnet $subnet }
    }
    [void]$rebuiltSites.Add($site)
  }
  $target['sites'] = $rebuiltSites.ToArray()

  return [pscustomobject]@{
    Registry = ConvertTo-SasTopologyObject -InputObject $target
    Stats    = [pscustomobject]$stats
  }
}

function Get-SasTopologySafeSourceReference {
  <#
  .SYNOPSIS
    Strip machine-local absolute paths from a shared bundle reference.
  #>
  param([string]$Reference)

  if ([string]::IsNullOrWhiteSpace($Reference)) { return 'operator-local-reference' }
  if ($Reference -match '^[A-Za-z]:\\' -or $Reference -match '^\\\\' -or $Reference -match '^/(home|Users|mnt)/') {
    return 'operator-local-reference'
  }
  return $Reference
}

function Export-SasCybernetTopologyBundle {
  <#
  .SYNOPSIS
    Write a shareable evidence bundle for another technician.

  .DESCRIPTION
    Machine-local absolute paths are replaced with 'operator-local-reference'.
    The bundle still carries site, CIDR, and device_key values, so it remains
    operator-local data and must stay in ignored paths.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Registry,
    [Parameter(Mandatory)][string]$Path,
    [string]$RunId = '',
    [datetime]$AsOf = (Get-Date).ToUniversalTime()
  )

  $mutable = ConvertTo-SasTopologyMutable -InputObject $Registry
  $siteCount = 0
  $subnetCount = 0
  $evidenceCount = 0

  foreach ($site in @($mutable['sites'])) {
    if ($null -eq $site) { continue }
    $siteCount++
    foreach ($subnet in @($site['subnets'])) {
      if ($null -eq $subnet) { continue }
      $subnetCount++
      if ($subnet.Contains('targeted_pass_eligibility')) {
        $subnet.Remove('targeted_pass_eligibility')
      }
      foreach ($ev in @($subnet['deployment_evidence'])) {
        if ($null -eq $ev) { continue }
        $evidenceCount++
        $ev['source_reference'] = Get-SasTopologySafeSourceReference -Reference ([string]$ev['source_reference'])
      }
    }
  }

  $bundle = [ordered]@{
    schema_version               = $script:BundleSchemaVersion
    generated_at                 = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
    source_run_id                = $RunId
    contains_operator_local_data = $true
    sharing_note                 = 'Operator-local topology evidence. Keep in ignored local paths. Never commit.'
    counts                       = [ordered]@{
      sites    = $siteCount
      subnets  = $subnetCount
      evidence = $evidenceCount
    }
    registry                     = [ordered]@{
      schema_version = $script:SessionSchemaVersion
      generated_at   = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
      policy         = $mutable['policy']
      sites          = $mutable['sites']
    }
  }

  Write-SasTopologyJsonFile -Path $Path -InputObject $bundle
  return [pscustomobject]@{
    Path          = $Path
    SiteCount     = $siteCount
    SubnetCount   = $subnetCount
    EvidenceCount = $evidenceCount
  }
}

function Import-SasCybernetTopologyBundle {
  <#
  .SYNOPSIS
    Merge one bundle or raw registry file into the working registry.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Registry,
    [Parameter(Mandatory)][string]$Path
  )

  $parsed = Read-SasTopologyJsonFile -Path $Path
  $schema = ''
  if ($parsed.PSObject.Properties['schema_version']) {
    $schema = [string]$parsed.schema_version
  }

  $incoming = $null
  if ($schema -eq $script:BundleSchemaVersion) {
    if (-not $parsed.PSObject.Properties['registry']) {
      throw "Bundle is missing its registry section: $Path"
    }
    $incoming = $parsed.registry
  }
  elseif ($schema -eq $script:SessionSchemaVersion) {
    $incoming = $parsed
  }
  else {
    throw "Unsupported schema_version '$schema' in $Path. Expected $($script:BundleSchemaVersion) or $($script:SessionSchemaVersion)."
  }

  Assert-SasTopologyRegistryShape -Registry $incoming -Path $Path

  return Merge-SasCybernetTopologyRegistry -Registry $Registry -Incoming $incoming -SourceLabel (Split-Path -Leaf $Path)
}

function Assert-SasTopologyRegistryShape {
  <#
  .SYNOPSIS
    Reject a payload that carries the right schema_version but the wrong shape.

  .DESCRIPTION
    A correct version string is not proof of a usable registry. Validating here means
    a malformed share lands in the rejected folder with a readable reason instead of
    silently contributing partial or dropped records to the merge.
  #>
  param(
    [Parameter(Mandatory)][object]$Registry,
    [Parameter(Mandatory)][string]$Path
  )

  $name = Split-Path -Leaf $Path
  foreach ($required in @('policy', 'sites')) {
    if (-not $Registry.PSObject.Properties[$required]) {
      throw "Registry payload in $name is missing required '$required'."
    }
  }
  if ($null -eq $Registry.sites) {
    throw "Registry payload in $name has a null 'sites' collection."
  }

  $index = 0
  foreach ($site in @($Registry.sites)) {
    if ($null -eq $site) {
      throw "Registry payload in $name has a null site at index $index."
    }
    if (-not $site.PSObject.Properties['site_id'] -or [string]::IsNullOrWhiteSpace([string]$site.site_id)) {
      throw "Registry payload in $name has a site at index $index with no site_id; it would be dropped silently."
    }
    foreach ($subnet in @($site.subnets)) {
      if ($null -eq $subnet) { continue }
      if (-not $subnet.PSObject.Properties['subnet_id'] -or [string]::IsNullOrWhiteSpace([string]$subnet.subnet_id)) {
        throw "Registry payload in $name has a subnet with no subnet_id under site '$($site.site_id)'."
      }
    }
    $index++
  }
}

function New-SasCybernetTopologyProbePlan {
  <#
  .SYNOPSIS
    Convert evaluated eligibility into the next bounded probe plan.
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)][object]$Registry)

  $planRows = New-Object System.Collections.Generic.List[object]
  $reviewRows = New-Object System.Collections.Generic.List[object]
  $statusById = [ordered]@{}

  foreach ($site in @($Registry.sites)) {
    if ($null -eq $site) { continue }
    $organizationId = ''
    if ($site.PSObject.Properties['organization_id']) { $organizationId = [string]$site.organization_id }

    foreach ($subnet in @($site.subnets)) {
      if ($null -eq $subnet) { continue }
      $eligibility = $subnet.targeted_pass_eligibility
      $status = [string]$eligibility.status
      $statusById[[string]$subnet.subnet_id] = $status

      $reasonCodes = @($eligibility.reason_codes) -join ';'
      $blockingCodes = @($eligibility.blocking_reason_codes) -join ';'

      if ($status -eq 'ELIGIBLE') {
        # A missing budget is never treated as an unlimited budget. Eligibility says the
        # location deserves a look; only a declared budget says how much looking is allowed.
        $undeclared = 'BUDGET_NOT_DECLARED'
        $profile = $undeclared
        $ports = $undeclared
        $retries = $undeclared
        if ($subnet.PSObject.Properties['targeted_pass_budget'] -and $null -ne $subnet.targeted_pass_budget) {
          $budget = $subnet.targeted_pass_budget
          if ($budget.PSObject.Properties['discovery_profile'] -and
            -not [string]::IsNullOrWhiteSpace([string]$budget.discovery_profile)) {
            $profile = [string]$budget.discovery_profile
          }
          if ($budget.PSObject.Properties['allowed_ports'] -and @($budget.allowed_ports).Count -gt 0) {
            $ports = (@($budget.allowed_ports) -join ',')
          }
          if ($budget.PSObject.Properties['retries'] -and $null -ne $budget.retries) {
            $retries = [string]$budget.retries
          }
        }
        [void]$planRows.Add([pscustomobject]@{
            OrganizationId   = $organizationId
            SiteId           = [string]$site.site_id
            SubnetId         = [string]$subnet.subnet_id
            Cidr             = [string]$subnet.cidr
            DiscoveryProfile = $profile
            AllowedPorts     = $ports
            Retries          = $retries
            BudgetDeclared   = ($profile -ne $undeclared -and $ports -ne $undeclared)
            ReasonCodes      = $reasonCodes
          })
      }
      else {
        [void]$reviewRows.Add([pscustomobject]@{
            OrganizationId      = $organizationId
            SiteId              = [string]$site.site_id
            SubnetId            = [string]$subnet.subnet_id
            Cidr                = [string]$subnet.cidr
            Status              = $status
            BlockingReasonCodes = $blockingCodes
            NextEvidenceNeeded  = (Get-SasTopologyNextEvidenceHint -BlockingCodes @($eligibility.blocking_reason_codes))
          })
      }
    }
  }

  return [pscustomobject]@{
    PlanRows   = @($planRows.ToArray())
    ReviewRows = @($reviewRows.ToArray())
    StatusById = $statusById
  }
}

function Get-SasTopologyNextEvidenceHint {
  <#
  .SYNOPSIS
    Say which evidence would move a blocked subnet forward on the next pass.
  #>
  param([string[]]$BlockingCodes)

  $codes = @($BlockingCodes)
  if ($codes -contains 'INSUFFICIENT_INDEPENDENT_CORROBORATION') {
    return 'Add a second SUBNET-supporting evidence record with a different source_type and a CONFIRMED_DEPLOYED device_anchor.'
  }
  if ($codes -contains 'NO_SUBNET_LINKED_DEPLOYMENT_PROOF') {
    return 'Add authoritative deployment evidence whose supports includes SUBNET for a confirmed deployed device.'
  }
  if ($codes -contains 'NO_DEPLOYMENT_PROOF') {
    return 'Add a confirmed deployment record from an approved tracker, signoff, or inventory source.'
  }
  if ($codes -contains 'OBSERVATION_STALE') {
    return 'Re-observe this subnet; the newest qualifying evidence is older than the freshness horizon.'
  }
  if ($codes -contains 'MISSING_LAST_OBSERVED' -or $codes -contains 'INVALID_LAST_OBSERVED') {
    return 'Supply a valid yyyy-MM-dd last_observed date backed by evidence ids.'
  }
  if ($codes -contains 'FUTURE_LAST_OBSERVED') {
    return 'Correct the observation date; it is later than the evaluation time.'
  }
  if ($codes -contains 'HOSTNAME_INFERENCE_ONLY') {
    return 'Subnet came only from naming convention. Obtain a real observation before probing.'
  }
  if ($codes -contains 'NETWORK_DISCOVERY_ONLY') {
    return 'Alive hosts alone do not authorize targeting. Tie an observation to a confirmed deployed device.'
  }
  if ($codes -contains 'CONFLICTING_SUBNET_EVIDENCE' -or $codes -contains 'RELOCATION_EVIDENCE_PRESENT') {
    return 'Two credible sources disagree. Resolve placement with an operator review before probing.'
  }
  if ($codes -contains 'SUPERSEDED_BY_NEWER_SUBNET') {
    return 'Device relocated. Probe the superseding subnet instead; keep this row for history.'
  }
  if ($codes -contains 'SITE_NOT_ACTIVE') {
    return 'Site is not ACTIVE. Confirm site status before any targeting.'
  }
  if ($codes -contains 'MISSING_ORGANIZATION_ID') {
    return 'Set organization_id on the site. Organization boundaries are profile boundaries.'
  }
  if ($codes -contains 'INVALID_CIDR') {
    return 'Fix the CIDR value; it is not a valid IPv4 network.'
  }
  return 'Review the blocking reason codes and supply the missing evidence.'
}

function Get-SasCybernetTopologyDelta {
  <#
  .SYNOPSIS
    Compare this run's statuses against the previous run so reruns show change.
  #>
  [CmdletBinding()]
  param(
    [System.Collections.IDictionary]$PreviousStatusById,
    [Parameter(Mandatory)][System.Collections.IDictionary]$CurrentStatusById,
    [switch]$HadPreviousRun
  )

  $newlyEligible = New-Object System.Collections.Generic.List[string]
  $noLongerEligible = New-Object System.Collections.Generic.List[string]
  $newSubnets = New-Object System.Collections.Generic.List[string]
  $changed = New-Object System.Collections.Generic.List[string]

  $previous = $PreviousStatusById
  if ($null -eq $previous) { $previous = [ordered]@{} }

  foreach ($subnetId in $CurrentStatusById.Keys) {
    $current = [string]$CurrentStatusById[$subnetId]
    if (-not $previous.Contains($subnetId)) {
      [void]$newSubnets.Add([string]$subnetId)
      if ($current -eq 'ELIGIBLE') { [void]$newlyEligible.Add([string]$subnetId) }
      continue
    }
    $prior = [string]$previous[$subnetId]
    if ($prior -eq $current) { continue }
    [void]$changed.Add("$subnetId : $prior -> $current")
    if ($current -eq 'ELIGIBLE') { [void]$newlyEligible.Add([string]$subnetId) }
    elseif ($prior -eq 'ELIGIBLE') { [void]$noLongerEligible.Add([string]$subnetId) }
  }

  return [pscustomobject]@{
    NewSubnets       = @($newSubnets.ToArray())
    NewlyEligible    = @($newlyEligible.ToArray())
    NoLongerEligible = @($noLongerEligible.ToArray())
    Changed          = @($changed.ToArray())
    HasPreviousRun   = ([bool]$HadPreviousRun -or $previous.Keys.Count -gt 0)
  }
}

Export-ModuleMember -Function @(
  'Get-SasCybernetTopologySessionPath'
  'Initialize-SasCybernetTopologySession'
  'New-SasCybernetTopologyEmptyRegistry'
  'New-SasCybernetTopologyRunId'
  'Merge-SasCybernetTopologyRegistry'
  'Import-SasCybernetTopologyBundle'
  'Export-SasCybernetTopologyBundle'
  'New-SasCybernetTopologyProbePlan'
  'Get-SasCybernetTopologyDelta'
  'Measure-SasTopologyEvidenceCount'
  'Initialize-SasTopologyIncomingSubnet'
  'Compare-SasTopologyTimestamp'
  'Assert-SasTopologyRegistryShape'
  'Get-SasTopologyNextEvidenceHint'
  'Get-SasTopologySafeSourceReference'
  'ConvertTo-SasTopologyMutable'
  'ConvertTo-SasTopologyObject'
  'Read-SasTopologyJsonFile'
  'Write-SasTopologyJsonFile'
)
