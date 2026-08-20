#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:runnerPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:launcherPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
    $script:evidencePolicyPath = Join-Path $script:repoRoot 'harness\api\northwell-printer-mapping-evidence-policy.json'
    $script:fieldSkillPath = Join-Path $script:repoRoot '.claude\skills\field-workflow\SKILL.md'
}

Describe 'Northwell printer mapping evidence precedence contract' {
    It 'keeps mapping bounded to SYSTEM /ga registration proof inside the reversible engine' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw

        $content | Should -Match "'/ga'"
        $content | Should -Match "'MACHINE_WIDE_REGISTRATION_PRESENT'"
        $content | Should -Match 'RuntimePrintObservedByEngine = \$false'
        $content | Should -Match 'TestPagesPrinted = \$false'
        $content | Should -Match 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Print\\Connections'
        $content | Should -Not -Match 'Get-StaleLocalIpQueueCollision'
        $content | Should -Not -Match 'REPAIRED_STALE_DIRECT_IP_QUEUE_COLLISION'
        $content | Should -Not -Match 'AMBIGUOUS_LOCAL_IP_QUEUE_COLLISION'
        $content | Should -Not -Match 'Remove-Printer\b'
        $content | Should -Not -Match 'Remove-PrinterPort'
        $content | Should -Not -Match 'Add-PrinterPort'
        $content | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $content | Should -Not -Match 'PrintTestPage'
    }

    It 'treats a real post-mapping document print as higher-ranked runtime acceptance' {
        Test-Path -LiteralPath $script:evidencePolicyPath | Should -BeTrue
        $policy = Get-Content -LiteralPath $script:evidencePolicyPath -Raw | ConvertFrom-Json

        $runtime = @($policy.evidence_precedence | Where-Object { $_.id -eq 'POST_MAPPING_CLIENT_DOCUMENT_PRINT_OBSERVED' })[0]
        $registration = @($policy.evidence_precedence | Where-Object { $_.id -eq 'HKLM_MACHINE_WIDE_QUEUE_PROOF' })[0]
        $telemetry = @($policy.evidence_precedence | Where-Object { $_.id -eq 'LOCAL_QUEUE_OR_PORT_TELEMETRY' })[0]

        $runtime.proof_level | Should -Be 'RUNTIME_ACCEPTANCE'
        $runtime.mapping_interpretation | Should -Be 'MAPPING_PATH_WORKING'
        [int]$runtime.rank | Should -BeGreaterThan ([int]$registration.rank)
        [int]$registration.rank | Should -BeGreaterThan ([int]$telemetry.rank)
        $runtime.overrides_negative_diagnostic_telemetry | Should -BeTrue
        $policy.rules.successful_real_document_print_after_mapping_is_acceptance | Should -BeTrue
        $policy.rules.diagnostic_port_name_can_invalidate_observed_print_success | Should -BeFalse
        $policy.rules.remote_status_timeout_can_invalidate_observed_print_success | Should -BeFalse
        $policy.rules.repeat_test_page_after_observed_real_print | Should -BeFalse
        $policy.rules.remove_printer_object_based_only_on_port_telemetry | Should -BeFalse
        $policy.rules.delete_printer_port_based_only_on_port_telemetry | Should -BeFalse
        $policy.rules.direct_ip_mapping_fallback | Should -BeFalse
        $policy.rules.per_user_mapping_fallback | Should -BeFalse
    }

    It 'keeps operator evidence discoverable without bloating the quick launcher or printing another test page' {
        $runner = Get-Content -LiteralPath $script:runnerPath -Raw
        $launcher = Get-Content -LiteralPath $script:launcherPath -Raw
        $fieldSkill = Get-Content -LiteralPath $script:fieldSkillPath -Raw

        $runner | Should -Match 'LATEST-PATH\.txt'
        $runner | Should -Match 'SessionRoot = \$SessionRoot'
        $runner | Should -Match 'Summary\.json'
        $runner | Should -Match 'Controller\.log'
        $runner | Should -Match 'Status\.json'
        $runner | Should -Match 'Agent\.log'
        $runner | Should -Match 'UndoPlan\.json'
        $launcher | Should -Match 'Confirm-NorthwellPrinterActiveUserMaterialization\.ps1'
        $launcher | Should -Not -Match 'SAS_LATEST_DIR|set /p|notepad\.exe'
        $launcher | Should -Match '(?i)pause'
        $launcher | Should -Match 'NO TEST PAGE'
        $fieldSkill | Should -Match 'runtime acceptance evidence that the mapped print path works'
        $fieldSkill | Should -Match 'Do not request another test page'
        $fieldSkill | Should -Match 'diagnostic context unless a later observed print failure reopens the incident'
    }
}
