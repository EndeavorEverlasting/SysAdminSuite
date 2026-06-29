#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:planner = Join-Path $script:repoRoot 'survey\sas-serial-preflight-plan.ps1'
    $script:dispatcher = Join-Path $script:repoRoot 'survey\sas-target-intake-dispatch.ps1'
    $script:runbook = Join-Path $script:repoRoot 'docs\FIELD_NETWORK_PREFLIGHT.md'
}

Describe 'serial preflight planner contracts' {
    It 'planner exists and parses without PowerShell syntax errors' {
        $script:planner | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:planner, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'dispatcher parses and exposes SerialPreflightPlan mode' {
        $script:dispatcher | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:dispatcher, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0

        $content = Get-Content -LiteralPath $script:dispatcher -Raw
        $content.Contains('SerialPreflightPlan') | Should -BeTrue
        $content.Contains('sas-serial-preflight-plan.ps1') | Should -BeTrue
        $content.Contains('Run in Windows PowerShell to stage pingable host/IP targets from Alejandro serials') | Should -BeTrue
    }

    It 'planner stages host/IP targets and not serial strings' {
        $content = Get-Content -LiteralPath $script:planner -Raw
        $content.Contains('Alejandro serial list') | Should -BeTrue
        $content.Contains('survey/input/serial_preflight') | Should -BeTrue
        $content.Contains('survey/output/serial_preflight') | Should -BeTrue
        $content.Contains('to_probe_targets.txt') | Should -BeTrue
        $content.Contains('STAGE_FOR_NETWORK_PREFLIGHT') | Should -BeTrue
        $content.Contains('REVIEW_REQUIRED_NO_PROBE_READY_EVIDENCE') | Should -BeTrue
        $content.Contains('do not ping the serial string') | Should -BeTrue
        $content.Contains('Do not ping serial strings') | Should -BeTrue
        $content.Contains('network_activity_performed = $false') | Should -BeTrue
    }

    It 'runbook documents the Alejandro serial list to network preflight path' {
        $script:runbook | Should -Exist
        $content = Get-Content -LiteralPath $script:runbook -Raw
        $content.Contains('Alejandro serial list flow') | Should -BeTrue
        $content.Contains('sas-serial-preflight-plan.ps1') | Should -BeTrue
        $content.Contains('approved serial-to-host/IP evidence') | Should -BeTrue
        $content.Contains('Serial-only rows go to review, not packets') | Should -BeTrue
        $content.Contains('sas-network-preflight.ps1') | Should -BeTrue
    }
}
