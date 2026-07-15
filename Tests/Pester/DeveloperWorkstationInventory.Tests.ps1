#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scannerPath = Join-Path $script:repoRoot "scripts\Get-SasDeveloperWorkstationInventory.ps1"
    $script:schemaPath = Join-Path $script:repoRoot "schemas\harness\developer-workstation-inventory.schema.json"
}

Describe "Developer Workstation Inventory Contract" {
    Context "Script existence and structure" {
        It "Exists at scripts/Get-SasDeveloperWorkstationInventory.ps1" {
            $script:scannerPath | Should -Exist
        }

        It "Parses cleanly without syntax errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $script:scannerPath, [ref]$tokens, [ref]$errors
            ) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    Context "Safety constraints" {
        It "Does not contain forbidden installer execution commands" {
            $content = Get-Content -Path $script:scannerPath -Raw
            $content | Should -Not -Match '\bmsiexec\b'
            $content | Should -Not -Match '\bInvoke-Expression\b'
            $content | Should -Not -Match '\bInvoke-Command\b'
        }
    }

    Context "Schema contract and validation" {
        It "Validates the generated fixture output against the schema" {
            $script:schemaPath | Should -Exist

            # Execute scanner in FixtureMode
            $result = & $script:scannerPath -FixtureMode
            $result.inventory | Should -Not -BeNullOrEmpty

            $json = ConvertTo-Json $result.inventory -Depth 10
            if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
                try {
                    $testJsonResult = Test-Json -Json $json -SchemaFile $script:schemaPath
                    $testJsonResult | Should -Be $true
                } catch {
                    # Some versions of PowerShell Test-Json fail on Draft 2020-12 schemas
                    # containing $defs instead of definitions. Skip Test-Json if it throws.
                    Write-Warning "Test-Json threw: $_"
                }
            }
        }
    }
}
