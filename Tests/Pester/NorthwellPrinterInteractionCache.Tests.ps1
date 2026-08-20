#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:interactivePath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:batchPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterBatch.ps1'
    $script:fileLauncherPath = Join-Path $script:repoRoot 'Map-NorthwellPrinters-FromFile.cmd'
    $script:batchLauncherPath = Join-Path $script:repoRoot 'Map-NorthwellPrinters-Batch.cmd'
    $script:cacheModulePath = Join-Path $script:repoRoot 'scripts\SasInteractionCache.psm1'
}

Describe 'Northwell printer low-rework interaction UX' {
    It 'offers recent proven host and printer selections instead of requiring repeated terminal reconstruction' {
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $content | Should -Match "Get-SasRecentInteractionValues -Kind Host"
        $content | Should -Match "recent number\(s\) or hostname\(s\)"
        $content | Should -Match "Get-SasRecentInteractionValues -Kind Printer"
        $content | Should -Match "Printer number\(s\), or Enter"
        $content | Should -Match "Get-SasRecentInteractionValues -Kind Server"
    }

    It 'records history only after fresh authoritative SYSTEM plus HKLM proof succeeds' {
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $successIndex = $content.IndexOf('$authoritativeSuccess =')
        $cacheWriteIndex = $content.IndexOf('Save-SasPrinterInteractionHistory -Computers')
        $proofIndex = $content.IndexOf('Test-SasLatestAuthoritativePrinterProof')
        $successIndex | Should -BeGreaterThan -1
        $cacheWriteIndex | Should -BeGreaterThan $successIndex
        $proofIndex | Should -BeGreaterThan -1
        $content | Should -Match '\$freshEvidence -and \(Test-SasLatestAuthoritativePrinterProof'
        $content | Should -Match "if \(\$Action -eq 'Map'\) \{ Save-SasPrinterInteractionHistory"
        $content | Should -Not -Match '(?m)^\s*Save-SasPrinterInteractionHistory.*\$WhatIf'
    }

    It 'keeps cache failures advisory rather than downgrading proven printer success' {
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $content | Should -Match 'Cache persistence is advisory'
        $content | Should -Match 'Write-SasPrinterResult -Success \$true'
        $content | Should -Match 'Add-SasInteractionCacheEntry'
    }

    It 'feeds history from successful Map batch groups but never preview or Unmap groups' {
        $content = Get-Content -LiteralPath $script:batchPath -Raw
        $content | Should -Match 'if \(-not \$cacheAvailable -or \$WhatIf\) \{ return \}'
        $content | Should -Match "if \(\$success -and \$group\.Action -eq 'Map'\) \{ Save-SasBatchInteractionHistory -Group \$group \}"
        $content | Should -Match 'MACHINE_WIDE_\$\(\$desiredState\.ToUpperInvariant\(\)\)_PROVED'
        $content | Should -Match "DesiredState = \$desiredState"
    }

    It 'provides one clearly named click launcher that delegates to the canonical batch file path' {
        Test-Path -LiteralPath $script:fileLauncherPath -PathType Leaf | Should -BeTrue
        $content = Get-Content -LiteralPath $script:fileLauncherPath -Raw
        $content | Should -Match 'call "%~dp0Map-NorthwellPrinters-Batch\.cmd"'
        $content | Should -Match 'exit /b %ERRORLEVEL%'
        $content | Should -Not -Match '(?i)powershell'
        $content | Should -Not -Match '(?i)PrintUIEntry'
        (Get-Content -LiteralPath $script:batchLauncherPath -Raw) | Should -Match 'mapping\\NorthwellPrinterBatch\.csv'
    }

    It 'keeps the interaction cache local, scoped, and separate from authoritative printer state' {
        $cacheContent = Get-Content -LiteralPath $script:cacheModulePath -Raw
        $interactiveContent = Get-Content -LiteralPath $script:interactivePath -Raw
        $batchContent = Get-Content -LiteralPath $script:batchPath -Raw
        $interactiveContent | Should -Match '\$cacheScope = ''northwell'''
        $batchContent | Should -Match '\$cacheScope = ''northwell'''
        $cacheContent | Should -Match 'LocalApplicationData'
        $cacheContent | Should -Not -Match '(?i)HKEY_LOCAL_MACHINE|PrintUIEntry'
        $cacheContent | Should -Not -Match '(?i)health.?hospitals'
    }
}
