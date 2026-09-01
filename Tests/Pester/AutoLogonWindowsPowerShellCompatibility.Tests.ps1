#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'AutoLogon Windows PowerShell 5.1 compatibility' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:bootstrapCmd = Join-Path $repoRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
        $script:bootstrapPs1 = Join-Path $repoRoot 'Bootstrap-SysAdminSuiteAutoLogon.ps1'
        $script:manifestResolver = Join-Path $repoRoot 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'
        $script:sealAuditor = Join-Path $repoRoot 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
        $script:bootstrapText = Get-Content -LiteralPath $script:bootstrapCmd -Raw
        $script:windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $script:systemModules = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
        $script:cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    }

    It 'normalizes the inbox module root and executes SHA256 before any manifest or target-capable bootstrap work' {
        $bootstrapText | Should -Match 'set "SAS_PS_SYSTEM_MODULES=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\Modules"'
        $bootstrapText | Should -Match 'set "PSModulePath=%SAS_PS_SYSTEM_MODULES%;%PSModulePath%"'
        $bootstrapText | Should -Match 'Get-FileHash -LiteralPath'
        $bootstrapText | Should -Match '-Algorithm SHA256 -ErrorAction Stop'
        $bootstrapText | Should -Match 'Get-FileHash SHA-256 capability proof'
        $bootstrapText | Should -Match 'No target contact or AutoLogon field transaction was started\.'

        $normalize = $bootstrapText.IndexOf('set "PSModulePath=%SAS_PS_SYSTEM_MODULES%;%PSModulePath%"', [StringComparison]::Ordinal)
        $hashProbe = $bootstrapText.IndexOf('$hash = Get-FileHash', [StringComparison]::Ordinal)
        $manifest = $bootstrapText.IndexOf('=== RESOLVING SEALED MANIFEST AUTHORITY - NO TARGET CONTACT ===', [StringComparison]::Ordinal)
        $protectedBootstrap = $bootstrapText.IndexOf('=== SEALED RUNTIME AUDIT PASSED - ENTERING PROTECTED BOOTSTRAP ===', [StringComparison]::Ordinal)
        $normalize | Should -BeGreaterThan -1
        $hashProbe | Should -BeGreaterThan $normalize
        $manifest | Should -BeGreaterThan $hashProbe
        $protectedBootstrap | Should -BeGreaterThan $manifest
    }

    It 'recovers working Get-FileHash when a PowerShell 7 style inherited module path omits Windows PowerShell inbox modules' {
        Test-Path -LiteralPath $windowsPowerShell -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $systemModules 'Microsoft.PowerShell.Utility') -PathType Container | Should -BeTrue

        $fixturePath = Join-Path $TestDrive 'ps51-hash-fixture.txt'
        [IO.File]::WriteAllText($fixturePath, 'sas-ps51-hash-fixture', [Text.UTF8Encoding]::new($false))
        $previousModulePath = $env:PSModulePath
        $previousFixturePath = $env:SAS_HASH_FIXTURE_PATH
        try {
            $env:PSModulePath = 'C:\__sas_intentionally_missing_modules__'
            $env:PSModulePath = "$systemModules;$env:PSModulePath"
            $env:SAS_HASH_FIXTURE_PATH = $fixturePath
            $output = & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command @'
$ErrorActionPreference = 'Stop'
Get-Command Get-FileHash -ErrorAction Stop | Out-Null
$hash = Get-FileHash -LiteralPath $env:SAS_HASH_FIXTURE_PATH -Algorithm SHA256 -ErrorAction Stop
[Console]::Out.Write($hash.Algorithm + '|' + $hash.Hash)
'@
            $LASTEXITCODE | Should -Be 0
            ([string]$output).Trim() | Should -Match '^SHA256\|[0-9A-Fa-f]{64}$'
        }
        finally {
            $env:PSModulePath = $previousModulePath
            $env:SAS_HASH_FIXTURE_PATH = $previousFixturePath
        }
    }

    It 'executes the real CMD SHA256 gate in an isolated runtime before deterministically rejecting manifest authority' {
        Test-Path -LiteralPath $cmdExe -PathType Leaf | Should -BeTrue
        $isolatedRuntime = Join-Path $TestDrive 'isolated-runtime'
        $isolatedScripts = Join-Path $isolatedRuntime 'scripts'
        $isolatedLocalAppData = Join-Path $TestDrive 'isolated-localappdata'
        New-Item -ItemType Directory -Path $isolatedScripts,$isolatedLocalAppData -Force | Out-Null
        Copy-Item -LiteralPath $bootstrapCmd -Destination (Join-Path $isolatedRuntime 'Bootstrap-SysAdminSuiteAutoLogon.cmd')
        Copy-Item -LiteralPath $bootstrapPs1 -Destination (Join-Path $isolatedRuntime 'Bootstrap-SysAdminSuiteAutoLogon.ps1')
        Copy-Item -LiteralPath $manifestResolver -Destination (Join-Path $isolatedScripts 'Resolve-SasAutoLogonManifestAuthority.ps1')
        Copy-Item -LiteralPath $sealAuditor -Destination (Join-Path $isolatedScripts 'Test-SasAutoLogonRuntimeSeal.ps1')
        $isolatedBootstrapCmd = Join-Path $isolatedRuntime 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
        $impossiblePreparedCommit = '1111111111111111111111111111111111111111'

        $previousModulePath = $env:PSModulePath
        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:PSModulePath = 'C:\__sas_intentionally_missing_modules__'
            $env:LOCALAPPDATA = $isolatedLocalAppData
            $commandLine = '"{0}" fixture.autologon.invalid {1}' -f $isolatedBootstrapCmd,$impossiblePreparedCommit
            $output = @(& $cmdExe /d /c $commandLine 2>&1)
            $exitCode = [int]$LASTEXITCODE
            $text = ($output | ForEach-Object { [string]$_ }) -join "`n"

            $exitCode | Should -Not -Be 0
            $text | Should -Match 'PASS: Windows PowerShell 5\.1 inbox utility commands are available for the protected process tree\.'
            $text | Should -Match '=== RESOLVING SEALED MANIFEST AUTHORITY - NO TARGET CONTACT ==='
            $text | Should -Match 'AUTOLOGON_MANIFEST_NOT_FOUND'
            $text | Should -Match 'Deployment blocked before runtime audit and crash-safe field transaction\.'
            $text | Should -Not -Match 'could not execute the Get-FileHash SHA-256 capability proof'
            $text | Should -Not -Match '=== SEALED RUNTIME AUDIT PASSED - ENTERING PROTECTED BOOTSTRAP ==='
        }
        finally {
            $env:PSModulePath = $previousModulePath
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }

    It 'keeps the compatibility repair process-scoped and free of repository or target mutation' {
        $bootstrapText | Should -Not -Match '(?im)^\s*(?:git|git\.exe)\s+'
        $bootstrapText | Should -Not -Match '(?i)Set-ItemProperty|New-ItemProperty|Register-ScheduledTask|New-ScheduledTask'
        $bootstrapText | Should -Match 'setlocal EnableExtensions DisableDelayedExpansion'
        $bootstrapText | Should -Match 'Git network activity: NONE'
    }
}
