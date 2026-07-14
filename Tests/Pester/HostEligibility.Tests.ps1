#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:validatorScript = Join-Path $script:repoRoot 'scripts\Test-SasHostEligibility.ps1'
    $script:samplePolicy = Join-Path $script:repoRoot 'Config\host-eligibility-policy.sample.json'
    $script:schemaPath = Join-Path $script:repoRoot 'schemas\harness\host-eligibility-policy.schema.json'

    function New-SasTestPolicy {
        param(
            [string]$PolicyId = 'test-policy',
            [string]$PolicyVersion = '2026.07.14',
            [string[]]$DefaultContexts = @('local', 'remote', 'fixture', 'vm'),
            [object[]]$Patterns
        )

        [pscustomobject]@{
            schema_version           = 'sas-host-eligibility-policy/v1'
            policy_id                = $PolicyId
            policy_version           = $PolicyVersion
            default_allowed_contexts = $DefaultContexts
            patterns                 = $Patterns
        }
    }

    function New-SasTestPattern {
        param(
            [string]$Name = 'test-pattern',
            [string]$Regex = '^test-[a-z]+$',
            [string[]]$Actions = @('local', 'remote', 'fixture', 'vm')
        )

        [pscustomobject]@{
            name      = $Name
            match_type = 'regex'
            regex     = $Regex
            actions   = $Actions
        }
    }

    function Save-SasTestPolicy {
        param(
            [Parameter(Mandatory = $true)][object]$Policy,
            [Parameter(Mandatory = $true)][string]$Path
        )

        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        $Policy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Describe 'Test-SasHostEligibility script' {
    It 'exists and parses without errors' {
        $script:validatorScript | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:validatorScript, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'defines the Test-SasHostEligibility function when dot-sourced' {
        . $script:validatorScript -Target 'test' -ExecContext 'fixture' -PolicyPath (Join-Path $TestDrive 'nonexistent.json')
        $command = Get-Command -Name Test-SasHostEligibility -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }
}

Describe 'Host eligibility policy schema' {
    It 'exists and is valid JSON' {
        $script:schemaPath | Should -Exist
        { Get-Content -LiteralPath $script:schemaPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'has the correct schema version id' {
        $schema = Get-Content -LiteralPath $script:schemaPath -Raw | ConvertFrom-Json
        $schema.'$id' | Should -Be 'schemas/harness/host-eligibility-policy.schema.json'
    }

    It 'requires schema_version, policy_id, policy_version, and patterns' {
        $schema = Get-Content -LiteralPath $script:schemaPath -Raw | ConvertFrom-Json
        $required = $schema.required
        $required | Should -Contain 'schema_version'
        $required | Should -Contain 'policy_id'
        $required | Should -Contain 'policy_version'
        $required | Should -Contain 'patterns'
    }
}

Describe 'Sample host eligibility policy' {
    BeforeAll {
        $script:samplePolicyContent = Get-Content -LiteralPath $script:samplePolicy -Raw | ConvertFrom-Json
    }

    It 'exists and is valid JSON' {
        $script:samplePolicy | Should -Exist
        { Get-Content -LiteralPath $script:samplePolicy -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'has the correct schema version' {
        $script:samplePolicyContent.schema_version | Should -Be 'sas-host-eligibility-policy/v1'
    }

    It 'has a policy_id and policy_version' {
        $script:samplePolicyContent.policy_id | Should -Not -BeNullOrEmpty
        $script:samplePolicyContent.policy_version | Should -Match '^\d{4}\.\d{2}\.\d{2}$'
    }

    It 'has at least one pattern' {
        @($script:samplePolicyContent.patterns).Count | Should -BeGreaterThan 0
    }

    It 'does not contain any real hostnames' {
        $rawContent = Get-Content -LiteralPath $script:samplePolicy -Raw
        $rawContent | Should -Not -Match '(?i)CHEEX|LPW003ASI|NT2K|NORTHWELL|NSLIJ'
    }

    It 'all patterns have required fields' {
        foreach ($pattern in $script:samplePolicyContent.patterns) {
            $pattern.name | Should -Not -BeNullOrEmpty
            $pattern.match_type | Should -Be 'regex'
            $pattern.regex | Should -Not -BeNullOrEmpty
            @($pattern.actions).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Test-SasHostEligibility with sanitized fixtures' {
    BeforeEach {
        $script:testDir = Join-Path $TestDrive 'host-eligibility'
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }

    Context 'Policy file missing (fails closed)' {
        It 'returns closed decision when policy file does not exist' {
            $missingPath = Join-Path $script:testDir 'nonexistent-policy.json'
            $result = & $script:validatorScript -Target 'fixture-host01' -ExecContext 'fixture' -PolicyPath $missingPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'POLICY_FILE_MISSING'
            $result.execution_context | Should -Be 'fixture'
            $result.target | Should -Be '[redacted]'
        }
    }

    Context 'Policy file malformed (fails closed)' {
        It 'returns closed decision when policy is not valid JSON' {
            $malformedPath = Join-Path $script:testDir 'malformed-policy.json'
            'this is not json' | Set-Content -LiteralPath $malformedPath -Encoding UTF8
            $result = & $script:validatorScript -Target 'fixture-host01' -ExecContext 'fixture' -PolicyPath $malformedPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'POLICY_MALFORMED_JSON'
        }
    }

    Context 'Policy schema unsupported (fails closed)' {
        It 'returns closed decision when schema version is wrong' {
            $badSchemaPath = Join-Path $script:testDir 'bad-schema-policy.json'
            $policy = New-SasTestPolicy -Patterns @((New-SasTestPattern))
            $policy.schema_version = 'wrong-version'
            Save-SasTestPolicy -Policy $policy -Path $badSchemaPath
            $result = & $script:validatorScript -Target 'fixture-host01' -ExecContext 'fixture' -PolicyPath $badSchemaPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'POLICY_SCHEMA_UNSUPPORTED'
        }
    }

    Context 'Policy has no patterns (fails closed)' {
        It 'returns closed decision when patterns array is empty' {
            $emptyPath = Join-Path $script:testDir 'empty-patterns-policy.json'
            $policy = New-SasTestPolicy -Patterns @()
            Save-SasTestPolicy -Policy $policy -Path $emptyPath
            $result = & $script:validatorScript -Target 'fixture-host01' -ExecContext 'fixture' -PolicyPath $emptyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'POLICY_NO_PATTERNS'
        }
    }

    Context 'Policy has duplicate pattern names (fails closed)' {
        It 'returns closed decision when pattern names are duplicated' {
            $dupPath = Join-Path $script:testDir 'dup-patterns-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'same-name' -Regex '^dup-a$'),
                (New-SasTestPattern -Name 'same-name' -Regex '^dup-b$')
            )
            Save-SasTestPolicy -Policy $policy -Path $dupPath
            $result = & $script:validatorScript -Target 'dup-a' -ExecContext 'fixture' -PolicyPath $dupPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'POLICY_DUPLICATE_PATTERNS'
        }
    }

    Context 'Empty target (fails closed)' {
        It 'rejects an empty target at parameter binding' {
            $policyPath = Join-Path $script:testDir 'valid-policy.json'
            $policy = New-SasTestPolicy -Patterns @((New-SasTestPattern -Regex '^fixture-.*$'))
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            { & $script:validatorScript -Target '' -ExecContext 'fixture' -PolicyPath $policyPath } | Should -Throw
        }

        It 'returns closed decision when target is whitespace only' {
            $policyPath = Join-Path $script:testDir 'valid-policy2.json'
            $policy = New-SasTestPolicy -Patterns @((New-SasTestPattern -Regex '^fixture-.*$'))
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target '   ' -ExecContext 'fixture' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'TARGET_EMPTY'
        }
    }

    Context 'Matching hostname (allowed)' {
        It 'allows fixture-context target matching a fixture pattern' {
            $policyPath = Join-Path $script:testDir 'match-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'fixture-only' -Regex '^fixture-[a-z0-9]+$' -Actions @('fixture'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'fixture-host01' -ExecContext 'fixture' -PolicyPath $policyPath
            $result.eligible | Should -BeTrue
            $result.decision | Should -Be 'allowed'
            $result.reason_code | Should -Be 'PATTERN_MATCH_AND_CONTEXT_ALLOWED'
            $result.matched_pattern | Should -Be 'fixture-only'
        }
    }

    Context 'Non-matching hostname (fails closed)' {
        It 'closes when target does not match any pattern in remote context' {
            $policyPath = Join-Path $script:testDir 'nomatch-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'fixture-only' -Regex '^fixture-[a-z0-9]+$' -Actions @('fixture'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'unknown-host01' -ExecContext 'remote' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'NO_PATTERN_MATCH'
        }
    }

    Context 'Context not allowed for matched pattern' {
        It 'closes when execution context is not in pattern actions' {
            $policyPath = Join-Path $script:testDir 'context-denied-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'remote-only' -Regex '^cyb-[a-z0-9]+$' -Actions @('remote'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'cyb-device01' -ExecContext 'local' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'CONTEXT_NOT_ALLOWED_FOR_PATTERN'
            $result.matched_pattern | Should -Be 'remote-only'
        }
    }

    Context 'Remote target mismatch (local fallback blocked)' {
        It 'closes when remote context targets localhost' {
            $policyPath = Join-Path $script:testDir 'fallback-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Regex '.*' -Actions @('remote'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'localhost' -ExecContext 'remote' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'LOCAL_FALLBACK_BLOCKED'
        }

        It 'closes when remote context targets 127.0.0.1' {
            $policyPath = Join-Path $script:testDir 'fallback-policy2.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Regex '.*' -Actions @('remote'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target '127.0.0.1' -ExecContext 'remote' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'LOCAL_FALLBACK_BLOCKED'
        }

        It 'closes when vm context targets the local computer name' {
            $policyPath = Join-Path $script:testDir 'fallback-policy3.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Regex '.*' -Actions @('vm'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target $env:COMPUTERNAME -ExecContext 'vm' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'LOCAL_FALLBACK_BLOCKED'
        }
    }

    Context 'Fixture mode' {
        It 'allows fixture execution on unmatched hosts' {
            $policyPath = Join-Path $script:testDir 'fixture-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'remote-only' -Regex '^cyb-[a-z]+$' -Actions @('remote'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'fixture-anything' -ExecContext 'fixture' -PolicyPath $policyPath
            $result.eligible | Should -BeTrue
            $result.decision | Should -Be 'allowed'
            $result.reason_code | Should -Be 'UNSUPPORTED_HOST_FIT_FOR_FIXTURE_OR_VM'
            $result.matched_pattern | Should -BeNullOrEmpty
        }
    }

    Context 'VM mode' {
        It 'allows VM execution on unmatched hosts' {
            $policyPath = Join-Path $script:testDir 'vm-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'remote-only' -Regex '^cyb-[a-z]+$' -Actions @('remote'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'vm-lab-01' -ExecContext 'vm' -PolicyPath $policyPath
            $result.eligible | Should -BeTrue
            $result.decision | Should -Be 'allowed'
            $result.reason_code | Should -Be 'UNSUPPORTED_HOST_FIT_FOR_FIXTURE_OR_VM'
            $result.matched_pattern | Should -BeNullOrEmpty
        }
    }

    Context 'Local context with local target' {
        It 'allows local context when target matches the local computer name' {
            $policyPath = Join-Path $script:testDir 'local-policy.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'any-host' -Regex '.*' -Actions @('local'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target $env:COMPUTERNAME -ExecContext 'local' -PolicyPath $policyPath
            $result.eligible | Should -BeTrue
            $result.decision | Should -Be 'allowed'
            $result.reason_code | Should -Be 'PATTERN_MATCH_AND_CONTEXT_ALLOWED'
        }

        It 'closes when local context target is not the local computer name' {
            $policyPath = Join-Path $script:testDir 'local-policy2.json'
            $policy = New-SasTestPolicy -Patterns @(
                (New-SasTestPattern -Name 'any-host' -Regex '.*' -Actions @('local'))
            )
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'REMOTE-HOST01' -ExecContext 'local' -PolicyPath $policyPath
            $result.eligible | Should -BeFalse
            $result.decision | Should -Be 'closed'
            $result.reason_code | Should -Be 'LOCAL_CONTEXT_TARGET_MISMATCH'
        }
    }

    Context 'Result schema contract' {
        It 'returns all required result fields' {
            $policyPath = Join-Path $script:testDir 'contract-policy.json'
            $policy = New-SasTestPolicy -Patterns @((New-SasTestPattern -Regex '^fixture-.*$'))
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'fixture-test' -ExecContext 'fixture' -PolicyPath $policyPath
            $result.schema_version | Should -Be 'sas-host-eligibility-result/v1'
            $result.PSObject.Properties.Name | Should -Contain 'execution_context'
            $result.PSObject.Properties.Name | Should -Contain 'target'
            $result.PSObject.Properties.Name | Should -Contain 'eligible'
            $result.PSObject.Properties.Name | Should -Contain 'decision'
            $result.PSObject.Properties.Name | Should -Contain 'reason_code'
            $result.PSObject.Properties.Name | Should -Contain 'reason'
            $result.PSObject.Properties.Name | Should -Contain 'policy_path'
            $result.PSObject.Properties.Name | Should -Contain 'policy_version'
            $result.PSObject.Properties.Name | Should -Contain 'matched_pattern'
            $result.PSObject.Properties.Name | Should -Contain 'allowed_contexts'
        }

        It 'never exposes the real target hostname' {
            $policyPath = Join-Path $script:testDir 'redact-policy.json'
            $policy = New-SasTestPolicy -Patterns @((New-SasTestPattern -Regex '^fixture-.*$'))
            Save-SasTestPolicy -Policy $policy -Path $policyPath
            $result = & $script:validatorScript -Target 'fixture-secret-name' -ExecContext 'fixture' -PolicyPath $policyPath
            $result.target | Should -Be '[redacted]'
        }
    }
}
