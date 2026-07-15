#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
BeforeAll {
    $script:repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scriptPath = Join-Path $script:repo 'scripts\Invoke-SasWindowsTmuxWorkspace.ps1'
    $script:fixture = Join-Path $script:repo 'Tests\Fixtures\windows-tmux-workspace\healthy.json'
}
Describe 'Windows WezTerm tmux workspace service' {
    It 'parses all lifecycle entrypoints' {
        $files = @(Get-ChildItem (Join-Path $script:repo 'scripts') -Filter '*SasWindowsTmuxWorkspace.ps1') + @(Get-Item (Join-Path $script:repo 'scripts\Get-SasWindowsTmuxWorkspaceStatus.ps1'))
        $files.Count | Should -Be 7
        foreach ($file in $files) {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }
    It 'plans without creating fixture state' {
        $root = Join-Path $TestDrive 'plan'
        $result = & $script:scriptPath -Action Plan -FixturePath $script:fixture -UserConfigDir (Join-Path $root 'home') -StateRoot (Join-Path $root 'state')
        $result.outcome | Should -Be 'success' -Because $result.message
        (Join-Path $root 'state') | Should -Not -Exist
    }
    It 'fails closed when Apply is not authorized' {
        $root = Join-Path $TestDrive 'denied'
        $result = & $script:scriptPath -Action Apply -FixturePath $script:fixture -UserConfigDir (Join-Path $root 'home') -StateRoot (Join-Path $root 'state') -Confirm:$false
        $result.outcome | Should -Be 'action-required'
        (Join-Path $root 'home') | Should -Not -Exist
    }
    It 'runs an idempotent fixture lifecycle and restores custom Lua' {
        $root = Join-Path $TestDrive 'lifecycle'; $userRoot = Join-Path $root 'home'; $state = Join-Path $root 'state'
        New-Item -ItemType Directory -Path $userRoot -Force | Out-Null
        $original = "local wezterm = require 'wezterm'`nlocal config = wezterm.config_builder()`nconfig.color_scheme = 'AdventureTime'`nreturn config`n"
        [IO.File]::WriteAllText((Join-Path $userRoot '.wezterm.lua'), $original)
        $apply = & $script:scriptPath -Action Apply -AllowTargetMutation -FixturePath $script:fixture -UserConfigDir $userRoot -StateRoot $state -Confirm:$false
        $apply.outcome | Should -Be 'success' -Because $apply.message
        (& $script:scriptPath -Action Start -LaunchGui -FixturePath $script:fixture -UserConfigDir $userRoot -StateRoot $state -Confirm:$false).outcome | Should -Be 'success'
        (& $script:scriptPath -Action Start -LaunchGui -FixturePath $script:fixture -UserConfigDir $userRoot -StateRoot $state -Confirm:$false).outcome | Should -Be 'success'
        (& $script:scriptPath -Action Status -FixturePath $script:fixture -UserConfigDir $userRoot -StateRoot $state).outcome | Should -Be 'success'
        (& $script:scriptPath -Action Stop -FixturePath $script:fixture -UserConfigDir $userRoot -StateRoot $state -Confirm:$false).outcome | Should -Be 'success'
        (& $script:scriptPath -Action Rollback -AllowTargetMutation -FixturePath $script:fixture -UserConfigDir $userRoot -StateRoot $state -Confirm:$false).outcome | Should -Be 'success'
        (Get-Content -Raw (Join-Path $userRoot '.wezterm.lua')) | Should -Be $original
    }
}
