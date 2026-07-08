#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:planner = Join-Path $script:repoRoot 'survey\sas-target-reduction-plan.ps1'
    $script:bashPlanner = Join-Path $script:repoRoot 'survey\sas-target-reduction-plan.sh'
    $script:fixtureRoot = Join-Path $script:repoRoot 'survey\fixtures\target_reduction'
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
}
