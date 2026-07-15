#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:collector = Join-Path $script:repoRoot 'scripts\Get-SasDeveloperWorkstationInventory.ps1'
}

Describe 'Execution-domain workstation inventory' {
    It 'parses without PowerShell syntax errors' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:collector, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'emits v2 typed inventory and lifecycle fixture output' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        try {
            $inventoryPath = Join-Path $root 'inventory.json'
            $lifecyclePath = Join-Path $root 'lifecycle.json'
            & $script:collector -Fixture 'tmux-session-healthy' -OutputPath $inventoryPath -LifecycleOutputPath $lifecyclePath
            $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
            $lifecycle = Get-Content -LiteralPath $lifecyclePath -Raw | ConvertFrom-Json
            $inventory.schema_version | Should -Be 'sas-developer-workstation-inventory/v2'
            $inventory.selected_backend | Should -Be 'windows-wsl'
            $inventory.domains[1].backend.tmux.sessions | Should -Contain 'dev'
            $lifecycle.operation | Should -Be 'inventory'
            $lifecycle.proof.persistence_observed | Should -BeFalse
        } finally { Remove-Item -LiteralPath $root -Recurse -Force }
    }

    It 'contains no installation, authentication, or destructive WSL operation' {
        $content = Get-Content -LiteralPath $script:collector -Raw
        $content | Should -Not -Match 'wsl\s+--install|--unregister|Start-Process|Invoke-Expression|oauth'
    }
}
