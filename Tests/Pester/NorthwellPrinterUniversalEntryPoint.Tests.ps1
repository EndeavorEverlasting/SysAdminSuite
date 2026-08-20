#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:bootstrap = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
    $script:launcher = Join-Path $script:repoRoot 'scripts\Invoke-SasUniversalField.ps1'
    $script:installer = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'

    function New-SasUniversalPrinterFixture {
        param([Parameter(Mandatory)][string]$Root)
        $paths = @(
            'Map-NorthwellPrinter-SystemWide.cmd','Map-NorthwellPrinters-FromFile.cmd','Map-NorthwellPrinters-Batch.cmd',
            'mapping\Start-NorthwellPrinterMapping.ps1','mapping\Start-NorthwellPrinterBatch.ps1',
            'mapping\Invoke-NorthwellPrinterState.ps1','mapping\Modules\NorthwellPrinterMapping.Core.psm1',
            'mapping\Confirm-NorthwellPrinterActiveUserMaterialization.ps1','mapping\Confirm-NorthwellPrinterBatchActiveUserMaterialization.ps1',
            'mapping\Agents\Invoke-NorthwellPrinterActiveUserAgent.ps1','mapping\Examples\NorthwellPrinterBatch.example.csv',
            'scripts\SasTargetNameResolution.psm1','scripts\SasNetworkGuard.psm1','scripts\SasInteractionCache.psm1',
            'Config\interaction-cache-policy.json','scripts\UnrelatedFieldHotfix.ps1'
        )
        foreach ($relative in $paths) {
            $path = Join-Path $Root $relative
            $parent = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $value = if ($relative -like '*.json') { '{"schemaVersion":"fixture"}' } elseif ($relative -like '*.cmd') { '@echo off' } elseif ($relative -like '*.csv') { 'Action,ComputerName,PrintServer,QueueName' } else { "# fixture $relative" }
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
    It 'installs and routes a trusted sibling bootstrap through the current-origin production path' {
        $launcherText = Get-Content -LiteralPath $script:launcher -Raw
        $installerText = Get-Content -LiteralPath $script:installer -Raw
        $launcherText | Should -Match 'Resolve-SasInstalledPrinterBootstrap'
        $launcherText | Should -Match 'Bootstrap-SysAdminSuitePrinter\.ps1'
        $launcherText | Should -Match 'Usage: sas printer \[file\]'
        $launcherText | Should -Match '-Mode \$printerMode'
        $launcherText | Should -Match "-RequiredCommit '66d38dd45881692303f77267e29e4fa44b4a9351'"
        $printerBlock = $launcherText.Split("    'printer' {")[1].Split("`n    'clipboard' {")[0]
        $printerBlock | Should -Not -Match 'Map-NorthwellPrinter-SystemWide\.cmd'
        $printerBlock | Should -Not -Match 'UseLocalRuntimeOnly'
        $installerText | Should -Match 'sourcePrinterBootstrap'
        $installerText | Should -Match 'printerBootstrapDestination'
        $installerText | Should -Match 'Copy-Item -LiteralPath \$sourcePrinterBootstrap -Destination \$printerBootstrapDestination -Force'
    }

    It 'reuses one machine-runtime state root for explicit local fixtures even when unrelated tracked field work is dirty' {
        $fixture = Join-Path $TestDrive 'runtime'
        $localAppData = Join-Path $TestDrive 'localappdata'
        New-Item -ItemType Directory -Path $fixture,$localAppData -Force | Out-Null
        $head = New-SasUniversalPrinterFixture -Root $fixture
        Add-Content -LiteralPath (Join-Path $fixture 'scripts\UnrelatedFieldHotfix.ps1') -Value '# unrelated local repair'
        $oldRuntime = $env:SAS_RUNTIME_ROOT; $oldRepo = $env:SAS_REPO_ROOT; $oldLocalAppData = $env:LOCALAPPDATA
        try {
            $env:SAS_RUNTIME_ROOT = $fixture
            Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
            $env:LOCALAPPDATA = $localAppData
            foreach ($mode in @('Quick','File')) {
                $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:bootstrap -RequiredCommit $head -Mode $mode -UseLocalRuntimeOnly -NoLaunch 2>&1)
                $rc = [int]$LASTEXITCODE
                if ($rc -ne 0) { throw "Bootstrap $mode fixture exited $rc.`n$($output -join [Environment]::NewLine)" }
                $outputText = $output -join "`n"
                $outputText | Should -Match 'PASS: printer runtime resolved; launcher not executed'
                $outputText | Should -Match 'EXPLICIT_LOCAL_ONLY_NO_ORIGIN_CURRENTNESS_CLAIM'
                $outputText | Should -Match ("Mode: {0}" -f $mode)
                $outputText.Contains($fixture) | Should -BeTrue
                $outputText.Contains((Join-Path $fixture '.state\printer-bootstrap')) | Should -BeTrue
                $outputText.Contains($localAppData) | Should -BeFalse
            }
        }
        finally {
            if ($null -eq $oldRuntime) { Remove-Item Env:SAS_RUNTIME_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_RUNTIME_ROOT = $oldRuntime }
            if ($null -eq $oldRepo) { Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_REPO_ROOT = $oldRepo }
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'keeps every current printer dependency fail-closed while ignoring unrelated tracked work' {
        $text = Get-Content -LiteralPath $script:bootstrap -Raw
        $text | Should -Match "@\('status','--porcelain','--untracked-files=no','--'\)"
        $text | Should -Match '\$statusArguments \+= @\(\$script:requiredRuntimePaths\)'
        $text | Should -Match 'Resolve-SasPrinterStateRoot'
        $text | Should -Match '\.state\\printer-bootstrap'
        $text | Should -Match 'Invoke-NorthwellPrinterState\.ps1'
        $text | Should -Match 'Confirm-NorthwellPrinterActiveUserMaterialization\.ps1'
        $text | Should -Match 'Confirm-NorthwellPrinterBatchActiveUserMaterialization\.ps1'
        $text | Should -Match 'Invoke-NorthwellPrinterActiveUserAgent\.ps1'
        $text | Should -Match 'Map-NorthwellPrinters-FromFile\.cmd'
        $text.Contains('$launcherName = if ($Mode -eq ''File'')') | Should -BeTrue
    }
}
