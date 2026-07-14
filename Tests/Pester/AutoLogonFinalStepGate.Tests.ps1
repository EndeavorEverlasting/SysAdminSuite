#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:gateScript = Join-Path $script:repoRoot 'scripts\Invoke-SasAutoLogonFinalStepGate.ps1'
    $script:fixtures = Join-Path $PSScriptRoot '..\Fixtures\autologon_final_step'
}

Describe 'Invoke-SasAutoLogonFinalStepGate safety behavior' {
    BeforeEach {
        $script:outputRoot = Join-Path $script:repoRoot ('survey\output\autologon_final_step\pester-' + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if ([System.IO.Directory]::Exists($script:outputRoot)) {
            [System.IO.Directory]::Delete($script:outputRoot, $true)
        }
    }

    It 'exists and parses without errors' {
        $script:gateScript | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:gateScript, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'rejects a malformed run ID' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'bad-run-id' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $result.blocked_reason | Should -BeLike '*run_id_format*'
    }

    It 'accepts a valid autologon-delta run ID' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $runIdPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'run_id_format' })[0]
        $runIdPrereq.passed | Should -BeTrue
    }

    It 'fails closed when approved apps catalog is missing' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath 'C:\nonexistent\approved-apps.json' `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $catalogPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'approved_catalog' })[0]
        $catalogPrereq.passed | Should -BeFalse
    }

    It 'fails closed when catalog has no autologon package' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-empty.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $catalogPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'approved_catalog' })[0]
        $catalogPrereq.passed | Should -BeFalse
        $catalogPrereq.detail | Should -BeLike '*not found*'
    }

    It 'fails closed when autologon install_enabled is false' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-disabled.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $catalogPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'approved_catalog' })[0]
        $catalogPrereq.passed | Should -BeFalse
        $catalogPrereq.detail | Should -BeLike '*install_enabled is false*'
    }

    It 'fails closed when Before snapshot is missing' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath 'C:\nonexistent\run_manifest_before.json' `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $snapshotPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'before_snapshot' })[0]
        $snapshotPrereq.passed | Should -BeFalse
    }

    It 'fails closed when Before snapshot has wrong run ID' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_wrong_runid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $snapshotPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'before_snapshot' })[0]
        $snapshotPrereq.passed | Should -BeFalse
        $snapshotPrereq.detail | Should -BeLike '*run_id mismatch*'
    }

    It 'fails closed when Before snapshot has wrong phase' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_wrong_phase.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $snapshotPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'before_snapshot' })[0]
        $snapshotPrereq.passed | Should -BeFalse
        $snapshotPrereq.detail | Should -BeLike '*phase*'
    }

    It 'fails closed when target is not in Before snapshot' {
        $result = & $script:gateScript `
            -Target 'NOTEXIST01' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -FixtureMode

        $result.overall_pass | Should -BeFalse
        $snapshotPrereq = @($result.prerequisites | Where-Object { $_.id -eq 'before_snapshot' })[0]
        $snapshotPrereq.passed | Should -BeFalse
        $snapshotPrereq.detail | Should -BeLike '*not found in Before snapshot*'
    }

    It 'passes when all mandatory prerequisites are satisfied' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -ExecContext fixture `
            -FixtureMode

        $result.overall_pass | Should -BeTrue
        $result.blocked_reason | Should -BeNullOrEmpty
        $mandatoryFailed = @($result.prerequisites | Where-Object { $_.mandatory -eq $true -and $_.passed -eq $false })
        $mandatoryFailed.Count | Should -Be 0
    }

    It 'writes gate result JSON to output root' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -ExecContext fixture `
            -FixtureMode

        $gatePath = Join-Path $script:outputRoot 'autologon-delta-20260714-143000-1a2b3c4d\autologon_final_step_gate.json'
        $gatePath | Should -Exist
        $gateContent = Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
        $gateContent.gate_id | Should -Be 'autologon-final-step'
        $gateContent.overall_pass | Should -BeTrue
    }

    It 'records gate_version in output' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -ExecContext fixture `
            -FixtureMode

        $result.gate_version | Should -Be '1.0.0'
    }

    It 'never exposes DefaultPassword data' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -ExecContext fixture `
            -FixtureMode

        $resultJson = $result | ConvertTo-Json -Depth 10
        $resultJson | Should -Not -BeLike '*DefaultPassword*'
        $resultJson | Should -Not -BeLike '*password*'
    }

    It 'all mandatory prerequisites have mandatory=true' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -ExecContext fixture `
            -FixtureMode

        $mandatoryIds = @('run_id_format', 'host_eligibility', 'approved_catalog', 'before_snapshot')
        foreach ($id in $mandatoryIds) {
            $prereq = @($result.prerequisites | Where-Object { $_.id -eq $id })[0]
            $prereq | Should -Not -BeNullOrEmpty
            $prereq.mandatory | Should -BeTrue
        }
    }

    It 'has exactly 6 prerequisites (4 mandatory, 2 recommended)' {
        $result = & $script:gateScript `
            -Target 'SAMPLE001' `
            -RunId 'autologon-delta-20260714-143000-1a2b3c4d' `
            -ApprovedAppsPath (Join-Path $script:fixtures 'approved-apps-valid.json') `
            -BeforeSnapshotPath (Join-Path $script:fixtures 'run_manifest_before_valid.json') `
            -OutputRoot $script:outputRoot `
            -HostEligibilityPolicyPath (Join-Path $script:fixtures 'host-eligibility-policy-test.json') `
            -ExecContext fixture `
            -FixtureMode

        @($result.prerequisites).Count | Should -Be 6
        $mandatoryCount = @($result.prerequisites | Where-Object { $_.mandatory -eq $true }).Count
        $mandatoryCount | Should -Be 4
        $recommendedCount = @($result.prerequisites | Where-Object { $_.mandatory -eq $false }).Count
        $recommendedCount | Should -Be 2
    }
}
