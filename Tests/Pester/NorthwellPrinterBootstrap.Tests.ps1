#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:bootstrapPath = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
    $script:bootstrapCmdPath = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.cmd'
    $script:requiredFixturePaths = @(
        'Map-NorthwellPrinter-SystemWide.cmd',
        'mapping\Start-NorthwellPrinterMapping.ps1',
        'mapping\Invoke-NorthwellPrinterMapping.ps1',
        'mapping\Modules\NorthwellPrinterMapping.Core.psm1',
        'scripts\SasTargetNameResolution.psm1',
        'scripts\SasNetworkGuard.psm1',
        'scripts\SasInteractionCache.psm1',
        'Config\interaction-cache-policy.json'
    )

    function New-SasPrinterBootstrapFixture {
        param([Parameter(Mandatory)][string]$Root)
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        foreach ($relativePath in $script:requiredFixturePaths) {
            $path = Join-Path $Root $relativePath
            $parent = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $value = if ($relativePath -like '*.json') { '{"schemaVersion":"fixture"}' } elseif ($relativePath -like '*.cmd') { '@echo off' } else { "# fixture: $relativePath" }
            Set-Content -LiteralPath $path -Value $value -Encoding ASCII
        }

        & git.exe -C $Root init | Out-Null
        & git.exe -C $Root config user.email 'fixture@example.invalid'
        & git.exe -C $Root config user.name 'SysAdminSuite Fixture'
        & git.exe -C $Root add -A
        & git.exe -C $Root commit -m 'fixture printer runtime' | Out-Null
        $head = (& git.exe -C $Root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not create printer bootstrap fixture commit.' }
        return $head
    }
}

Describe 'Northwell printer from-anywhere bootstrap contract' {
    It 'does not require the caller to already be inside a Git repository' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Not -Match 'rev-parse\s+--show-toplevel'
        $text | Should -Match 'Current directory is not used as repository authority'
        $text | Should -Match 'SAS_RUNTIME_ROOT'
        $text | Should -Match 'C:\\SASAL'
        $text | Should -Match 'SAS_REPO_ROOT'
        $text | Should -Match 'LOCALAPPDATA'
    }

    It 'pins a safe printer baseline and accepts newer mainline by ancestry' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match "\[string\]\$RequiredCommit = '5463c0ed3fedc4f9c5fe8048ead3cfc6bf2c434f'"
        $text | Should -Match "merge-base','--is-ancestor"
        $text | Should -Match 'Current origin/\$Branch does not contain required printer fix commit'
        $text | Should -Not -Match 'origin/main.*-ne.*RequiredCommit'
    }

    It 'requires complete clean runtime authority and preserves arbitrary operator work' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        foreach ($path in @(
            'mapping\\Invoke-NorthwellPrinterMapping\.ps1',
            'NorthwellPrinterMapping\.Core\.psm1',
            'SasTargetNameResolution\.psm1',
            'SasNetworkGuard\.psm1',
            'SasInteractionCache\.psm1',
            'interaction-cache-policy\.json'
        )) { $text | Should -Match $path }
        $text | Should -Match "status','--porcelain','--untracked-files=no'"
        $text | Should -Match 'Test-SasTrackedRuntimeClean -Root \$candidate'
        $text | Should -Match "worktree','add','--detach'"
        $text | Should -Not -Match 'reset\s+--hard'
        $text | Should -Not -Match 'clean\s+-[a-zA-Z]*f'
        $text | Should -Not -Match 'checkout\s+-f'
        $text | Should -Match 'latest-runtime\.txt'
    }

    It 'serializes dedicated cache/runtime creation instead of racing shared worktree paths' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match 'System\.Threading\.Mutex'
        $text | Should -Match 'SysAdminSuitePrinterBootstrapCache'
        $text | Should -Match 'WaitOne'
        $text | Should -Match 'ReleaseMutex'
    }

    It 'does not expose a repository URL that conflicts with fixed origin validation' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match "\$repositoryUrl = 'https://github\.com/EndeavorEverlasting/SysAdminSuite\.git'"
        $text | Should -Not -Match '\[string\]\$RepositoryUrl'
    }

    It 'adds no reachability ritual before printer mapping' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Not -Match '(?im)^\s*Test-Connection\b'
        $text | Should -Not -Match '(?im)^\s*&?\s*ping(?:\.exe)?\b'
        $text | Should -Not -Match '(?i)-Count\s+5\b'
    }

    It 'keeps the clickable wrapper self-relative, baseline-pinned, and exit-code preserving' {
        Test-Path -LiteralPath $script:bootstrapCmdPath | Should -BeTrue
        $cmd = Get-Content -LiteralPath $script:bootstrapCmdPath -Raw
        $cmd | Should -Match '%~dp0Bootstrap-SysAdminSuitePrinter\.ps1'
        $cmd | Should -Match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
        $cmd | Should -Match '-RequiredCommit 5463c0ed3fedc4f9c5fe8048ead3cfc6bf2c434f'
        $cmd | Should -Match 'exit /b %ERRORLEVEL%'
    }

    It 'resolves a valid runtime from an arbitrary non-repository working directory' {
        $fixture = Join-Path $TestDrive 'runtime'
        $arbitraryCwd = Join-Path $TestDrive 'not-a-repo'
        $localAppData = Join-Path $TestDrive 'localappdata'
        New-Item -ItemType Directory -Path $arbitraryCwd -Force | Out-Null
        New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
        $head = New-SasPrinterBootstrapFixture -Root $fixture

        $oldRuntime = $env:SAS_RUNTIME_ROOT
        $oldRepo = $env:SAS_REPO_ROOT
        $oldLocalAppData = $env:LOCALAPPDATA
        try {
            $env:SAS_RUNTIME_ROOT = $fixture
            Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
            $env:LOCALAPPDATA = $localAppData
            Push-Location $arbitraryCwd
            try {
                $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:bootstrapPath -RequiredCommit $head -NoLaunch 2>&1)
                $bootstrapExit = [int]$LASTEXITCODE
                if ($bootstrapExit -ne 0) {
                    throw "Bootstrap fixture exited $bootstrapExit.`n$($output -join [Environment]::NewLine)"
                }
            }
            finally { Pop-Location }

            ($output -join "`n") | Should -Match 'PASS: printer runtime resolved; launcher not executed'
            ($output -join "`n") | Should -Match [regex]::Escape($fixture)
        }
        finally {
            if ($null -eq $oldRuntime) { Remove-Item Env:SAS_RUNTIME_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_RUNTIME_ROOT = $oldRuntime }
            if ($null -eq $oldRepo) { Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_REPO_ROOT = $oldRepo }
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'rejects a dirty reusable runtime instead of executing tracked local edits' {
        $fixture = Join-Path $TestDrive 'dirty-runtime'
        $localAppData = Join-Path $TestDrive 'dirty-localappdata'
        $badCache = Join-Path $localAppData 'bad-cache'
        New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
        New-Item -ItemType Directory -Path $badCache -Force | Out-Null
        $head = New-SasPrinterBootstrapFixture -Root $fixture
        Add-Content -LiteralPath (Join-Path $fixture 'mapping\Start-NorthwellPrinterMapping.ps1') -Value '# tracked local edit'

        $oldRuntime = $env:SAS_RUNTIME_ROOT
        $oldRepo = $env:SAS_REPO_ROOT
        $oldLocalAppData = $env:LOCALAPPDATA
        try {
            $env:SAS_RUNTIME_ROOT = $fixture
            Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
            $env:LOCALAPPDATA = $localAppData
            $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:bootstrapPath -RequiredCommit $head -CacheRoot $badCache -NoLaunch 2>&1)
            $LASTEXITCODE | Should -Not -Be 0
            ($output -join "`n") | Should -Match 'cache path already exists but is not a Git worktree'
            ($output -join "`n") | Should -Not -Match 'PASS: printer runtime resolved'
        }
        finally {
            if ($null -eq $oldRuntime) { Remove-Item Env:SAS_RUNTIME_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_RUNTIME_ROOT = $oldRuntime }
            if ($null -eq $oldRepo) { Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_REPO_ROOT = $oldRepo }
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }
}
