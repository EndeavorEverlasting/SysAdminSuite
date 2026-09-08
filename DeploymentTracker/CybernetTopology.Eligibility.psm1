#Requires -Version 5.1
<#
.SYNOPSIS
  Pure offline eligibility evaluator for sas-cybernet-deployment-topology-registry/v1.

.DESCRIPTION
  Answers one question only: which CIDRs deserve a low-noise targeted Cybernet survey
  based on deployment topology evidence.

  Independent corroboration (MEDIUM -> ELIGIBLE) requires:
  - at least two deployment_evidence records that both support SUBNET
  - distinct source_type values among those records
  - at least one of those records has authority that is neither DISCOVERY_ONLY nor INFERENTIAL

  Classification drives workflow decisions. Numeric subnet_confidence.score is ignored.
  targeted_pass_budget is operational metadata and is never an eligibility input.
#>

Set-StrictMode -Version Latest

$script:DeploymentProofSourceTypes = @(
  'DEPLOYMENT_TRACKER'
  'TECHNICIAN_SIGNOFF'
  'DEPLOYMENT_COMPLETION_REPORT'
  'SERIAL_INVENTORY'
  'OPERATOR_CONFIRMED'
)

$script:DeploymentProofEvidenceTypes = @(
  'CONFIRMED_DEPLOYMENT'
  'DEPLOYMENT_COMPLETION'
)

function Get-CybernetTopologyProperty {
  param(
    [Parameter(Mandatory)][object]$Object,
    [Parameter(Mandatory)][string]$Name
  )
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Test-CybernetTopologyValidCidr {
  param([string]$Cidr)
  if ([string]::IsNullOrWhiteSpace($Cidr)) { return $false }
  if ($Cidr -notmatch '^(?<ip>(?:\d{1,3}\.){3}\d{1,3})/(?<prefix>\d{1,2})$') {
    return $false
  }
  $prefix = [int]$Matches['prefix']
  if ($prefix -lt 0 -or $prefix -gt 32) { return $false }
  $octets = $Matches['ip'] -split '\.'
  foreach ($o in $octets) {
    $n = [int]$o
    if ($n -lt 0 -or $n -gt 255) { return $false }
  }
  return $true
}

function Get-CybernetTopologySupports {
  param([object]$Evidence)
  $supports = @(Get-CybernetTopologyProperty -Object $Evidence -Name 'supports')
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($s in $supports) {
    if ($null -eq $s) { continue }
    if ($s -is [System.Array]) {
      foreach ($inner in @($s)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$inner)) {
          [void]$out.Add(([string]$inner).Trim().ToUpperInvariant())
        }
      }
    }
    else {
      $t = ([string]$s).Trim().ToUpperInvariant()
      if ($t) { [void]$out.Add($t) }
    }
  }
  return @($out | Select-Object -Unique)
}

function Test-CybernetTopologyDeploymentProof {
  param([object]$Evidence)
  $authority = [string](Get-CybernetTopologyProperty -Object $Evidence -Name 'authority')
  if ($authority -eq 'DISCOVERY_ONLY') { return $false }

  $evidenceType = [string](Get-CybernetTopologyProperty -Object $Evidence -Name 'evidence_type')
  if ($script:DeploymentProofEvidenceTypes -contains $evidenceType) { return $true }

  $sourceType = [string](Get-CybernetTopologyProperty -Object $Evidence -Name 'source_type')
  if (
    ($script:DeploymentProofSourceTypes -contains $sourceType) -and
    ($authority -eq 'AUTHORITATIVE')
  ) {
    return $true
  }
  return $false
}

function Test-CybernetTopologyIndependentSubnetCorroboration {
  param([object[]]$Evidence)
  $subnetEvidence = @()
  foreach ($ev in @($Evidence)) {
    $supports = Get-CybernetTopologySupports -Evidence $ev
    if ($supports -notcontains 'SUBNET') { continue }
    if (-not (Test-CybernetTopologyConfirmedDeviceAnchor -Evidence $ev)) { continue }
    $subnetEvidence += ,$ev
  }
  if ($subnetEvidence.Count -lt 2) { return $false }

  $sourceTypes = @(
    $subnetEvidence |
      ForEach-Object { [string](Get-CybernetTopologyProperty -Object $_ -Name 'source_type') } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -Unique
  )
  if ($sourceTypes.Count -lt 2) { return $false }

  $hasStrongAuthority = $false
  foreach ($ev in $subnetEvidence) {
    $authority = [string](Get-CybernetTopologyProperty -Object $ev -Name 'authority')
    if ($authority -ne 'DISCOVERY_ONLY' -and $authority -ne 'INFERENTIAL' -and -not [string]::IsNullOrWhiteSpace($authority)) {
      $hasStrongAuthority = $true
      break
    }
  }
  return $hasStrongAuthority
}

function Test-CybernetTopologySubnetLinkedDeploymentProof {
  param([object[]]$Evidence)
  foreach ($ev in @($Evidence)) {
    if (-not (Test-CybernetTopologyDeploymentProof -Evidence $ev)) { continue }
    $supports = Get-CybernetTopologySupports -Evidence $ev
    if ($supports -notcontains 'SUBNET') { continue }
    if (-not (Test-CybernetTopologyConfirmedDeviceAnchor -Evidence $ev)) { continue }
    return $true
  }
  return $false
}

function Test-CybernetTopologyHostnameOnlySubnet {
  param(
    [string[]]$Basis,
    [object[]]$Evidence
  )
  $basisSet = @($Basis | ForEach-Object { [string]$_ })
  if ($basisSet -contains 'HOSTNAME_INFERENCE_ONLY') {
    $strong = @(
      'CONFIRMED_DEPLOYMENT_DEVICE_OBSERVED_IN_SUBNET'
      'MULTIPLE_DEPLOYED_DEVICES_OBSERVED_IN_SUBNET'
      'SERIAL_ANCHORED_DEVICE_OBSERVATION'
      'DHCP_CORROBORATION'
      'DNS_CORROBORATION'
      'CMDB_CORROBORATION'
      'MULTIPLE_INDEPENDENT_DEPLOYMENT_RECORDS'
    )
    $hasStrong = $false
    foreach ($code in $basisSet) {
      if ($strong -contains $code) { $hasStrong = $true; break }
    }
    if (-not $hasStrong) { return $true }
  }

  $subnetEvidence = @()
  foreach ($ev in @($Evidence)) {
    $supports = Get-CybernetTopologySupports -Evidence $ev
    if ($supports -contains 'SUBNET') { $subnetEvidence += ,$ev }
  }
  if ($subnetEvidence.Count -eq 0) { return $false }
  foreach ($ev in $subnetEvidence) {
    $authority = [string](Get-CybernetTopologyProperty -Object $ev -Name 'authority')
    if ($authority -ne 'INFERENTIAL') { return $false }
  }
  return ($basisSet -contains 'HOSTNAME_INFERENCE_ONLY')
}

function Test-CybernetTopologyDiscoveryOnlySubnet {
  param(
    [string[]]$Basis,
    [object[]]$Evidence
  )
  $basisSet = @($Basis | ForEach-Object { [string]$_ })
  if ($basisSet -contains 'NETWORK_DISCOVERY_ONLY') {
    $strong = @(
      'CONFIRMED_DEPLOYMENT_DEVICE_OBSERVED_IN_SUBNET'
      'MULTIPLE_DEPLOYED_DEVICES_OBSERVED_IN_SUBNET'
      'SERIAL_ANCHORED_DEVICE_OBSERVATION'
      'MULTIPLE_INDEPENDENT_DEPLOYMENT_RECORDS'
      'DHCP_CORROBORATION'
      'DNS_CORROBORATION'
      'CMDB_CORROBORATION'
    )
    $hasStrong = $false
    foreach ($code in $basisSet) {
      if ($strong -contains $code) { $hasStrong = $true; break }
    }
    if (-not $hasStrong) { return $true }
  }

  $subnetEvidence = @()
  foreach ($ev in @($Evidence)) {
    $supports = Get-CybernetTopologySupports -Evidence $ev
    if ($supports -contains 'SUBNET') { $subnetEvidence += ,$ev }
  }
  if ($subnetEvidence.Count -eq 0) { return $false }
  foreach ($ev in $subnetEvidence) {
    $authority = [string](Get-CybernetTopologyProperty -Object $ev -Name 'authority')
    if ($authority -ne 'DISCOVERY_ONLY') { return $false }
  }
  return $true
}

function Get-CybernetTopologyObservationAgeDays {
  param(
    [object]$LastObserved,
    [datetime]$AsOf
  )
  if ($null -eq $LastObserved) { return $null }
  $dateText = [string](Get-CybernetTopologyProperty -Object $LastObserved -Name 'date')
  if ([string]::IsNullOrWhiteSpace($dateText)) { return $null }
  $parsed = [datetime]::MinValue
  if (-not [datetime]::TryParseExact(
      $dateText,
      'yyyy-MM-dd',
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::None,
      [ref]$parsed
    )) {
    return $null
  }
  $span = $AsOf.Date - $parsed.Date
  return [int][Math]::Floor($span.TotalDays)
}

function Test-CybernetTopologyConfirmedDeviceAnchor {
  param([object]$Evidence)
  $anchor = Get-CybernetTopologyProperty -Object $Evidence -Name 'device_anchor'
  if ($null -eq $anchor) { return $false }
  $key = [string](Get-CybernetTopologyProperty -Object $anchor -Name 'device_key')
  if ([string]::IsNullOrWhiteSpace($key)) { return $false }
  $status = [string](Get-CybernetTopologyProperty -Object $anchor -Name 'deployment_status')
  return ($status -eq 'CONFIRMED_DEPLOYED')
}

function New-CybernetTopologyEligibilityResult {
  param(
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][datetime]$EvaluatedAt,
    [string[]]$ReasonCodes = @(),
    [string[]]$BlockingReasonCodes = @(),
    [string]$SupersededBySubnetId = $null
  )
  $result = [ordered]@{
    status                 = $Status
    evaluated_at           = $EvaluatedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    reason_codes           = @($ReasonCodes | Select-Object -Unique)
    blocking_reason_codes  = @($BlockingReasonCodes | Select-Object -Unique)
  }
  if (-not [string]::IsNullOrWhiteSpace($SupersededBySubnetId)) {
    $result['superseded_by_subnet_id'] = $SupersededBySubnetId
  }
  elseif ($Status -eq 'SUPERSEDED') {
    $result['superseded_by_subnet_id'] = $null
  }
  return [pscustomobject]$result
}

function Get-TargetedPassEligibility {
  <#
  .SYNOPSIS
    Compute targeted_pass_eligibility for one subnet object.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Subnet,
    [Parameter(Mandatory)][object]$Policy,
    [datetime]$AsOf = (Get-Date).ToUniversalTime()
  )

  $targeted = Get-CybernetTopologyProperty -Object $Policy -Name 'targeted_pass'
  if ($null -eq $targeted) {
    throw 'Policy.targeted_pass is required.'
  }

  $cidr = [string](Get-CybernetTopologyProperty -Object $Subnet -Name 'cidr')
  $confidence = Get-CybernetTopologyProperty -Object $Subnet -Name 'subnet_confidence'
  $classification = [string](Get-CybernetTopologyProperty -Object $confidence -Name 'classification')
  $basis = @(Get-CybernetTopologyProperty -Object $confidence -Name 'basis')
  $evidence = @(Get-CybernetTopologyProperty -Object $Subnet -Name 'deployment_evidence')
  $lastObserved = Get-CybernetTopologyProperty -Object $Subnet -Name 'last_observed'
  $supersededBy = [string](Get-CybernetTopologyProperty -Object $Subnet -Name 'superseded_by_subnet_id')

  $allowedConfidence = @(Get-CybernetTopologyProperty -Object $targeted -Name 'allowed_confidence')
  $mediumRequiresIndependent = [bool](Get-CybernetTopologyProperty -Object $targeted -Name 'medium_requires_independent_corroboration')
  $requireLastObserved = [bool](Get-CybernetTopologyProperty -Object $targeted -Name 'require_last_observed')
  $maxAgeDays = [int](Get-CybernetTopologyProperty -Object $targeted -Name 'max_observation_age_days')
  $rejectRelocation = [bool](Get-CybernetTopologyProperty -Object $targeted -Name 'reject_if_relocation_evidence_exists')
  $rejectHostnameOnly = [bool](Get-CybernetTopologyProperty -Object $targeted -Name 'reject_if_subnet_is_only_inferred_from_hostname')
  $rejectDiscoveryOnly = [bool](Get-CybernetTopologyProperty -Object $targeted -Name 'reject_if_only_network_discovery_supports_subnet')

  $reasons = New-Object System.Collections.Generic.List[string]
  $blocking = New-Object System.Collections.Generic.List[string]

  if (-not [string]::IsNullOrWhiteSpace($supersededBy)) {
    [void]$reasons.Add('CONFIRMED_DEVICE_RELOCATED')
    [void]$blocking.Add('SUPERSEDED_BY_NEWER_SUBNET')
    return (New-CybernetTopologyEligibilityResult `
        -Status 'SUPERSEDED' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking `
        -SupersededBySubnetId $supersededBy)
  }

  if ($classification -eq 'CONFLICTING' -or ($basis -contains 'RELOCATION_CONFLICT')) {
    [void]$reasons.Add('AUTHORITATIVE_PLACEMENT_CONFLICT')
    [void]$blocking.Add('CONFLICTING_SUBNET_EVIDENCE')
    if ($rejectRelocation -and ($basis -contains 'RELOCATION_CONFLICT')) {
      [void]$blocking.Add('RELOCATION_EVIDENCE_PRESENT')
    }
    return (New-CybernetTopologyEligibilityResult `
        -Status 'CONFLICTING' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }

  if (-not (Test-CybernetTopologyValidCidr -Cidr $cidr)) {
    [void]$blocking.Add('INVALID_CIDR')
    return (New-CybernetTopologyEligibilityResult `
        -Status 'NOT_ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }
  [void]$reasons.Add('VALID_CIDR')

  $hostnameOnly = Test-CybernetTopologyHostnameOnlySubnet -Basis $basis -Evidence $evidence
  if ($rejectHostnameOnly -and $hostnameOnly) {
    [void]$blocking.Add('HOSTNAME_INFERENCE_ONLY')
    return (New-CybernetTopologyEligibilityResult `
        -Status 'NOT_ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }

  $discoveryOnly = Test-CybernetTopologyDiscoveryOnlySubnet -Basis $basis -Evidence $evidence
  if ($rejectDiscoveryOnly -and $discoveryOnly) {
    [void]$blocking.Add('NETWORK_DISCOVERY_ONLY')
    return (New-CybernetTopologyEligibilityResult `
        -Status 'NOT_ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }

  if (-not (Test-CybernetTopologySubnetLinkedDeploymentProof -Evidence $evidence)) {
    $anySiteProof = $false
    foreach ($ev in $evidence) {
      if (Test-CybernetTopologyDeploymentProof -Evidence $ev) {
        $anySiteProof = $true
        break
      }
    }
    if ($anySiteProof) {
      [void]$blocking.Add('NO_SUBNET_LINKED_DEPLOYMENT_PROOF')
    }
    else {
      [void]$blocking.Add('NO_DEPLOYMENT_PROOF')
    }
    return (New-CybernetTopologyEligibilityResult `
        -Status 'NOT_ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }
  [void]$reasons.Add('CONFIRMED_DEPLOYMENT_EVIDENCE')
  [void]$reasons.Add('SUBNET_LINKED_DEPLOYMENT_PROOF')

  if ($requireLastObserved) {
    if ($null -eq $lastObserved) {
      [void]$blocking.Add('MISSING_LAST_OBSERVED')
      return (New-CybernetTopologyEligibilityResult `
          -Status 'STALE' `
          -EvaluatedAt $AsOf `
          -ReasonCodes $reasons `
          -BlockingReasonCodes $blocking)
    }
    $ageDays = Get-CybernetTopologyObservationAgeDays -LastObserved $lastObserved -AsOf $AsOf
    if ($null -eq $ageDays) {
      [void]$blocking.Add('INVALID_LAST_OBSERVED')
      return (New-CybernetTopologyEligibilityResult `
          -Status 'STALE' `
          -EvaluatedAt $AsOf `
          -ReasonCodes $reasons `
          -BlockingReasonCodes $blocking)
    }
    if ($ageDays -lt 0) {
      [void]$blocking.Add('FUTURE_LAST_OBSERVED')
      return (New-CybernetTopologyEligibilityResult `
          -Status 'STALE' `
          -EvaluatedAt $AsOf `
          -ReasonCodes $reasons `
          -BlockingReasonCodes $blocking)
    }
    if ($ageDays -gt $maxAgeDays) {
      [void]$blocking.Add('OBSERVATION_STALE')
      return (New-CybernetTopologyEligibilityResult `
          -Status 'STALE' `
          -EvaluatedAt $AsOf `
          -ReasonCodes $reasons `
          -BlockingReasonCodes $blocking)
    }
    [void]$reasons.Add('RECENT_OBSERVATION')
  }

  if ($allowedConfidence -notcontains $classification) {
    [void]$blocking.Add('CONFIDENCE_NOT_ALLOWED')
    return (New-CybernetTopologyEligibilityResult `
        -Status 'NOT_ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }

  $independent = Test-CybernetTopologyIndependentSubnetCorroboration -Evidence $evidence

  if ($classification -eq 'HIGH') {
    [void]$reasons.Add('HIGH_SUBNET_CONFIDENCE')
    if (-not ($basis -contains 'RELOCATION_CONFLICT')) {
      [void]$reasons.Add('NO_RELOCATION_CONFLICT')
    }
    return (New-CybernetTopologyEligibilityResult `
        -Status 'ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }

  if ($classification -eq 'MEDIUM') {
    [void]$reasons.Add('MEDIUM_SUBNET_CONFIDENCE')
    if ($mediumRequiresIndependent -and -not $independent) {
      [void]$blocking.Add('INSUFFICIENT_INDEPENDENT_CORROBORATION')
      return (New-CybernetTopologyEligibilityResult `
          -Status 'REVIEW_REQUIRED' `
          -EvaluatedAt $AsOf `
          -ReasonCodes $reasons `
          -BlockingReasonCodes $blocking)
    }
    if ($independent) {
      [void]$reasons.Add('INDEPENDENT_SUBNET_CORROBORATION')
    }
    if (-not ($basis -contains 'RELOCATION_CONFLICT')) {
      [void]$reasons.Add('NO_RELOCATION_CONFLICT')
    }
    return (New-CybernetTopologyEligibilityResult `
        -Status 'ELIGIBLE' `
        -EvaluatedAt $AsOf `
        -ReasonCodes $reasons `
        -BlockingReasonCodes $blocking)
  }

  [void]$blocking.Add('CONFIDENCE_BELOW_TARGETED_PASS')
  return (New-CybernetTopologyEligibilityResult `
      -Status 'NOT_ELIGIBLE' `
      -EvaluatedAt $AsOf `
      -ReasonCodes $reasons `
      -BlockingReasonCodes $blocking)
}

function Update-CybernetTopologyRegistryEligibility {
  <#
  .SYNOPSIS
    Recompute targeted_pass_eligibility for every subnet in a registry object.
    Never trusts a manually declared ELIGIBLE status.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Registry,
    [datetime]$AsOf = (Get-Date).ToUniversalTime()
  )

  $policy = Get-CybernetTopologyProperty -Object $Registry -Name 'policy'
  if ($null -eq $policy) {
    throw 'Registry.policy is required.'
  }

  $sites = @(Get-CybernetTopologyProperty -Object $Registry -Name 'sites')
  foreach ($site in $sites) {
    $siteStatus = [string](Get-CybernetTopologyProperty -Object $site -Name 'site_status')
    $organizationId = [string](Get-CybernetTopologyProperty -Object $site -Name 'organization_id')
    $subnets = @(Get-CybernetTopologyProperty -Object $site -Name 'subnets')
    foreach ($subnet in $subnets) {
      if ([string]::IsNullOrWhiteSpace($organizationId)) {
        $eligibility = New-CybernetTopologyEligibilityResult `
          -Status 'NOT_ELIGIBLE' `
          -EvaluatedAt $AsOf `
          -ReasonCodes @() `
          -BlockingReasonCodes @('MISSING_ORGANIZATION_ID')
      }
      elseif ($siteStatus -ne 'ACTIVE') {
        $eligibility = New-CybernetTopologyEligibilityResult `
          -Status 'NOT_ELIGIBLE' `
          -EvaluatedAt $AsOf `
          -ReasonCodes @() `
          -BlockingReasonCodes @('SITE_NOT_ACTIVE')
      }
      else {
        $eligibility = Get-TargetedPassEligibility -Subnet $subnet -Policy $policy -AsOf $AsOf
      }

      $existing = $subnet.PSObject.Properties['targeted_pass_eligibility']
      if ($null -eq $existing) {
        $subnet | Add-Member -NotePropertyName targeted_pass_eligibility -NotePropertyValue $eligibility
      }
      else {
        $subnet.targeted_pass_eligibility = $eligibility
      }
    }
  }
  return $Registry
}

Export-ModuleMember -Function @(
  'Get-TargetedPassEligibility'
  'Update-CybernetTopologyRegistryEligibility'
  'Test-CybernetTopologyValidCidr'
  'Test-CybernetTopologyIndependentSubnetCorroboration'
  'Test-CybernetTopologySubnetLinkedDeploymentProof'
)
