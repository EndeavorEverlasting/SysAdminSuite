#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
  Structural contract tests for sas-cybernet-deployment-topology-registry/v1.
#>

BeforeAll {
  $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $script:schemaPath = Join-Path $script:repoRoot 'Config\Cybernet\sas-cybernet-deployment-topology-registry.v1.schema.json'
  $script:samplePath = Join-Path $script:repoRoot 'Config\Cybernet\sample.topology.registry.json'
  $script:docPath = Join-Path $script:repoRoot 'docs\CYBERNET_DEPLOYMENT_TOPOLOGY_REGISTRY.md'
  $script:modulePath = Join-Path $script:repoRoot 'DeploymentTracker\CybernetTopology.Eligibility.psm1'
}

Describe 'Cybernet topology registry contract' {
  It 'Schema, sample, module, and charter doc exist' {
    $script:schemaPath | Should -Exist
    $script:samplePath | Should -Exist
    $script:modulePath | Should -Exist
    $script:docPath | Should -Exist
  }

  It 'Schema declares expected version and vocab enums' {
    $schema = Get-Content -LiteralPath $script:schemaPath -Raw | ConvertFrom-Json
    $schema.'$id' | Should -Be 'sas-cybernet-deployment-topology-registry/v1'
    $schema.properties.schema_version.const | Should -Be 'sas-cybernet-deployment-topology-registry/v1'

    $sourceTypes = @($schema.'$defs'.source_type.enum)
    foreach ($needed in @(
        'DEPLOYMENT_TRACKER', 'TECHNICIAN_SIGNOFF', 'DEPLOYMENT_COMPLETION_REPORT',
        'SERIAL_INVENTORY', 'CMDB', 'SCCM_CONFIGMGR', 'ACTIVE_DIRECTORY',
        'DHCP', 'DNS', 'PRIOR_SAS_IDENTITY_EVIDENCE', 'PRIOR_SAS_NETWORK_EVIDENCE',
        'OPERATOR_CONFIRMED', 'OTHER_APPROVED_SOURCE'
      )) {
      $sourceTypes | Should -Contain $needed
    }

    $authorities = @($schema.'$defs'.authority.enum)
    foreach ($needed in @('AUTHORITATIVE', 'CORROBORATING', 'INFERENTIAL', 'DISCOVERY_ONLY')) {
      $authorities | Should -Contain $needed
    }

    $statuses = @($schema.'$defs'.eligibility_status.enum)
    foreach ($needed in @('ELIGIBLE', 'REVIEW_REQUIRED', 'STALE', 'CONFLICTING', 'NOT_ELIGIBLE', 'SUPERSEDED')) {
      $statuses | Should -Contain $needed
    }

    $evidenceProps = @($schema.'$defs'.evidence.properties.PSObject.Properties.Name)
    $evidenceProps | Should -Contain 'device_anchor'
    $evidenceProps | Should -Not -Contain 'device_reference'
  }

  It 'Sample registry uses schema_version and separates SITE-only from SITE+SUBNET evidence' {
    $sample = Get-Content -LiteralPath $script:samplePath -Raw | ConvertFrom-Json
    $sample.schema_version | Should -Be 'sas-cybernet-deployment-topology-registry/v1'
    $sample.policy.targeted_pass.medium_requires_independent_corroboration | Should -Be $true

    $eligible = $sample.sites[0].subnets | Where-Object { $_.subnet_id -like '*:10.20.30.0/24' } | Select-Object -First 1
    $siteOnly = $sample.sites[0].subnets | Where-Object { $_.subnet_id -like '*SITE-ONLY' } | Select-Object -First 1

    $eligible | Should -Not -BeNullOrEmpty
    $siteOnly | Should -Not -BeNullOrEmpty

    $eligibleSupports = @($eligible.deployment_evidence | ForEach-Object { $_.supports }) -join ','
    $eligibleSupports | Should -Match 'SUBNET'
    $eligible.targeted_pass_budget.discovery_profile | Should -Be 'windows_pc_signature_json'
    @($eligible.targeted_pass_budget.allowed_ports) | Should -Be @(135, 445)
    $eligible.targeted_pass_budget.broad_service_enumeration_allowed | Should -Be $false

    $siteOnlySupports = @($siteOnly.deployment_evidence[0].supports)
    $siteOnlySupports | Should -Contain 'SITE'
    $siteOnlySupports | Should -Not -Contain 'SUBNET'
  }

  It 'Charter doc freezes the one-question scope and deferred extractor boundary' {
    $doc = Get-Content -LiteralPath $script:docPath -Raw
    $doc | Should -Match 'One question only'
    $doc | Should -Match 'does \*\*not\*\* decide whether a host is a Cybernet'
    $doc | Should -Match 'Independent corroboration'
    $doc | Should -Match 'Deferred: tracker extractor'
    $doc | Should -Match 'Neuron IP'
  }

  It 'Eligibility module parses without syntax errors' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script:modulePath, [ref]$tokens, [ref]$errors) | Out-Null
    $errors | Should -BeNullOrEmpty
  }
}
