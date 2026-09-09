#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
  Offline proof that the Cybernet topology survey loop is idempotent, accumulates
  probe context between runs, and supports technician-to-technician evidence sharing.
#>

BeforeAll {
  $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $script:sessionModule = Join-Path $script:repoRoot 'scripts\SasCybernetTopologySession.psm1'
  $script:entryScript = Join-Path $script:repoRoot 'scripts\Invoke-SasCybernetTopologySession.ps1'
  $script:launcher = Join-Path $script:repoRoot 'Run-CybernetTopologySurvey.cmd'
  $script:bundleSchema = Join-Path $script:repoRoot 'Config\Cybernet\sas-cybernet-topology-evidence-bundle.v1.schema.json'
  $script:goldenRegistry = Join-Path $script:repoRoot 'Tests\Fixtures\CybernetTopology\golden.registry.json'
  $script:startHere = Join-Path $script:repoRoot 'START-HERE-CYBERNET-TOPOLOGY-SURVEY.md'

  Import-Module -Name $script:sessionModule -Force

  $script:asOf = [datetime]::Parse('2026-09-09T12:00:00Z').ToUniversalTime()

  function New-TestSubnetEvidence {
    param(
      [string]$EvidenceId,
      [string]$SourceType = 'DEPLOYMENT_TRACKER',
      [string]$Authority = 'AUTHORITATIVE',
      [string[]]$Supports = @('SITE', 'SUBNET'),
      [string]$ObservedAt = '2026-09-01T10:00:00Z',
      [string]$DeviceKey = 'dev-1',
      [string]$SourceReference = 'fixture://evidence'
    )
    return [ordered]@{
      evidence_id      = $EvidenceId
      evidence_type    = 'CONFIRMED_DEPLOYMENT'
      source_type      = $SourceType
      source_reference = $SourceReference
      observed_at      = $ObservedAt
      device_anchor    = [ordered]@{
        device_key                 = $DeviceKey
        deployment_status          = 'CONFIRMED_DEPLOYED'
        identity_strength          = 'SERIAL_ANCHORED'
        hostname_reference_present = $true
        serial_reference_present   = $true
        model_reference_present    = $false
      }
      supports         = $Supports
      authority        = $Authority
      notes            = $null
    }
  }

  function New-TestRegistry {
    param(
      [string]$SubnetId = 'TEST:10.10.10.0/24',
      [string]$Cidr = '10.10.10.0/24',
      [string]$Classification = 'HIGH',
      [object[]]$Evidence
    )
    return [ordered]@{
      schema_version = 'sas-cybernet-deployment-topology-registry/v1'
      generated_at   = '2026-09-09T00:00:00Z'
      policy         = (New-SasCybernetTopologyEmptyRegistry -AsOf $script:asOf)['policy']
      sites          = @(
        [ordered]@{
          site_id         = 'SITE-TEST'
          organization_id = 'ORG-TEST'
          site_name       = 'Test Campus'
          site_status     = 'ACTIVE'
          subnets         = @(
            [ordered]@{
              subnet_id           = $SubnetId
              cidr                = $Cidr
              subnet_confidence   = [ordered]@{
                classification = $Classification
                score          = 0.9
                basis          = @('CONFIRMED_DEPLOYMENT_DEVICE_OBSERVED_IN_SUBNET')
                calculated_at  = '2026-09-01T00:00:00Z'
              }
              last_observed       = [ordered]@{
                date                = '2026-09-01'
                source_evidence_ids = @('EV-1')
              }
              deployment_evidence = $Evidence
              targeted_pass_budget = [ordered]@{
                discovery_profile                 = 'windows_pc_signature_json'
                allowed_ports                     = @(135, 445)
                retries                           = 0
                metadata_requires_signature_match = $true
                metadata_requires_windows_client  = $true
                broad_service_enumeration_allowed = $false
              }
            }
          )
        }
      )
    }
  }
}

Describe 'Topology session bootstrap is idempotent' {
  It 'creates the session on first call and reuses it on the second' {
    $root = Join-Path $TestDrive 'session-a'
    $first = Initialize-SasCybernetTopologySession -RepoRoot $script:repoRoot -SessionRoot $root -AsOf $script:asOf
    $first.FirstRun | Should -BeTrue
    Test-Path -LiteralPath $first.Paths.RegistryPath | Should -BeTrue
    Test-Path -LiteralPath $first.Paths.InboxDir | Should -BeTrue
    Test-Path -LiteralPath $first.Paths.OutboxDir | Should -BeTrue
    Test-Path -LiteralPath $first.Paths.IngestDir | Should -BeTrue

    $second = Initialize-SasCybernetTopologySession -RepoRoot $script:repoRoot -SessionRoot $root -AsOf $script:asOf
    $second.FirstRun | Should -BeFalse
  }

  It 'seeds an empty registry that claims no locations' {
    $registry = New-SasCybernetTopologyEmptyRegistry -AsOf $script:asOf
    $registry['schema_version'] | Should -Be 'sas-cybernet-deployment-topology-registry/v1'
    @($registry['sites']).Count | Should -Be 0
    $registry['policy']['targeted_pass']['medium_requires_independent_corroboration'] | Should -BeTrue
  }
}

Describe 'Evidence merge accumulates context across probes' {
  It 'adds new evidence and deduplicates by evidence_id' {
    $base = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1'))
    $incoming = New-TestRegistry -Evidence @(
      (New-TestSubnetEvidence -EvidenceId 'EV-1'),
      (New-TestSubnetEvidence -EvidenceId 'EV-2' -SourceType 'DHCP' -Authority 'CORROBORATING' -Supports @('SUBNET'))
    )

    $result = Merge-SasCybernetTopologyRegistry -Registry $base -Incoming $incoming -SourceLabel 'test'
    $result.Stats.evidence_added | Should -Be 1
    $subnet = $result.Registry.sites[0].subnets[0]
    @($subnet.deployment_evidence).Count | Should -Be 2
  }

  It 'lets a newer observation of the same evidence_id win' {
    $base = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-01-01T00:00:00Z'))
    $incoming = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-09-05T00:00:00Z'))

    $result = Merge-SasCybernetTopologyRegistry -Registry $base -Incoming $incoming -SourceLabel 'test'
    $result.Stats.evidence_updated | Should -Be 1
    $subnet = $result.Registry.sites[0].subnets[0]
    @($subnet.deployment_evidence).Count | Should -Be 1
    $subnet.deployment_evidence[0].observed_at | Should -Be '2026-09-05T00:00:00Z'
  }

  It 'keeps timestamps in canonical UTC form across repeated merges' {
    $registry = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-09-05T00:00:00Z'))
    $incoming = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-2' -ObservedAt '2026-09-06T00:00:00Z'))

    for ($i = 0; $i -lt 3; $i++) {
      $registry = (Merge-SasCybernetTopologyRegistry -Registry $registry -Incoming $incoming -SourceLabel 'test').Registry
    }

    $subnet = $registry.sites[0].subnets[0]
    foreach ($ev in @($subnet.deployment_evidence)) {
      $ev.observed_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }
    $subnet.last_observed.date | Should -Be '2026-09-06'
  }

  It 'counts evidence carried in by a brand new site instead of reporting zero' {
    $base = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1'))
    $incoming = ConvertTo-SasTopologyMutable -InputObject (New-TestRegistry -Evidence @(
        (New-TestSubnetEvidence -EvidenceId 'EV-A'),
        (New-TestSubnetEvidence -EvidenceId 'EV-B')
      ))
    $incoming['sites'][0]['site_id'] = 'SITE-OTHER'

    $result = Merge-SasCybernetTopologyRegistry -Registry $base -Incoming $incoming -SourceLabel 'test'
    $result.Stats.sites_added | Should -Be 1
    $result.Stats.subnets_added | Should -Be 1
    $result.Stats.evidence_added | Should -Be 2
  }

  It 'refreshes last_observed from the newest merged evidence' {
    $base = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-01-01T00:00:00Z'))
    $incoming = New-TestRegistry -Evidence @(
      (New-TestSubnetEvidence -EvidenceId 'EV-9' -ObservedAt '2026-09-07T08:00:00Z')
    )

    $result = Merge-SasCybernetTopologyRegistry -Registry $base -Incoming $incoming -SourceLabel 'test'
    $subnet = $result.Registry.sites[0].subnets[0]
    $subnet.last_observed.date | Should -Be '2026-09-07'
    @($subnet.last_observed.source_evidence_ids) | Should -Contain 'EV-9'
  }

  It 'adds a whole new site when the incoming site_id is unknown' {
    $base = New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1'))
    $incoming = ConvertTo-SasTopologyMutable -InputObject (New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-5')))
    $incoming['sites'][0]['site_id'] = 'SITE-OTHER'

    $result = Merge-SasCybernetTopologyRegistry -Registry $base -Incoming $incoming -SourceLabel 'test'
    $result.Stats.sites_added | Should -Be 1
    @($result.Registry.sites).Count | Should -Be 2
  }
}

Describe 'Probe plan turns eligibility into the next bounded pass' {
  BeforeAll {
    Import-Module -Name (Join-Path $script:repoRoot 'DeploymentTracker\CybernetTopology.Eligibility.psm1') -Force
  }

  It 'emits eligible CIDRs with their bounded budget only' {
    $registry = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-09-01T10:00:00Z')))
    $registry = Update-CybernetTopologyRegistryEligibility -Registry $registry -AsOf $script:asOf
    $plan = New-SasCybernetTopologyProbePlan -Registry $registry

    $plan.PlanRows.Count | Should -Be 1
    $plan.PlanRows[0].Cidr | Should -Be '10.10.10.0/24'
    $plan.PlanRows[0].DiscoveryProfile | Should -Be 'windows_pc_signature_json'
    $plan.PlanRows[0].AllowedPorts | Should -Be '135,445'
    $plan.PlanRows[0].BudgetDeclared | Should -BeTrue
    $plan.ReviewRows.Count | Should -Be 0
  }

  It 'never treats a missing targeted_pass_budget as an unlimited budget' {
    $mutable = ConvertTo-SasTopologyMutable -InputObject (New-TestRegistry -Evidence @(
        (New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-09-01T10:00:00Z')
      ))
    $mutable['sites'][0]['subnets'][0].Remove('targeted_pass_budget')

    $registry = Update-CybernetTopologyRegistryEligibility `
      -Registry (ConvertTo-SasTopologyObject -InputObject $mutable) -AsOf $script:asOf
    $plan = New-SasCybernetTopologyProbePlan -Registry $registry

    $plan.PlanRows.Count | Should -Be 1
    $plan.PlanRows[0].DiscoveryProfile | Should -Be 'BUDGET_NOT_DECLARED'
    $plan.PlanRows[0].AllowedPorts | Should -Be 'BUDGET_NOT_DECLARED'
    $plan.PlanRows[0].Retries | Should -Be 'BUDGET_NOT_DECLARED'
    $plan.PlanRows[0].BudgetDeclared | Should -BeFalse
  }

  It 'routes a blocked subnet to review with the evidence that would unblock it' {
    $registry = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Classification 'MEDIUM' -Evidence @(
        (New-TestSubnetEvidence -EvidenceId 'EV-1' -ObservedAt '2026-09-01T10:00:00Z')
      ))
    $registry = Update-CybernetTopologyRegistryEligibility -Registry $registry -AsOf $script:asOf
    $plan = New-SasCybernetTopologyProbePlan -Registry $registry

    $plan.PlanRows.Count | Should -Be 0
    $plan.ReviewRows.Count | Should -Be 1
    $plan.ReviewRows[0].Status | Should -Be 'REVIEW_REQUIRED'
    $plan.ReviewRows[0].NextEvidenceNeeded | Should -Match 'different source_type'
  }

  It 'maps every blocking code to actionable next evidence' {
    foreach ($code in @(
        'INSUFFICIENT_INDEPENDENT_CORROBORATION',
        'NO_SUBNET_LINKED_DEPLOYMENT_PROOF',
        'NO_DEPLOYMENT_PROOF',
        'OBSERVATION_STALE',
        'FUTURE_LAST_OBSERVED',
        'HOSTNAME_INFERENCE_ONLY',
        'NETWORK_DISCOVERY_ONLY',
        'CONFLICTING_SUBNET_EVIDENCE',
        'SUPERSEDED_BY_NEWER_SUBNET',
        'SITE_NOT_ACTIVE',
        'MISSING_ORGANIZATION_ID',
        'INVALID_CIDR'
      )) {
      $hint = Get-SasTopologyNextEvidenceHint -BlockingCodes @($code)
      $hint | Should -Not -BeNullOrEmpty
      $hint | Should -Not -Be 'Review the blocking reason codes and supply the missing evidence.'
    }
  }
}

Describe 'Technician-to-technician bundle exchange' {
  It 'exports a bundle that strips machine-local paths and computed eligibility' {
    $registry = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @(
        (New-TestSubnetEvidence -EvidenceId 'EV-1' -SourceReference 'C:\Users\somebody\Desktop\tracker.xlsx')
      ))
    $registry = Update-CybernetTopologyRegistryEligibility -Registry $registry -AsOf $script:asOf

    $bundlePath = Join-Path $TestDrive 'bundle.json'
    $result = Export-SasCybernetTopologyBundle -Registry $registry -Path $bundlePath -RunId 'RUN1' -AsOf $script:asOf
    $result.EvidenceCount | Should -Be 1

    $bundle = Get-Content -LiteralPath $bundlePath -Raw | ConvertFrom-Json
    $bundle.schema_version | Should -Be 'sas-cybernet-topology-evidence-bundle/v1'
    $bundle.contains_operator_local_data | Should -BeTrue
    $bundle.registry.sites[0].subnets[0].deployment_evidence[0].source_reference | Should -Be 'operator-local-reference'
    $bundle.registry.sites[0].subnets[0].PSObject.Properties.Name | Should -Not -Contain 'targeted_pass_eligibility'
  }

  It 'imports a colleague bundle and merges its evidence' {
    $mine = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-MINE')))
    $theirs = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @(
        (New-TestSubnetEvidence -EvidenceId 'EV-THEIRS' -SourceType 'DHCP' -Authority 'CORROBORATING' -Supports @('SUBNET'))
      ))

    $bundlePath = Join-Path $TestDrive 'colleague.json'
    Export-SasCybernetTopologyBundle -Registry $theirs -Path $bundlePath -RunId 'RUN-THEIRS' -AsOf $script:asOf | Out-Null

    $merged = Import-SasCybernetTopologyBundle -Registry $mine -Path $bundlePath
    $ids = @($merged.Registry.sites[0].subnets[0].deployment_evidence | ForEach-Object { $_.evidence_id })
    $ids | Should -Contain 'EV-MINE'
    $ids | Should -Contain 'EV-THEIRS'
  }

  It 'imports a raw registry file as well as a bundle' {
    $mine = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-MINE')))
    $rawPath = Join-Path $TestDrive 'raw-registry.json'
    Write-SasTopologyJsonFile -Path $rawPath -InputObject (New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-RAW')))

    $merged = Import-SasCybernetTopologyBundle -Registry $mine -Path $rawPath
    $ids = @($merged.Registry.sites[0].subnets[0].deployment_evidence | ForEach-Object { $_.evidence_id })
    $ids | Should -Contain 'EV-RAW'
  }

  It 'refuses an unknown schema instead of silently merging junk' {
    $mine = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @((New-TestSubnetEvidence -EvidenceId 'EV-MINE')))
    $badPath = Join-Path $TestDrive 'bad.json'
    Set-Content -LiteralPath $badPath -Value '{ "schema_version": "something-else/v9" }' -Encoding UTF8
    { Import-SasCybernetTopologyBundle -Registry $mine -Path $badPath } | Should -Throw '*Unsupported schema_version*'
  }
}

Describe 'Run delta reports what changed between clicks' {
  It 'reports new subnets and newly eligible rows on the first comparison' {
    $current = [ordered]@{ 'A' = 'ELIGIBLE'; 'B' = 'REVIEW_REQUIRED' }
    $delta = Get-SasCybernetTopologyDelta -PreviousStatusById $null -CurrentStatusById $current
    $delta.HasPreviousRun | Should -BeFalse
    $delta.NewSubnets | Should -Contain 'A'
    $delta.NewlyEligible | Should -Contain 'A'
  }

  It 'still knows a previous run happened when that run had no subnets yet' {
    $delta = Get-SasCybernetTopologyDelta `
      -PreviousStatusById ([ordered]@{}) `
      -CurrentStatusById ([ordered]@{ 'A' = 'ELIGIBLE' }) `
      -HadPreviousRun
    $delta.HasPreviousRun | Should -BeTrue
    $delta.NewSubnets | Should -Contain 'A'
  }

  It 'reports promotions and regressions against the previous run' {
    $previous = [ordered]@{ 'A' = 'REVIEW_REQUIRED'; 'B' = 'ELIGIBLE' }
    $current = [ordered]@{ 'A' = 'ELIGIBLE'; 'B' = 'STALE' }
    $delta = Get-SasCybernetTopologyDelta -PreviousStatusById $previous -CurrentStatusById $current
    $delta.NewlyEligible | Should -Contain 'A'
    $delta.NoLongerEligible | Should -Contain 'B'
    $delta.Changed.Count | Should -Be 2
  }
}

Describe 'End-to-end iteration through the entry script' {
  BeforeAll {
    $script:e2eRoot = Join-Path $TestDrive 'session-e2e'
  }

  It 'first click bootstraps and publishes an empty but valid plan' {
    & $script:entryScript -SessionRoot $script:e2eRoot -AsOf $script:asOf | Out-Null
    $LASTEXITCODE | Should -Be 0

    $paths = Get-SasCybernetTopologySessionPath -RepoRoot $script:repoRoot -SessionRoot $script:e2eRoot
    Test-Path -LiteralPath $paths.RegistryPath | Should -BeTrue
    Test-Path -LiteralPath $paths.StatePath | Should -BeTrue

    $runDir = Get-ChildItem -LiteralPath $paths.RunsDir -Directory | Select-Object -First 1
    Test-Path -LiteralPath (Join-Path $runDir.FullName 'operator_handoff.txt') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $runDir.FullName 'next_probe_targets.csv') | Should -BeTrue

    $summary = Get-Content -LiteralPath (Join-Path $runDir.FullName 'iteration_summary.json') -Raw | ConvertFrom-Json
    $summary.first_run | Should -BeTrue
    $summary.network_activity_performed | Should -BeFalse
    $summary.subnets_total | Should -Be 0
  }

  It 'second click absorbs inbox evidence and reports it as newly eligible' {
    $paths = Get-SasCybernetTopologySessionPath -RepoRoot $script:repoRoot -SessionRoot $script:e2eRoot
    $incoming = Join-Path $paths.InboxDir 'colleague.json'
    $theirs = ConvertTo-SasTopologyObject -InputObject (New-TestRegistry -Evidence @(
        (New-TestSubnetEvidence -EvidenceId 'EV-SHARED' -ObservedAt '2026-09-08T10:00:00Z')
      ))
    Export-SasCybernetTopologyBundle -Registry $theirs -Path $incoming -RunId 'RUN-THEIRS' -AsOf $script:asOf | Out-Null

    $later = $script:asOf.AddMinutes(5)
    & $script:entryScript -SessionRoot $script:e2eRoot -AsOf $later | Out-Null
    $LASTEXITCODE | Should -Be 0

    Test-Path -LiteralPath $incoming | Should -BeFalse

    $runDir = Get-ChildItem -LiteralPath $paths.RunsDir -Directory | Sort-Object Name | Select-Object -Last 1
    $summary = Get-Content -LiteralPath (Join-Path $runDir.FullName 'iteration_summary.json') -Raw | ConvertFrom-Json
    $summary.first_run | Should -BeFalse
    $summary.subnets_total | Should -Be 1
    $summary.eligible_probe_targets | Should -Be 1
    @($summary.newly_eligible_subnet_ids) | Should -Contain 'TEST:10.10.10.0/24'

    $planRows = Import-Csv -LiteralPath (Join-Path $runDir.FullName 'next_probe_targets.csv')
    @($planRows).Count | Should -Be 1
    $planRows[0].Cidr | Should -Be '10.10.10.0/24'

    Test-Path -LiteralPath $summary.shareable_bundle_path | Should -BeTrue

    # The first run had no subnets; the second run must still recognise it as a prior run
    # and must credit the evidence the new site brought with it.
    @($summary.sources_merged_this_run)[0].evidence_added | Should -Be 1
    $handoff = Get-Content -LiteralPath (Join-Path $runDir.FullName 'operator_handoff.txt') -Raw
    $handoff | Should -Not -Match 'No previous run to compare against'
    $handoff | Should -Match 'new subnet: TEST:10\.10\.10\.0/24'
    $handoff | Should -Match '\+1 evidence'
  }

  It 'third click with no new evidence is stable and reports no change' {
    $paths = Get-SasCybernetTopologySessionPath -RepoRoot $script:repoRoot -SessionRoot $script:e2eRoot
    $later = $script:asOf.AddMinutes(10)
    & $script:entryScript -SessionRoot $script:e2eRoot -AsOf $later | Out-Null
    $LASTEXITCODE | Should -Be 0

    $runDir = Get-ChildItem -LiteralPath $paths.RunsDir -Directory | Sort-Object Name | Select-Object -Last 1
    $summary = Get-Content -LiteralPath (Join-Path $runDir.FullName 'iteration_summary.json') -Raw | ConvertFrom-Json
    $summary.subnets_total | Should -Be 1
    $summary.eligible_probe_targets | Should -Be 1
    @($summary.status_changes).Count | Should -Be 0

    $handoff = Get-Content -LiteralPath (Join-Path $runDir.FullName 'operator_handoff.txt') -Raw
    $handoff | Should -Match 'No status changes'
    $handoff | Should -Match 'Run-CybernetTopologySurvey\.cmd'
  }
}

Describe 'Technician launcher contract' {
  It 'exists as one obvious double-click CMD' {
    Test-Path -LiteralPath $script:launcher -PathType Leaf | Should -BeTrue
    $cmd = Get-Content -LiteralPath $script:launcher -Raw
    $cmd | Should -Match 'SysAdminSuite - Cybernet Topology Survey'
    $cmd | Should -Match 'SAS_TOPOLOGY_ENTRYPOINT=TECHNICIAN_CMD'
    $cmd | Should -Match 'Safe to run as many times as you like'
  }

  It 'needs no arguments and defaults to the full iteration' {
    $cmd = Get-Content -LiteralPath $script:launcher -Raw
    $cmd | Should -Match 'set "SAS_ACTION=Status"'
    $cmd | Should -Match 'Invoke-SasCybernetTopologySession\.ps1'
    $cmd | Should -Match '-OpenResults'
  }

  It 'supports Export and Import without hand-built PowerShell' {
    $cmd = Get-Content -LiteralPath $script:launcher -Raw
    $cmd | Should -Match 'set "SAS_ACTION=Export"'
    $cmd | Should -Match 'set "SAS_ACTION=Import"'
    $cmd | Should -Match '-BundlePath'
  }

  It 'preserves failure exit state and tells the technician where evidence goes' {
    $cmd = Get-Content -LiteralPath $script:launcher -Raw
    $cmd | Should -Match 'set "SAS_EXIT=!ERRORLEVEL!"'
    $cmd | Should -Match 'exit /b %SAS_EXIT%'
    $cmd | Should -Match 'evidence\\CybernetTopology\\ingest'
    $cmd | Should -Match 'evidence\\CybernetTopology\\inbox'
    $cmd | Should -Match 'evidence\\CybernetTopology\\outbox'
    $cmd | Should -Match 'Do not rerun blindly'
  }

  It 'claims no network activity and no hardware identity decision' {
    $cmd = Get-Content -LiteralPath $script:launcher -Raw
    $cmd | Should -Match 'never touches the network'
    $cmd | Should -Match 'does not decide what a'
    $cmd | Should -Not -Match '(?i)naabu|nmap|Test-NetConnection|Invoke-WebRequest'
  }
}

Describe 'Session engine safety posture' {
  It 'performs no network calls anywhere in the engine or entry script' {
    foreach ($path in @($script:sessionModule, $script:entryScript)) {
      $content = Get-Content -LiteralPath $path -Raw
      $content | Should -Not -Match '(?i)Invoke-WebRequest|Invoke-RestMethod|Test-NetConnection|New-CimSession|Get-WmiObject|naabu|nmap'
    }
  }

  It 'parses without PowerShell syntax errors' {
    foreach ($path in @($script:sessionModule, $script:entryScript)) {
      $tokens = $null
      $errors = $null
      [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
      $errors | Should -BeNullOrEmpty
    }
  }

  It 'keeps session state under an ignored evidence root by default' {
    $paths = Get-SasCybernetTopologySessionPath -RepoRoot 'C:\repo'
    $paths.SessionRoot | Should -Be 'C:\repo\evidence\CybernetTopology'
    $ignore = Get-Content -LiteralPath (Join-Path $script:repoRoot '.gitignore') -Raw
    $ignore | Should -Match '(?m)^evidence/\*'
  }
}

Describe 'Bundle schema and operator documentation' {
  It 'publishes a bundle schema that forbids silent commits' {
    Test-Path -LiteralPath $script:bundleSchema | Should -BeTrue
    $schema = Get-Content -LiteralPath $script:bundleSchema -Raw | ConvertFrom-Json
    $schema.'$id' | Should -Be 'sas-cybernet-topology-evidence-bundle/v1'
    $schema.properties.contains_operator_local_data.const | Should -BeTrue
    $schema.required | Should -Contain 'registry'
  }

  It 'documents the repeatable click, the folders, and the sharing path' {
    Test-Path -LiteralPath $script:startHere | Should -BeTrue
    $doc = Get-Content -LiteralPath $script:startHere -Raw
    $doc | Should -Match 'Run-CybernetTopologySurvey\.cmd'
    $doc | Should -Match 'ingest'
    $doc | Should -Match 'inbox'
    $doc | Should -Match 'outbox'
    $doc | Should -Match '(?i)share'
    $doc | Should -Match '(?i)never commit'
  }
}
