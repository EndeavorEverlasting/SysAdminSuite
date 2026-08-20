#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:bootstrap = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
    $script:launcher = Join-Path $script:repoRoot 'scripts\Invoke-SasUniversalField.ps1'
    $script:installer = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'

    function New-SasUniversalPrinterFixture {
        param([Parameter(Mandatory)][string]$Root)
        $paths = @(
            'Map-NorthwellPrinter-SystemWide.cmd',
            'Map-NorthwellPrinters-FromFile.cmd',
            'Map-NorthwellPrinters-Batch.cmd',
            'mapping\Start-NorthwellPrinterMapping.ps1',
            'mapping\Start-NorthwellPrinterBatch.ps1',
            'mapping\Invoke-NorthwellPrinterMapping.ps1',
            'mapping\Modules\NorthwellPrinterMapping.Core.psm1',
            'mapping\Examples\NorthwellPrinterBatch.example.csv',
            'scripts\SasTargetNameResolution.psm1',
            'scripts\SasNetworkGuard.psm1',
            'scripts\SasInteractionCache.psm1',
            'Config\interaction-cache-policy.json',
            'scripts\UnrelatedFieldHotfix.ps1'
        )
        foreach ($relative in $paths) {
            $path = Join-Path $Root $relative
            $parent = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            $value = if ($relative -like '*.json') { '{"schemaVersion":"fixture"}' } elseif ($relative -like '*.cmd') { '@echo off' } elseif ($relative -like '*.csv') { 'ComputerName,PrintServer,QueueName' } else { "# fixture $relative" }
            Set-Content -LiteralPath $path -Value $value -Encoding ASCII
        }
        & git.exe -C $Root init | Out-Null
        & git.exe -C $Root config user.email 'fixture@example.invalid'
        & git.exe -C $Root config user.name 'SysAdminSuite Fixture'
        & git.exe -C $Root add -A
        & git.exe -C $Root commit -m 'fixture printer runtime' | Out-Null
        return (& git.exe -C $Root rev-parse HEAD).Trim()
    }
}

Describe 'Universal sas printer entrypoint' {
    It 'installs and routes a trusted sibling bootstrap instead of a controller-root mapper path' {
        $launcherText = Get-Content -LiteralPath $script:launcher -Raw
        $installerText = Get-Content -LiteralPath $script:installer -Raw

        $launcherText | Should -Match 'Resolve-SasInstalledPrinterBootstrap'
        $launcherText | Should -Match 'Bootstrap-SysAdminSuitePrinter\.ps1'
        $launcherText | Should -Match 'Usage: sas printer \[file\]'
        $launcherText | Should -Match '-Mode \$printerMode'
        $printerBlock = $launcherText.Split("    'printer' {")[1].Split("`n    'clipboard' {")[0]
        $printerBlock | Should -Not -Match 'Map-NorthwellPrinter-SystemWide\.cmd'

        $installerText | Should -Match 'sourcePrinterBootstrap'
        $installerText | Should -Match 'printerBootstrapDestination'
        $installerText | Should -Match 'Copy-Item -LiteralPath \$sourcePrinterBootstrap -Destination \$printerBootstrapDestination -Force'
    }

    It 'reuses a printer-clean runtime even when unrelated tracked field work is dirty' {
        $fixture = Join-Path $TestDrive 'runtime'
        $localAppData = Join-Path $TestDrive 'localappdata'
        New-Item -ItemType Directory -Path $fixture,$localAppData -Force | Out-Null
        $head = New-SasUniversalPrinterFixture -Root $fixture
        Add-Content -LiteralPath (Join-Path $fixture 'scripts\UnrelatedFieldHotfix.ps1') -Value '# unrelated local repair'

        $oldRuntime = $env:SAS_RUNTIME_ROOT
        $oldRepo = $env:SAS_REPO_ROOT
        $oldLocalAppData = $env:LOCALAPPDATA
        try {
            $env:SAS_RUNTIME_ROOT = $fixture
            Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
            $env:LOCALAPPDATA = $localAppData

            foreach ($mode in @('Quick','File')) {
                $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:bootstrap -RequiredCommit $head -Mode $mode -NoLaunch 2>&1)
                $rc = [int]$LASTEXITCODE
                if ($rc -ne 0) { throw "Bootstrap $mode fixture exited $rc.`n$($output -join [Environment]::NewLine)" }
                ($output -join "`n") | Should -Match 'PASS: printer runtime resolved; launcher not executed'
                ($output -join "`n") | Should -Match ("Mode: {0}" -f $mode)
                ($output -join "`n").Contains($fixture) | Should -BeTrue
            }
        }
        finally {
            if ($null -eq $oldRuntime) { Remove-Item Env:SAS_RUNTIME_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_RUNTIME_ROOT = $oldRuntime }
            if ($null -eq $oldRepo) { Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_REPO_ROOT = $oldRepo }
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'keeps printer-owned tracked edits fail-closed' {
        $text = Get-Content -LiteralPath $script:bootstrap -Raw
        $text | Should -Match "@\('status','--porcelain','--untracked-files=no','--'\)"
        $text | Should -Match '\$statusArguments \+= @\(\$script:requiredRuntimePaths\)'
        $text | Should -Match 'Map-NorthwellPrinters-FromFile\.cmd'
        $text | Should -Match "\$launcherName = if \(\$Mode -eq 'File'\)"
    }
}
