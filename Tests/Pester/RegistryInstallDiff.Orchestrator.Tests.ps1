Describe 'Registry Install Diff Orchestrator' {
    $scriptPath = Join-Path $PSScriptRoot '..\..\scripts\powershell\Invoke-RegistryInstallDiff.ps1'

    It 'exists' {
        Test-Path -LiteralPath $scriptPath | Should -BeTrue
    }

    It 'has comment based help synopsis' {
        $content = Get-Content -LiteralPath $scriptPath -Raw
        $content | Should -Match '\.SYNOPSIS'
        $content | Should -Match '\.DESCRIPTION'
    }

    It 'blocks approved remediation as unsupported' {
        $outRoot = Join-Path $env:TEMP ('rid-approved-' + [guid]::NewGuid())
        $result = & $scriptPath -Mode ReconOnly -Target localhost -OutputRoot $outRoot -ApprovedRemediation 2>&1
        ($result | Out-String) | Should -Match 'ApprovedRemediationNotImplemented|Unsupported'
    }

    It 'does not contain forbidden registry write or remoting patterns' {
        $content = Get-Content -LiteralPath $scriptPath -Raw
        $forbidden = @(
            'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg add','reg delete','reg import','reg restore',
            'Start-Service\s+RemoteRegistry','Stop-Service\s+RemoteRegistry','Set-Service\s+RemoteRegistry','Enable-PSRemoting','PsExec'
        )
        foreach ($pattern in $forbidden) {
            $content | Should -Not -Match $pattern
        }
    }

    It 'recononly runs or records missing dependency gracefully' {
        $outRoot = Join-Path $env:TEMP ('rid-recon-' + [guid]::NewGuid())
        $null = & $scriptPath -Mode ReconOnly -Target localhost -OutputRoot $outRoot 2>&1
        $runDir = Get-ChildItem -LiteralPath $outRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $manifest = Join-Path $runDir.FullName 'run_manifest.json'
        Test-Path $manifest | Should -BeTrue
        $manifestContent = Get-Content $manifest -Raw
        $manifestContent | Should -Match 'MissingDependency|dependency_scripts'
    }

    It 'analyzeinstall dry-run emits manifest and summary' {
        $outRoot = Join-Path $env:TEMP ('rid-analyze-' + [guid]::NewGuid())
        $null = & $scriptPath -Mode AnalyzeInstall -Target localhost -SoftwareId TEST-SW -DryRun -OutputRoot $outRoot 2>&1
        $runDir = Get-ChildItem -LiteralPath $outRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Test-Path (Join-Path $runDir.FullName 'run_manifest.json') | Should -BeTrue
        Test-Path (Join-Path $runDir.FullName 'summary.md') | Should -BeTrue
    }
}
