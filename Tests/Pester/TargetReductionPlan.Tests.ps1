#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:planner = Join-Path $script:repoRoot 'survey\sas-target-reduction-plan.ps1'
    $script:bashPlanner = Join-Path $script:repoRoot 'survey\sas-target-reduction-plan.sh'
    $script:fixtureRoot = Join-Path $script:repoRoot 'survey\fixtures\target_reduction'
    $script:runId = 'pester-' + [guid]::NewGuid().ToString('N')
    $script:outputDirectory = Join-Path $script:repoRoot "survey\output\target_reduction\$($script:runId)"
    & $script:planner `
        -PriorProbeResults (Join-Path $script:fixtureRoot 'local_evidence.csv') `
        -LocationSubnetMap (Join-Path $script:fixtureRoot 'location_subnet_map.csv') `
        -RunId $script:runId `
        -AllowFixtures | Out-Null
    $script:summary = Get-Content -LiteralPath (Join-Path $script:outputDirectory 'target_reduction_summary.json') -Raw | ConvertFrom-Json
}

AfterAll {
    if (Test-Path -LiteralPath $script:outputDirectory) {
        Remove-Item -LiteralPath $script:outputDirectory -Recurse -Force
    }
}

Describe 'sas-target-reduction-plan.ps1' {
    It 'exists and parses' {
        $script:planner | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:planner, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'keeps the local transform contract wired to shared modules' {
        $content = Get-Content -LiteralPath $script:planner -Raw
        $content | Should -Match 'SasTargetIntake\.psm1'
        $content | Should -Match 'SasLowNoisePolicy\.psm1'
        $content | Should -Match 'target_reduction\.plan'
        $content | Should -Match 'reduced_targets\.csv'
        $content | Should -Match 'retry_candidates\.csv'
        $content | Should -Match 'review_required\.csv'
        $content | Should -Match 'out_of_scope\.csv'
        $content | Should -Match 'location_subnet_candidates\.csv'
        $content | Should -Match 'target_reduction_summary\.json'
    }

    It 'does not let the nonstandard input switch bypass output guardrails' {
        $content = Get-Content -LiteralPath $script:planner -Raw
        $content | Should -Match 'Assert-SasApprovedOutputPath -Path \$OutputDirectory'
        $content | Should -Not -Match 'Assert-SasApprovedOutputPath[^\r\n]+AllowNonstandard:\$AllowNonstandardInput'
    }

    It 'keeps a Bash-native field entrypoint' {
        $script:bashPlanner | Should -Exist
        $bashContent = Get-Content -LiteralPath $script:bashPlanner -Raw
        $bashContent | Should -Match '#!/usr/bin/env bash'
        $bashContent | Should -Match 'python3 -'
        $bashContent | Should -Match 'operation_id.*target_reduction\.plan'
        $bashContent | Should -Match 'out_of_scope\.csv'
        $bashContent | Should -Match 'No network activity was attempted'
    }

    It 'keeps synthetic fixtures present' {
        Join-Path $script:fixtureRoot 'local_evidence.csv' | Should -Exist
        Join-Path $script:fixtureRoot 'location_subnet_map.csv' | Should -Exist
    }

    It 'executes the local transform and reconciles every input row' {
        $script:summary.input_row_count | Should -Be 8
        $script:summary.classified_row_count | Should -Be 8
        $script:summary.classification_reconciled | Should -BeTrue
        ($script:summary.confirmed_reached_count + $script:summary.retry_candidate_count + $script:summary.review_required_count + $script:summary.out_of_scope_count) | Should -Be 8
        $script:summary.deferred_subnet_candidate_count | Should -Be 1
        $script:summary.network_activity_performed | Should -BeFalse
        $script:summary.target_mutation_performed | Should -BeFalse
    }

    It 'keeps DNS-only and duplicate case-variant targets out of confirmed and retry queues' {
        $reduced = @(Import-Csv -LiteralPath (Join-Path $script:outputDirectory 'reduced_targets.csv'))
        $retry = @(Import-Csv -LiteralPath (Join-Path $script:outputDirectory 'retry_candidates.csv'))
        $review = @(Import-Csv -LiteralPath (Join-Path $script:outputDirectory 'review_required.csv'))

        @($reduced | Where-Object { $_.Target -ieq 'foxtrot' }).Count | Should -Be 0
        @($reduced | Where-Object { $_.Target -ieq 'golf' }).Count | Should -Be 0
        @($retry | Where-Object { $_.Target -ieq 'golf' }).Count | Should -Be 0
        @($review | Where-Object { $_.Target -ieq 'golf' }).Count | Should -Be 2
    }

    It 'defers only an approved location row that lacks a direct target' {
        $locations = @(Import-Csv -LiteralPath (Join-Path $script:outputDirectory 'location_subnet_candidates.csv'))
        $locations.Count | Should -Be 1
        $locations[0].Target | Should -BeNullOrEmpty
        $locations[0].SubnetCIDR | Should -Be '192.0.2.0/28'
        $locations[0].Notes | Should -Be 'synthetic candidate, quoted safely'
    }

    It 'declares every generated artifact in the API manifest' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'harness\api\sas-harness-api.json') -Raw | ConvertFrom-Json
        $operation = $manifest.operations | Where-Object { $_.id -eq 'target_reduction.plan' }
        @($operation.outputs) | Should -Contain 'operator_handoff.txt'
        foreach ($name in @($operation.outputs)) {
            Join-Path $script:outputDirectory $name | Should -Exist
        }
    }
}
