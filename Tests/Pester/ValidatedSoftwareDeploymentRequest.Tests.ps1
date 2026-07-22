#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline executable tests for the closed validated software deployment request contract.

.DESCRIPTION
    Imports only the request/finalization module and validates malformed request objects.
    No network access, target contact, installer execution, or workstation mutation occurs.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repoRoot 'scripts\SasSoftwareInstallFinalization.psm1'
    $examplePath = Join-Path $repoRoot 'docs\examples\validated-deployment-request.example.json'
    Import-Module $modulePath -Force

    function New-ValidDeploymentRequest {
        return (Get-Content -LiteralPath $examplePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
}

Describe 'Validated software deployment request runtime contract' {
    It 'accepts the tracked schema-valid example' {
        $request = New-ValidDeploymentRequest
        $errors = @(Test-SasValidatedDeploymentRequest -Request $request)
        $errors.Count | Should -Be 0
    }

    It 'accepts only explicitly approved empty installer arguments' {
        $approved = New-ValidDeploymentRequest
        $approved.installer_arguments = @()
        $approved | Add-Member -NotePropertyName 'installer_arguments_policy' -NotePropertyValue 'approved_empty'
        @(Test-SasValidatedDeploymentRequest -Request $approved).Count | Should -Be 0

        $unapproved = New-ValidDeploymentRequest
        $unapproved.installer_arguments = @()
        @(Test-SasValidatedDeploymentRequest -Request $unapproved) |
            Should -Contain 'INSTALLER_ARGUMENTS_EMPTY_NOT_APPROVED'

        $unexpected = New-ValidDeploymentRequest
        $unexpected | Add-Member -NotePropertyName 'installer_arguments_policy' -NotePropertyValue 'approved_empty'
        @(Test-SasValidatedDeploymentRequest -Request $unexpected) |
            Should -Contain 'INSTALLER_ARGUMENTS_POLICY_UNEXPECTED'
    }

    It 'rejects unknown root properties instead of ignoring typos' {
        $request = New-ValidDeploymentRequest
        $request | Add-Member -NotePropertyName 'installer_argumnts' -NotePropertyValue @('/quiet')

        $errors = @(Test-SasValidatedDeploymentRequest -Request $request)
        $errors | Should -Contain 'REQUEST_FIELD_UNKNOWN:installer_argumnts'
    }

    It 'rejects unknown nested authorization properties' {
        $request = New-ValidDeploymentRequest
        $request.authorization | Add-Member -NotePropertyName 'approval_note' -NotePropertyValue 'not part of the closed contract'

        $errors = @(Test-SasValidatedDeploymentRequest -Request $request)
        $errors | Should -Contain 'AUTHORIZATION_FIELD_UNKNOWN:approval_note'
    }

    It 'rejects scalar target input and case-insensitive duplicate targets' {
        $scalar = New-ValidDeploymentRequest
        $scalar.targets = 'HOST-01'
        @(Test-SasValidatedDeploymentRequest -Request $scalar) | Should -Contain 'TARGETS_NOT_ARRAY'

        $duplicate = New-ValidDeploymentRequest
        $duplicate.targets = @('HOST-01', 'host-01')
        @(Test-SasValidatedDeploymentRequest -Request $duplicate) | Should -Contain 'TARGET_DUPLICATE:host-01'
    }

    It 'requires an actual boolean for signature enforcement' {
        $request = New-ValidDeploymentRequest
        $request.require_valid_signature = 'true'

        @(Test-SasValidatedDeploymentRequest -Request $request) | Should -Contain 'REQUIRE_VALID_SIGNATURE_TYPE_INVALID'
    }

    It 'validates an optional signer thumbprint even when signature enforcement is false' {
        $request = New-ValidDeploymentRequest
        $request.require_valid_signature = $false
        $request.expected_signer_thumbprint = 'not-a-thumbprint'

        @(Test-SasValidatedDeploymentRequest -Request $request) | Should -Contain 'EXPECTED_SIGNER_THUMBPRINT_INVALID'
    }

    It 'rejects unknown validation-check properties' {
        $request = New-ValidDeploymentRequest
        $request.validation.checks[0] | Add-Member -NotePropertyName 'command' -NotePropertyValue 'arbitrary text'

        @(Test-SasValidatedDeploymentRequest -Request $request) | Should -Contain 'VALIDATION_CHECK_FIELD_UNKNOWN:command'
    }

    It 'rejects unsupported service states before target execution' {
        $request = New-ValidDeploymentRequest
        $check = $request.validation.checks[0]
        $check.type = 'ServiceExists'
        $check | Add-Member -NotePropertyName 'service_name' -NotePropertyValue 'ApprovedService'
        $check | Add-Member -NotePropertyName 'expected_status' -NotePropertyValue 'Starting'

        @(Test-SasValidatedDeploymentRequest -Request $request) | Should -Contain 'VALIDATION_SERVICE_STATUS_INVALID:installed-file'
    }

    It 'keeps JSON validation-check arrays distinct on Windows PowerShell 5.1' {
        $installedPath = Join-Path $TestDrive 'installed.txt'
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        Set-Content -LiteralPath $installedPath -Value 'installed' -Encoding UTF8
        @{ package_name = 'Fixture Package' } |
            ConvertTo-Json |
            Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $checks = @(
            [ordered]@{
                id = 'installed-file'
                type = 'FileExists'
                required = $true
                path = $installedPath
            },
            [ordered]@{
                id = 'manifest-package'
                type = 'JsonPropertyEquals'
                required = $true
                path = $manifestPath
                property_path = 'package_name'
                expected_value = 'Fixture Package'
            }
        )
        $checksJson = $checks | ConvertTo-Json -Depth 8 -Compress
        $validationScript = Get-SasSoftwareValidationScriptBlock
        $validation = & $validationScript $checksJson

        $validation.succeeded | Should -BeTrue
        $validation.required_check_count | Should -Be 2
        $validation.failed_required_check_count | Should -Be 0
        @($validation.checks).Count | Should -Be 2
        @($validation.checks).id | Should -Be @('installed-file', 'manifest-package')
        @($validation.checks).type | Should -Be @('FileExists', 'JsonPropertyEquals')
    }
}
