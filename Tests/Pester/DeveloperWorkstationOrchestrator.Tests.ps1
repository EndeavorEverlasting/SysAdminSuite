#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
BeforeAll {
    $script:repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:entry=Join-Path $script:repo 'scripts\Invoke-SasDeveloperWorkstation.ps1'
}
Describe 'Developer workstation orchestrator' {
    It 'parses the PowerShell entrypoint' {
        $errors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($script:entry,[ref]$null,[ref]$errors)|Out-Null
        @($errors).Count|Should -Be 0
    }
    It 'defaults to Inventory' {
        (Get-Content -Raw $script:entry)|Should -Match "Mode = 'Inventory'"
    }
    It 'fails closed before Apply without authorization' {
        $out=Join-Path $TestDrive 'denied'
        & $script:entry -Mode Apply -FixtureScenario success -OutputRoot $out
        $LASTEXITCODE|Should -Be 0
        (Get-Content -Raw (Join-Path $out 'orchestrator-result.json')|ConvertFrom-Json).outcome|Should -Be 'ACTION_REQUIRED'
    }
    It 'composes the Windows fixture journey' {
        $out=Join-Path $TestDrive 'success'
        & $script:entry -Mode Apply -FixtureScenario success -OutputRoot $out -AllowTargetMutation
        $LASTEXITCODE|Should -Be 0
        $result=Get-Content -Raw (Join-Path $out 'orchestrator-result.json')|ConvertFrom-Json
        $result.outcome|Should -Be 'PASS'
        (Join-Path $out 'agentswitchboard-result.json')|Should -Exist
    }
}
