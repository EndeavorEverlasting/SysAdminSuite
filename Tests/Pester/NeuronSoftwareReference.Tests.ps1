#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline contract tests for Neuron software reference comparison tooling.

.DESCRIPTION
    Validates the local reference baseline, comparison script contract, example observed snapshot, and documentation.
    These tests do not require command-console access or live Neuron connectivity.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $repoRoot 'GetInfo\Get-NeuronSoftwareReference.ps1'
    $referencePath = Join-Path $repoRoot 'GetInfo\Config\NeuronSoftwareReferences\11.8.0.328.json'
    $observedPath = Join-Path $repoRoot 'GetInfo\Config\NeuronObservedPackages.example.csv'
    $docPath = Join-Path $repoRoot 'docs\NEURON_SOFTWARE_REFERENCE.md'
}

Describe 'Get-NeuronSoftwareReference.ps1 -- script contract' {
    BeforeAll {
        $script:content = Get-Content -Path $scriptPath -Raw
    }

    It 'Script file exists' {
        $scriptPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Uses an offline reference id by default' {
        $script:content | Should -Match '\$ReferenceId\s*=\s*''11\.8\.0\.328'''
        $script:content | Should -Match 'NeuronSoftwareReferences'
    }

    It 'Supports observed CSV or JSON comparison input' {
        $script:content | Should -Match '\$ObservedPath'
        $script:content | Should -Match 'Import-Csv'
        $script:content | Should -Match 'ConvertFrom-Json'
    }

    It 'Emits expected, comparison, and summary artifacts' {
        $script:content | Should -Match '_expected\.csv'
        $script:content | Should -Match '_comparison\.csv'
        $script:content | Should -Match '_summary\.json'
        $script:content | Should -Match 'Export-Csv'
        $script:content | Should -Match 'ConvertTo-Json'
    }

    It 'Tracks meaningful comparison statuses' {
        foreach ($status in @('OK','Missing','VersionMismatch','Extra','ReferenceOnly')) {
            $script:content | Should -Match $status
        }
    }

    It 'Generates suite HTML when helper exists' {
        $script:content | Should -Match 'ConvertTo-SuiteHtml'
    }
}

Describe 'Neuron software reference baseline -- 11.8.0.328' {
    It 'Reference JSON exists' {
        $referencePath | Should -Exist
    }

    It 'Reference JSON is valid and has firmware plus DDI sections' {
        $raw = Get-Content -Path $referencePath -Raw | ConvertFrom-Json
        $raw.referenceId | Should -Be '11.8.0.328'
        @($raw.firmware).Count | Should -BeGreaterOrEqual 2
        @($raw.ddi).Count | Should -BeGreaterOrEqual 10
    }

    It 'Includes key DDI packages visible in the console reference' {
        $raw = Get-Content -Path $referencePath -Raw | ConvertFrom-Json
        $names = @($raw.ddi | ForEach-Object { $_.name })
        foreach ($name in @('AspectA','DatexA','DragerMedibus','PhilipsDataExport','TerumoD')) {
            $names | Should -Contain $name
        }
    }
}

Describe 'Observed package example and docs' {
    It 'Observed package example exists with expected header' {
        $observedPath | Should -Exist
        (Get-Content -Path $observedPath -First 1) | Should -Be 'Category,Name,Version'
    }

    It 'Documentation exists and explains survey usage' {
        $docPath | Should -Exist
        $doc = Get-Content -Path $docPath -Raw
        $doc | Should -Match 'Software Reference'
        $doc | Should -Match 'Survey use case'
        $doc | Should -Match 'Category,Name,Version'
    }
}
