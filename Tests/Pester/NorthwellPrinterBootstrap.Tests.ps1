#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:bootstrapPath = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
    $script:bootstrapCmdPath = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.cmd'
    $script:requiredFixturePaths = @(
        'Map-NorthwellPrinter-SystemWide.cmd',
        'mapping\Start-NorthwellPrinterMapping.ps1',
        'mapping\Invoke-NorthwellPrinterState.ps1',
        'mapping\Modules\NorthwellPrinterMapping.Core.psm1',
        'mapping\Confirm-NorthwellPrinterActiveUserMaterialization.ps1',
        'mapping\Agents\Invoke-NorthwellPrinterActiveUserAgent.ps1',
        'scripts\SasNorthwellNetworkAuthority.psm1',
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

Describe 'Northwell printer current-runtime bootstrap contract' {
    It 'does not require the caller to already be inside a Git repository' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Not -Match 'rev-parse\s+--show-toplevel'
        $text | Should -Match 'Current directory and dirty operator checkouts are not repository authority'
        $text | Should -Match 'SAS_RUNTIME_ROOT'
        $text | Should -Match 'C:\\SASAL'
        $text | Should -Match 'SAS_REPO_ROOT'
    }

    It 'treats RequiredCommit only as a safety baseline and proves the exact fetched branch head before default launch' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text.Contains("[string]`$RequiredCommit = '66d38dd45881692303f77267e29e4fa44b4a9351'") | Should -BeTrue
        $text | Should -Match "fetch','--no-tags','--prune','origin'"
        $text | Should -Match 'refs/remotes/origin/\$Branch'
        $text | Should -Match '\$remoteHead = Get-SasGitScalar'
        $text | Should -Match 'if \(\$runtimeHead -ne \$remoteHead\)'
        $text | Should -Match 'CURRENT_ORIGIN_BRANCH_HEAD_PROVEN'
        $text | Should -Match 'Stale local printer code will not be launched'
        $text | Should -Not -Match 'Find-SasEligiblePrinterRuntime -Required \$RequiredCommit'
    }

    It 'requires every executable printer authority dependency including the reversible engine and network authority' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match 'mapping\\Invoke-NorthwellPrinterState\.ps1'
        $text | Should -Not -Match "'mapping\\Invoke-NorthwellPrinterMapping\.ps1'"
        $text | Should -Match 'Confirm-NorthwellPrinterActiveUserMaterialization\.ps1'
        $text | Should -Match 'Invoke-NorthwellPrinterActiveUserAgent\.ps1'
        $text | Should -Match 'scripts\\SasNorthwellNetworkAuthority\.psm1'
    }

    It 'keeps operator checkout changes outside runtime authority and never destroys them' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match "status','--porcelain','--untracked-files=no','--'"
        $text | Should -Match '\$statusArguments \+= @\(\$script:requiredRuntimePaths\)'
        $text | Should -Not -Match 'reset\s+--hard'
        $text | Should -Not -Match 'clean\s+-[a-zA-Z]*f'
        $text | Should -Not -Match 'stash\b'
        $text | Should -Not -Match 'git\s+commit'
        $text | Should -Not -Match 'checkout\s+-f'
    }

    It 'serializes exact-head cache/runtime creation and validates the dedicated origin' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match 'System\.Threading\.Mutex'
        $text | Should -Match 'SysAdminSuitePrinterBootstrapCache'
        $text | Should -Match 'Test-SasDedicatedCacheRoot'
        $text | Should -Match 'Test-SasExpectedOrigin'
        $text | Should -Match "worktree','add','--detach'"
        $text | Should -Match 'latest-runtime\.txt'
    }

    It 'does not multiply an invalid exact-head runtime into GUID-suffixed worktrees' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match 'Exact current printer runtime path exists but is invalid or modified'
        $text | Should -Match 'no duplicate runtime was created'
        $text | Should -Not -Match '\$remoteHead \+ ''-'' \+ \[guid\]'
    }

    It 'retires only clean bootstrap-owned superseded runtimes and preserves their evidence first' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match 'Remove-SasSupersededPrinterRuntimes'
        $text | Should -Match 'Test-SasPathInsideRoot'
        $text | Should -Match 'Move-SasPrinterRuntimeEvidence'
        $text | Should -Match "Join-Path \$StateRoot 'evidence'"
        $text | Should -Match "worktree','remove','--force'"
        $text | Should -Match "worktree','prune'"
        $text | Should -Match 'Preserving superseded printer runtime because tracked printer files are modified'
    }

    It 'keeps explicit local-only mode separate from normal current-origin claims' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match '\[switch\]\$UseLocalRuntimeOnly'
        $text | Should -Match 'EXPLICIT_LOCAL_ONLY_NO_ORIGIN_CURRENTNESS_CLAIM'
        $text | Should -Match 'if \(\$UseLocalRuntimeOnly\)'
        $text | Should -Match "use 'sas printer offline'"
    }

    It 'adds no reachability or test-page ritual before printer mapping' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Not -Match '(?im)^\s*Test-Connection\b'
        $text | Should -Not -Match '(?im)^\s*&?\s*ping(?:\.exe)?\b'
        $text | Should -Not -Match '(?i)PrintTestPage'
    }

    It 'keeps the clickable wrapper self-relative and exit-code preserving' {
        Test-Path -LiteralPath $script:bootstrapCmdPath | Should -BeTrue
        $cmd = Get-Content -LiteralPath $script:bootstrapCmdPath -Raw
        $cmd | Should -Match '%~dp0Bootstrap-SysAdminSuitePrinter\.ps1'
        $cmd | Should -Match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
        $cmd | Should -Match 'exit /b %ERRORLEVEL%'
    }

    It 'can explicitly resolve a clean local fixture from an arbitrary non-repository directory without claiming latest origin' {
        $fixture = Join-Path $TestDrive 'runtime'
        $arbitraryCwd = Join-Path $TestDrive 'not-a-repo'
        $localAppData = Join-Path $TestDrive 'localappdata'
        New-Item -ItemType Directory -Path $arbitraryCwd,$localAppData -Force | Out-Null
        $head = New-SasPrinterBootstrapFixture -Root $fixture

        $oldRuntime = $env:SAS_RUNTIME_ROOT; $oldRepo = $env:SAS_REPO_ROOT; $oldLocalAppData = $env:LOCALAPPDATA
        try {
            $env:SAS_RUNTIME_ROOT = $fixture
            Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
            $env:LOCALAPPDATA = $localAppData
            Push-Location $arbitraryCwd
            try {
                $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:bootstrapPath -RequiredCommit $head -UseLocalRuntimeOnly -NoLaunch 2>&1)
                $bootstrapExit = [int]$LASTEXITCODE
                if ($bootstrapExit -ne 0) { throw "Bootstrap fixture exited $bootstrapExit.`n$($output -join [Environment]::NewLine)" }
            }
            finally { Pop-Location }

            $outputText = $output -join "`n"
            $outputText | Should -Match 'PASS: printer runtime resolved; launcher not executed'
            $outputText | Should -Match 'EXPLICIT_LOCAL_ONLY_NO_ORIGIN_CURRENTNESS_CLAIM'
            $outputText.Contains($fixture) | Should -BeTrue
        }
        finally {
            if ($null -eq $oldRuntime) { Remove-Item Env:SAS_RUNTIME_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_RUNTIME_ROOT = $oldRuntime }
            if ($null -eq $oldRepo) { Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_REPO_ROOT = $oldRepo }
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'rejects printer-owned local edits in explicit local-only mode instead of executing or committing them' {
        $fixture = Join-Path $TestDrive 'dirty-runtime'
        $localAppData = Join-Path $TestDrive 'dirty-localappdata'
        New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
        $head = New-SasPrinterBootstrapFixture -Root $fixture
        Add-Content -LiteralPath (Join-Path $fixture 'mapping\Start-NorthwellPrinterMapping.ps1') -Value '# tracked local edit'

        $oldRuntime = $env:SAS_RUNTIME_ROOT; $oldRepo = $env:SAS_REPO_ROOT; $oldLocalAppData = $env:LOCALAPPDATA
        try {
            $env:SAS_RUNTIME_ROOT = $fixture
            Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
            $env:LOCALAPPDATA = $localAppData
            $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:bootstrapPath -RequiredCommit $head -UseLocalRuntimeOnly -NoLaunch 2>&1)
            $LASTEXITCODE | Should -Not -Be 0
            ($output -join "`n") | Should -Match 'No clean local printer runtime contains the required baseline'
            (& git.exe -C $fixture status --porcelain) | Should -Match 'Start-NorthwellPrinterMapping\.ps1'
        }
        finally {
            if ($null -eq $oldRuntime) { Remove-Item Env:SAS_RUNTIME_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_RUNTIME_ROOT = $oldRuntime }
            if ($null -eq $oldRepo) { Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue } else { $env:SAS_REPO_ROOT = $oldRepo }
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }
}
