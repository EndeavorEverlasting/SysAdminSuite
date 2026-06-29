#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:planner = Join-Path $script:repoRoot 'survey\sas-serial-preflight-plan.ps1'
}

Describe 'sas-serial-preflight-plan.ps1' {
    It 'exists and parses without PowerShell syntax errors' {
        $script:planner | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:planner, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'stages only approved hostname/IP evidence from an Alejandro serial list' {
        $runId = 'pester-serial-preflight'
        $targetsLocal = Join-Path $script:repoRoot 'targets\local'
        $outputRoot = Join-Path $script:repoRoot "survey\output\serial_preflight\$runId"
        $stagingRoot = Join-Path $script:repoRoot "survey\input\serial_preflight\$runId"
        New-Item -ItemType Directory -Force -Path $targetsLocal | Out-Null

        $serialFile = Join-Path $targetsLocal 'alejandro_serials.pester.csv'
        $evidenceFile = Join-Path $targetsLocal 'alejandro_serial_evidence.pester.csv'

        @(
            'Serial',
            'CYBTEST0001',
            'CYBTEST0002'
        ) | Set-Content -LiteralPath $serialFile -Encoding UTF8

        @(
            'Serial,HostName,EvidenceClass',
            'CYBTEST0001,WMH999TEST001,approved_identity_collection',
            'CYBTEST0002,,population_only'
        ) | Set-Content -LiteralPath $evidenceFile -Encoding UTF8

        if (Test-Path -LiteralPath $outputRoot) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }

        & $script:planner -SerialFile $serialFile -EvidenceFile $evidenceFile -RunId $runId | Out-Null

        $targetFile = Join-Path $stagingRoot 'to_probe_targets.txt'
        $planFile = Join-Path $outputRoot 'serial_preflight_plan.csv'
        $reviewFile = Join-Path $outputRoot 'review_required.csv'
        $summaryFile = Join-Path $outputRoot 'serial_preflight_summary.json'
        $handoffFile = Join-Path $outputRoot 'operator_handoff.txt'

        $targetFile | Should -Exist
        $planFile | Should -Exist
        $reviewFile | Should -Exist
        $summaryFile | Should -Exist
        $handoffFile | Should -Exist

        $targets = @(Get-Content -LiteralPath $targetFile)
        $targets | Should -Contain 'WMH999TEST001'
        $targets | Should -Not -Contain 'CYBTEST0001'
        $targets | Should -Not -Contain 'CYBTEST0002'

        $plan = @(Import-Csv -LiteralPath $planFile)
        ($plan | Where-Object { $_.Serial -eq 'CYBTEST0001' }).Decision | Should -Be 'STAGE_FOR_NETWORK_PREFLIGHT'
        ($plan | Where-Object { $_.Serial -eq 'CYBTEST0002' }).Decision | Should -Be 'REVIEW_REQUIRED_NO_PROBE_READY_EVIDENCE'

        $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
        $summary.network_activity_performed | Should -BeFalse
        $summary.staged_probe_target_count | Should -Be 1
        $summary.review_required_count | Should -Be 1
    }

    It 'contains the safety contract that serial strings are not ping targets' {
        $content = Get-Content -LiteralPath $script:planner -Raw
        $content | Should -Match 'Do not ping serial strings'
        $content | Should -Match 'network_activity_performed = \$false'
        $content | Should -Match 'STAGE_FOR_NETWORK_PREFLIGHT'
        $content | Should -Match 'REVIEW_REQUIRED_NO_PROBE_READY_EVIDENCE'
    }
}
