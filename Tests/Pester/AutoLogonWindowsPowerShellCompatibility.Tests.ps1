#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'AutoLogon Windows PowerShell 5.1 compatibility' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:bootstrapCmd = Join-Path $repoRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
        $script:bootstrapText = Get-Content -LiteralPath $script:bootstrapCmd -Raw
        $script:windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $script:systemModules = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
    }

    It 'normalizes the inbox module root before any manifest or target-capable bootstrap work' {
        $bootstrapText | Should -Match 'set "SAS_PS_SYSTEM_MODULES=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\Modules"'
        $bootstrapText | Should -Match 'set "PSModulePath=%SAS_PS_SYSTEM_MODULES%;%PSModulePath%"'
        $bootstrapText | Should -Match 'Get-Command Get-FileHash -ErrorAction Stop'
        $bootstrapText | Should -Match 'No target contact or AutoLogon field transaction was started\.'

        $normalize = $bootstrapText.IndexOf('set "PSModulePath=%SAS_PS_SYSTEM_MODULES%;%PSModulePath%"', [StringComparison]::Ordinal)
        $hashProbe = $bootstrapText.IndexOf('Get-Command Get-FileHash -ErrorAction Stop', [StringComparison]::Ordinal)
        $manifest = $bootstrapText.IndexOf('=== RESOLVING SEALED MANIFEST AUTHORITY - NO TARGET CONTACT ===', [StringComparison]::Ordinal)
        $protectedBootstrap = $bootstrapText.IndexOf('=== SEALED RUNTIME AUDIT PASSED - ENTERING PROTECTED BOOTSTRAP ===', [StringComparison]::Ordinal)
        $normalize | Should -BeGreaterThan -1
        $hashProbe | Should -BeGreaterThan $normalize
        $manifest | Should -BeGreaterThan $hashProbe
        $protectedBootstrap | Should -BeGreaterThan $manifest
    }

    It 'recovers Get-FileHash when a PowerShell 7 style inherited module path omits Windows PowerShell inbox modules' {
        Test-Path -LiteralPath $windowsPowerShell -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $systemModules 'Microsoft.PowerShell.Utility') -PathType Container | Should -BeTrue

        $previous = $env:PSModulePath
        try {
            $env:PSModulePath = 'C:\__sas_intentionally_missing_modules__'
            $env:PSModulePath = "$systemModules;$env:PSModulePath"
            $output = & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command @'
$ErrorActionPreference = 'Stop'
$command = Get-Command Get-FileHash -ErrorAction Stop
[Console]::Out.Write($command.Name + '|' + $command.CommandType)
'@
            $LASTEXITCODE | Should -Be 0
            ([string]$output).Trim() | Should -Match '^Get-FileHash\|Cmdlet$'
        }
        finally {
            $env:PSModulePath = $previous
        }
    }

    It 'keeps the compatibility repair process-scoped and free of repository or target mutation' {
        $bootstrapText | Should -Not -Match '(?im)^\s*(?:git|git\.exe)\s+'
        $bootstrapText | Should -Not -Match '(?i)Set-ItemProperty|New-ItemProperty|Register-ScheduledTask|New-ScheduledTask'
        $bootstrapText | Should -Match 'setlocal EnableExtensions DisableDelayedExpansion'
        $bootstrapText | Should -Match 'Git network activity: NONE'
    }
}
