#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:enginePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:engineText = Get-Content -LiteralPath $script:enginePath -Raw
}

Describe 'Northwell printer administrative staging fallback' {
    It 'parses under Windows PowerShell-compatible syntax' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:enginePath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'prefers C$ and then tries ADMIN$ before declaring staging unavailable' {
        $cIndex = $script:engineText.IndexOf("Name = 'C$'")
        $adminIndex = $script:engineText.IndexOf("Name = 'ADMIN$'")
        $failureIndex = $script:engineText.IndexOf('Admin share unavailable: neither')
        $cIndex | Should -BeGreaterThan -1
        $adminIndex | Should -BeGreaterThan $cIndex
        $failureIndex | Should -BeGreaterThan $adminIndex
        $script:engineText | Should -Match '\\\$computer\\C\$'
        $script:engineText | Should -Match '\\\$computer\\ADMIN\$'
    }

    It 'uses safe matching local paths for each administrative share' {
        $script:engineText | Should -Match "AdminRelative = \"ProgramData\\\\\$remoteSubPath\""
        $script:engineText | Should -Match "LocalRoot = 'C:\\\\ProgramData'"
        $script:engineText | Should -Match "AdminRelative = \"Temp\\\\\$remoteSubPath\""
        $script:engineText | Should -Match "LocalRoot = '%SystemRoot%\\\\Temp'"
        $script:engineText | Should -Match 'StagingShare = if'
    }

    It 'keeps SYSTEM task execution and no-print proof semantics' {
        $corePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
        $core = Get-Content -LiteralPath $corePath -Raw
        $core | Should -Match "'/RU','SYSTEM'"
        $script:engineText | Should -Match 'SMB\+AdministrativeShareFallback\+RemoteTaskScheduler'
        $script:engineText | Should -Match 'TestPagesPrinted = \$false'
        $script:engineText | Should -Not -Match 'PrintTestPage'
        $script:engineText | Should -Not -Match '(?i)Add-PrinterPort|Standard TCP/IP Port'
    }

    It 'does not dereference missing staging paths during fail-closed cleanup' {
        $script:engineText | Should -Match '\$null -ne \$remoteStatusAdmin -and'
        $script:engineText | Should -Match '\$null -ne \$remoteEvidence\.Source -and'
        $script:engineText | Should -Match '\$null -ne \$remoteAdminDir'
    }
}
