Describe 'Invoke-TrackedInstall' {
    BeforeAll {
        $ScriptPath = Join-Path $PSScriptRoot '../../scripts/powershell/Invoke-TrackedInstall.ps1'
    }

    It 'script exists' {
        Test-Path -LiteralPath $ScriptPath | Should -BeTrue
    }

    It 'has comment-based help synopsis' {
        $content = Get-Content -LiteralPath $ScriptPath -Raw
        $content | Should -Match '\.SYNOPSIS'
        $content | Should -Match '\.DESCRIPTION'
    }

    It 'dry-run works with direct InstallerPath and does not execute installer' {
        Mock Start-Process { throw 'Should not execute on dry run' }
        $result = & $ScriptPath -Target localhost -DryRun -SoftwareId EXAMPLE-SOFTWARE-ID -InstallerPath 'C:\Installers\ExampleApp\setup.exe' -InstallerType exe -SilentArgs '/quiet /norestart'
        $result.status | Should -Be 'DryRun'
        Assert-MockCalled Start-Process -Times 0
    }

    It 'creates output JSON when OutputPath is supplied and JSON parses' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('trackedinstall-' + [guid]::NewGuid().Guid)
        $outPath = Join-Path $tempDir 'installer_result.json'
        $null = & $ScriptPath -Target localhost -DryRun -InstallerPath 'C:\Installers\ExampleApp\setup.exe' -InstallerType exe -SilentArgs '/quiet' -OutputPath $outPath

        Test-Path -LiteralPath $outPath | Should -BeTrue
        $json = Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json
        $json.status | Should -Be 'DryRun'
        $json.installer.installer_path | Should -Be 'C:\Installers\ExampleApp\setup.exe'
        $json.installer.installer_type | Should -Be 'exe'
        $json.installer.silent_args | Should -Be '/quiet'
        $json.installer.PSObject.Properties.Name | Should -Contain 'resolved_from_sources_yaml'

        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }

    It 'non-localhost target returns Unsupported with RemoteInstallNotImplemented' {
        $result = & $ScriptPath -Target 'server01' -DryRun -InstallerPath 'C:\Installers\ExampleApp\setup.exe' -InstallerType exe
        $result.status | Should -Be 'Unsupported'
        $result.errors | Should -Contain 'RemoteInstallNotImplemented'
    }

    It 'missing installer path in execution mode fails safely' {
        $result = & $ScriptPath -Target localhost -SoftwareId EXAMPLE-SOFTWARE-ID
        $result.status | Should -Be 'Failed'
        $result.errors | Should -Contain 'INSTALLER_PATH_REQUIRED_FOR_EXECUTION'
    }

    It 'attempts source config lookup or reports parser/config issue gracefully' {
        $result = & $ScriptPath -Target localhost -DryRun -SoftwareId 'NotPresentApp' -SourceConfigPath 'Config/sources.yaml'
        @('SOFTWARE_ID_NOT_FOUND','YAML_PARSER_UNAVAILABLE','SOURCE_CONFIG_SHAPE_UNSUPPORTED','SOURCE_CONFIG_NOT_FOUND','SOURCE_CONFIG_PARSE_FAILED') | Should -Contain $result.errors[0]
    }

    It 'does not contain forbidden registry write/remoting/snapshot/diff commands' {
        $content = Get-Content -LiteralPath $ScriptPath -Raw
        $forbidden = @(
            'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg add','reg delete','reg import','reg restore',
            'Start-Service RemoteRegistry','Stop-Service RemoteRegistry','Set-Service RemoteRegistry','Enable-PSRemoting',
            'RegistrySnapshot','Compare-Object.*Registry','reg export'
        )

        foreach ($token in $forbidden) {
            $content | Should -Not -Match [regex]::Escape($token)
        }
    }
}
