#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:bootstrapPath = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'
    $script:bootstrapCmdPath = Join-Path $script:repoRoot 'Bootstrap-SysAdminSuitePrinter.cmd'
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

    It 'accepts a required fix by ancestry instead of brittle exact-main equality' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match "merge-base','--is-ancestor"
        $text | Should -Match 'Current origin/\$Branch does not contain required printer fix commit'
        $text | Should -Not -Match 'origin/main.*-ne.*RequiredCommit'
    }

    It 'preserves arbitrary operator work and uses a dedicated detached runtime' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Match "worktree','add','--detach'"
        $text | Should -Match "status','--porcelain','--untracked-files=no'"
        $text | Should -Not -Match 'reset\s+--hard'
        $text | Should -Not -Match 'clean\s+-[a-zA-Z]*f'
        $text | Should -Not -Match 'checkout\s+-f'
        $text | Should -Match 'latest-runtime\.txt'
    }

    It 'adds no reachability ritual before printer mapping' {
        $text = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $text | Should -Not -Match '(?im)^\s*Test-Connection\b'
        $text | Should -Not -Match '(?im)^\s*&?\s*ping(?:\.exe)?\b'
        $text | Should -Not -Match '(?i)-Count\s+5\b'
    }

    It 'keeps the clickable wrapper self-relative and exit-code preserving' {
        Test-Path -LiteralPath $script:bootstrapCmdPath | Should -BeTrue
        $cmd = Get-Content -LiteralPath $script:bootstrapCmdPath -Raw
        $cmd | Should -Match '%~dp0Bootstrap-SysAdminSuitePrinter\.ps1'
        $cmd | Should -Match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
        $cmd | Should -Match 'exit /b %ERRORLEVEL%'
    }

    It 'resolves a valid runtime from an arbitrary non-repository working directory' {
        $fixture = Join-Path $TestDrive 'runtime'
        $arbitraryCwd = Join-Path $TestDrive 'not-a-repo'
        $localAppData = Join-Path $TestDrive 'localappdata'
        New-Item -ItemType Directory -Path (Join-Path $fixture 'mapping') -Force | Out-Null
        New-Item -ItemType Directory -Path $arbitraryCwd -Force | Out-Null
        New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture 'Map-NorthwellPrinter-SystemWide.cmd') -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $fixture 'mapping\Start-NorthwellPrinterMapping.ps1') -Value "Write-Host 'fixture'" -Encoding ASCII

        & git.exe -C $fixture init | Out-Null
        & git.exe -C $fixture config user.email 'fixture@example.invalid'
        & git.exe -C $fixture config user.name 'SysAdminSuite Fixture'
        & git.exe -C $fixture add -- Map-NorthwellPrinter-SystemWide.cmd mapping/Start-NorthwellPrinterMapping.ps1
        & git.exe -C $fixture commit -m 'fixture printer runtime' | Out-Null
        $head = (& git.exe -C $fixture rev-parse HEAD).Trim()
        $LASTEXITCODE | Should -Be 0

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
                $LASTEXITCODE | Should -Be 0
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
}
