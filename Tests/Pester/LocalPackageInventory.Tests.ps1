#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scannerPath = Join-Path $script:repoRoot "scripts\Get-SasLocalPackageInventory.ps1"
    $script:schemaPath = Join-Path $script:repoRoot "schemas\harness\local-package-inventory.schema.json"
}

Describe "Local Package Inventory Contract" {
    Context "Script existence and structure" {
        It "Exists at scripts/Get-SasLocalPackageInventory.ps1" {
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
        It "Does not contain installer execution commands" {
            $content = Get-Content -Path $script:scannerPath -Raw
            # Ensure the script doesn't call msiexec or start-process to install or extract
            $content | Should -Not -Match '\bmsiexec(?!\.msi)\b'
            $content | Should -Not -Match 'Start-Process'
            $content | Should -Not -Match 'Invoke-Expression'
            $content | Should -Not -Match '\binvoke-command\b'
        }
    }

    Context "Schema contract and validation" {
        It "Validates the generated fixture output against the schema" {
            $script:schemaPath | Should -Exist
            
            # Execute scanner in FixtureOnly mode
            $inventory = & $script:scannerPath -FixtureOnly
            $inventory | Should -Not -BeNullOrEmpty
            
            $json = ConvertTo-Json $inventory -Depth 10
            $testJsonResult = Test-Json -Json $json -SchemaFile $script:schemaPath
            $testJsonResult | Should -Be $true
        }
    }

    Context "Gitignore policy verification" {
        It "Proves payload files in 'tech emulation/' are ignored by Git" {
            $checkIgnore = git check-ignore "tech emulation/dummy.exe" 2>&1
            $checkIgnore | Should -Match "tech emulation/"
        }

        It "Proves payload files in 'docs/Northwell Apps/' are ignored by Git" {
            $checkIgnore = git check-ignore "docs/Northwell Apps/dummy.exe" 2>&1
            $checkIgnore | Should -Match "docs/Northwell Apps/"
        }

        It "Proves no payload files are tracked by Git" {
            $tracked = git ls-files "tech emulation/*" "docs/Northwell Apps/*" 2>&1
            $tracked | Should -BeNullOrEmpty
        }
    }
}
