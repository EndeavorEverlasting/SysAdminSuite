#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:applyScript = Join-Path $script:repoRoot "scripts\Invoke-SasWezTermWindowsNativeProfile.ps1"
    $script:templatePath = Join-Path $script:repoRoot "Config\wezterm-windows.lua.template"
    $script:fixturePath = Join-Path $script:repoRoot "Tests\Fixtures\workstation-inventory\windows-native.fixture.json"
}

Describe "Windows-Native WezTerm Profile Contract" {
    Context "Scripts and templates presence" {
        It "Exists scripts/Invoke-SasWezTermWindowsNativeProfile.ps1" {
            $script:applyScript | Should -Exist
        }

        It "Exists Config/wezterm-windows.lua.template" {
            $script:templatePath | Should -Exist
        }

        It "Parses cleanly without syntax errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $script:applyScript, [ref]$tokens, [ref]$errors
            ) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    Context "Safety and fail-closed posture" {
        It "Fails closed on Apply without AllowTargetMutation" {
            $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "wezterm-test-$(New-Guid)") -Force
            try {
                $result = & $script:applyScript -UserConfigDir $tempDir.FullName -Action Apply -InventoryFixturePath $script:fixturePath -Confirm:$false
                $result.success | Should -Be $false
                $result.error | Should -Match "AllowTargetMutation not authorized"
            } finally {
                Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Configuration rendering branches (Fixtures)" {
        It "Successfully runs Plan mode" {
            $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "wezterm-test-$(New-Guid)") -Force
            try {
                $result = & $script:applyScript -UserConfigDir $tempDir.FullName -Action Plan -InventoryFixturePath $script:fixturePath -Confirm:$false
                $result.success | Should -Be $true
                $result.plan | Should -Not -BeNullOrEmpty
            } finally {
                Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Renders default configuration when WezTerm config is empty or missing" {
            $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "wezterm-test-$(New-Guid)") -Force
            try {
                $result = & $script:applyScript -UserConfigDir $tempDir.FullName -Action Apply -AllowTargetMutation -InventoryFixturePath $script:fixturePath -Confirm:$false
                $result.success | Should -Be $true
                
                $weztermLua = Join-Path $tempDir.FullName ".wezterm.lua"
                $sasLua = Join-Path $tempDir.FullName ".wezterm-sysadminsuite.lua"
                $weztermLua | Should -Exist
                $sasLua | Should -Exist

                $weztermContent = Get-Content -Raw -Path $weztermLua
                $weztermContent | Should -Match "BEGIN SYSADMINSUITE MANAGED BLOCK"
                $weztermContent | Should -Match "return config"
            } finally {
                Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Preserves existing customized config outside the managed block" {
            $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "wezterm-test-$(New-Guid)") -Force
            try {
                $weztermLua = Join-Path $tempDir.FullName ".wezterm.lua"
                $customConfig = @"
-- User custom config
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
config.color_scheme = 'AdventureTime'

return config
"@
                [System.IO.File]::WriteAllText($weztermLua, $customConfig, [System.Text.Encoding]::UTF8)

                $result = & $script:applyScript -UserConfigDir $tempDir.FullName -Action Apply -AllowTargetMutation -InventoryFixturePath $script:fixturePath -Confirm:$false
                $result.success | Should -Be $true

                $content = Get-Content -Raw -Path $weztermLua
                $content | Should -Match "config\.color_scheme = 'AdventureTime'"
                $content | Should -Match "BEGIN SYSADMINSUITE MANAGED BLOCK"
                $content | Should -Match "return config"
            } finally {
                Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Supports rollback to restore original configuration" {
            $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "wezterm-test-$(New-Guid)") -Force
            try {
                $weztermLua = Join-Path $tempDir.FullName ".wezterm.lua"
                $customConfig = "-- Original Custom Config"
                [System.IO.File]::WriteAllText($weztermLua, $customConfig, [System.Text.Encoding]::UTF8)

                $applyRes = & $script:applyScript -UserConfigDir $tempDir.FullName -Action Apply -AllowTargetMutation -InventoryFixturePath $script:fixturePath -Confirm:$false
                $applyRes.success | Should -Be $true

                $rollbackRes = & $script:applyScript -UserConfigDir $tempDir.FullName -Action Rollback -AllowTargetMutation -InventoryFixturePath $script:fixturePath -Confirm:$false
                $rollbackRes.success | Should -Be $true

                $content = Get-Content -Raw -Path $weztermLua
                $content.Trim() | Should -Be $customConfig
            } finally {
                Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
