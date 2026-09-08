#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
  Offline eligibility regression for sas-cybernet-deployment-topology-registry/v1.
#>

BeforeAll {
  $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $script:modulePath = Join-Path $script:repoRoot 'DeploymentTracker\CybernetTopology.Eligibility.psm1'
  $script:goldenPath = Join-Path $script:repoRoot 'Tests\Fixtures\CybernetTopology\golden.registry.json'
  $script:samplePath = Join-Path $script:repoRoot 'Config\Cybernet\sample.topology.registry.json'
  Import-Module -Name $script:modulePath -Force
  $script:asOf = [datetime]::Parse('2026-09-08T00:00:00Z').ToUniversalTime()
}

Describe 'Get-TargetedPassEligibility golden matrix' {
  BeforeAll {
    $script:golden = Get-Content -LiteralPath $script:goldenPath -Raw | ConvertFrom-Json
    $script:policy = $script:golden.policy
    $script:byId = @{}
    foreach ($site in @($script:golden.sites)) {
      foreach ($subnet in @($site.subnets)) {
        $script:byId[$subnet.subnet_id] = $subnet
      }
    }
  }

  It 'HIGH recent authoritative subnet is ELIGIBLE' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:high-eligible'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'ELIGIBLE'
    $result.reason_codes | Should -Contain 'HIGH_SUBNET_CONFIDENCE'
    $result.reason_codes | Should -Contain 'CONFIRMED_DEPLOYMENT_EVIDENCE'
    $result.blocking_reason_codes.Count | Should -Be 0
  }

  It 'MEDIUM with independent SUBNET corroboration is ELIGIBLE' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:medium-eligible'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'ELIGIBLE'
    $result.reason_codes | Should -Contain 'MEDIUM_SUBNET_CONFIDENCE'
    $result.reason_codes | Should -Contain 'INDEPENDENT_SUBNET_CORROBORATION'
  }

  It 'MEDIUM without independent corroboration is REVIEW_REQUIRED' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:medium-review'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'REVIEW_REQUIRED'
    $result.blocking_reason_codes | Should -Contain 'INSUFFICIENT_INDEPENDENT_CORROBORATION'
  }

  It 'Observation older than policy horizon is STALE' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:stale'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'STALE'
    $result.blocking_reason_codes | Should -Contain 'OBSERVATION_STALE'
  }

  It 'Conflicting classification is CONFLICTING' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:conflicting'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'CONFLICTING'
    $result.blocking_reason_codes | Should -Contain 'CONFLICTING_SUBNET_EVIDENCE'
  }

  It 'superseded_by_subnet_id yields SUPERSEDED and preserves pointer' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:superseded'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'SUPERSEDED'
    $result.superseded_by_subnet_id | Should -Be 'GOLDEN:high-eligible'
    $result.reason_codes | Should -Contain 'CONFIRMED_DEVICE_RELOCATED'
  }

  It 'Hostname-only subnet inference is NOT_ELIGIBLE' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:hostname-only'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'NOT_ELIGIBLE'
    $result.blocking_reason_codes | Should -Contain 'HOSTNAME_INFERENCE_ONLY'
  }

  It 'Discovery-only subnet support is NOT_ELIGIBLE' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:discovery-only'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'NOT_ELIGIBLE'
    $result.blocking_reason_codes | Should -Contain 'NETWORK_DISCOVERY_ONLY'
  }

  It 'Invalid CIDR is NOT_ELIGIBLE' {
    $result = Get-TargetedPassEligibility -Subnet $script:byId['GOLDEN:invalid-cidr'] -Policy $script:policy -AsOf $script:asOf
    $result.status | Should -Be 'NOT_ELIGIBLE'
    $result.blocking_reason_codes | Should -Contain 'INVALID_CIDR'
  }
}

Describe 'Update-CybernetTopologyRegistryEligibility' {
  It 'Overwrites placeholder eligibility on every golden subnet' {
    $registry = Get-Content -LiteralPath $script:goldenPath -Raw | ConvertFrom-Json
    Update-CybernetTopologyRegistryEligibility -Registry $registry -AsOf $script:asOf | Out-Null

    $expected = @{
      'GOLDEN:high-eligible'   = 'ELIGIBLE'
      'GOLDEN:medium-eligible' = 'ELIGIBLE'
      'GOLDEN:medium-review'   = 'REVIEW_REQUIRED'
      'GOLDEN:stale'           = 'STALE'
      'GOLDEN:conflicting'     = 'CONFLICTING'
      'GOLDEN:superseded'      = 'SUPERSEDED'
      'GOLDEN:hostname-only'   = 'NOT_ELIGIBLE'
      'GOLDEN:discovery-only'  = 'NOT_ELIGIBLE'
      'GOLDEN:invalid-cidr'    = 'NOT_ELIGIBLE'
    }

    foreach ($site in @($registry.sites)) {
      foreach ($subnet in @($site.subnets)) {
        $subnet.targeted_pass_eligibility.status | Should -Be $expected[$subnet.subnet_id]
        $subnet.targeted_pass_eligibility.status | Should -Not -Be 'PLACEHOLDER'
      }
    }
  }

  It 'Recomputes sample registry eligible and site-only rows' {
    $sample = Get-Content -LiteralPath $script:samplePath -Raw | ConvertFrom-Json
    # Poison stored statuses to prove recomputation.
    foreach ($site in @($sample.sites)) {
      foreach ($subnet in @($site.subnets)) {
        $subnet.targeted_pass_eligibility.status = 'ELIGIBLE'
        $subnet.targeted_pass_eligibility.blocking_reason_codes = @()
      }
    }

    Update-CybernetTopologyRegistryEligibility -Registry $sample -AsOf $script:asOf | Out-Null
    $eligible = $sample.sites[0].subnets | Where-Object { $_.cidr -eq '10.20.30.0/24' } | Select-Object -First 1
    $siteOnly = $sample.sites[0].subnets | Where-Object { $_.subnet_id -like '*SITE-ONLY' } | Select-Object -First 1
    $eligible.targeted_pass_eligibility.status | Should -Be 'ELIGIBLE'
    $siteOnly.targeted_pass_eligibility.status | Should -Be 'NOT_ELIGIBLE'
    $siteOnly.targeted_pass_eligibility.blocking_reason_codes | Should -Contain 'HOSTNAME_INFERENCE_ONLY'
  }

  It 'Ignores numeric score and budget when deciding eligibility' {
    $subnet = [pscustomobject]@{
      subnet_id = 'SCORE-IGNORED'
      cidr = '10.1.1.0/24'
      subnet_confidence = [pscustomobject]@{
        classification = 'HIGH'
        score = 0.01
        basis = @('CONFIRMED_DEPLOYMENT_DEVICE_OBSERVED_IN_SUBNET')
        calculated_at = '2026-09-08T00:00:00Z'
      }
      last_observed = [pscustomobject]@{
        date = '2026-08-01'
        source_evidence_ids = @('EV-1')
      }
      deployment_evidence = @(
        [pscustomobject]@{
          evidence_id = 'EV-1'
          evidence_type = 'CONFIRMED_DEPLOYMENT'
          source_type = 'DEPLOYMENT_TRACKER'
          source_reference = 'fixture://score'
          observed_at = '2026-08-01T00:00:00Z'
          supports = @('SITE', 'SUBNET')
          authority = 'AUTHORITATIVE'
          notes = $null
        }
      )
      targeted_pass_budget = [pscustomobject]@{
        discovery_profile = 'windows_pc_signature_json'
        allowed_ports = @(22, 80, 443)
        retries = 99
        metadata_requires_signature_match = $false
        metadata_requires_windows_client = $false
        broad_service_enumeration_allowed = $true
      }
    }

    $policy = (Get-Content -LiteralPath $script:samplePath -Raw | ConvertFrom-Json).policy
    $result = Get-TargetedPassEligibility -Subnet $subnet -Policy $policy -AsOf $script:asOf
    $result.status | Should -Be 'ELIGIBLE'
  }
}

Describe 'Independent corroboration helper' {
  It 'Requires distinct source_type and non-inferential authority' {
    $weak = @(
      [pscustomobject]@{ supports = @('SUBNET'); source_type = 'DHCP'; authority = 'CORROBORATING' }
      [pscustomobject]@{ supports = @('SUBNET'); source_type = 'DHCP'; authority = 'CORROBORATING' }
    )
    Test-CybernetTopologyIndependentSubnetCorroboration -Evidence $weak | Should -Be $false

    $inferOnly = @(
      [pscustomobject]@{ supports = @('SUBNET'); source_type = 'DHCP'; authority = 'INFERENTIAL' }
      [pscustomobject]@{ supports = @('SUBNET'); source_type = 'DNS'; authority = 'DISCOVERY_ONLY' }
    )
    Test-CybernetTopologyIndependentSubnetCorroboration -Evidence $inferOnly | Should -Be $false

    $ok = @(
      [pscustomobject]@{ supports = @('SUBNET'); source_type = 'DHCP'; authority = 'CORROBORATING' }
      [pscustomobject]@{ supports = @('SUBNET'); source_type = 'DNS'; authority = 'CORROBORATING' }
    )
    Test-CybernetTopologyIndependentSubnetCorroboration -Evidence $ok | Should -Be $true
  }
}
