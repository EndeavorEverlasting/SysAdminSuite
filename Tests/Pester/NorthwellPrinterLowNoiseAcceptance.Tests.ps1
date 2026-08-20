#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:startPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:enginePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:statePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
}

Describe 'Northwell quick mapping low-noise acceptance contract' {
    It 'does not add ICMP reachability rituals to the active quick-map path' {
        $text = (Get-Content -LiteralPath $script:startPath -Raw) + "`n" +
                (Get-Content -LiteralPath $script:enginePath -Raw) + "`n" +
                (Get-Content -LiteralPath $script:statePath -Raw) + "`n" +
                (Get-Content -LiteralPath $script:cmdPath -Raw)
        $text | Should -Not -Match '(?i)Test-Connection'
        $text | Should -Not -Match '(?im)^\s*ping(?:\.exe)?\s+'
        $text | Should -Not -Match '(?i)[\\/]ping\.exe["'']?\s'
        $text | Should -Not -Match '(?i)-Count\s+5\b'
    }

    It 'captures lower-level engine chatter instead of dumping it into the technician terminal' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match '& \$engine @invokeParameters \*>&1'
        $text | Should -Match '\{0\}ing \{1\} queue\(s\) on \{2\} target\(s\)'
        $text | Should -Match 'PASS: requested printer \{0\} is proven SYSTEM-wide in HKLM'
        $text | Should -Match 'FAIL: authoritative machine-wide printer proof was not obtained'
    }

    It 'allows final SYSTEM plus HKLM proof to supersede lower-level controller noise' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match 'Test-SasLatestAuthoritativePrinterProof'
        $text | Should -Match '\[string\]\$status\.Identity -notmatch ''SYSTEM\$'''
        $text | Should -Match '@\(\$status\.Missing\)\.Count -gt 0'
        $text | Should -Match '\$status\.MachineWideUNC'
        $text | Should -Match '\$status\.Requested'
        $text | Should -Match 'RecoveredFromLowerLevelError'
        $text | Should -Match 'superseded by authoritative final printer-state proof'
    }

    It 'requires fresh run-scoped evidence before lower-level errors can be superseded' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match '\$previousEvidenceRoot = Get-SasLatestPrinterEvidenceRoot'
        $text | Should -Match '\$freshEvidence ='
        $text | Should -Match '\$authoritativeSuccess = \$freshEvidence -and'
        $text | Should -Match 'fresh evidence but did not prove the requested SYSTEM-wide HKLM state'
    }

    It 'keeps WhatIf plan-only instead of demanding runtime status proof' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $whatIfIndex = $text.IndexOf('if ($WhatIf) {')
        $proofIndex = $text.IndexOf('$authoritativeSuccess = $freshEvidence -and')
        $whatIfIndex | Should -BeGreaterThan -1
        $proofIndex | Should -BeGreaterThan $whatIfIndex
        $text | Should -Match 'PLAN: preview complete; no printer changes were made'
    }

    It 'preserves actionable early engine errors when no new evidence exists' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match 'if \(\$null -ne \$engineError -and -not \$freshEvidence\)'
        $text | Should -Match 'throw \$engineError\.Exception\.Message'
    }

    It 'keeps the CMD front door short and avoids reparsing evidence paths' {
        $text = Get-Content -LiteralPath $script:cmdPath -Raw
        $text | Should -Match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
        $text | Should -Match 'Start-NorthwellPrinterMapping\.ps1'
        $text | Should -Not -Match 'SAS_LATEST_DIR'
        $text | Should -Not -Match 'set /p'
        $text | Should -Not -Match 'Primary artifacts:'
    }

    It 'preserves the current HKLM child-key proof fix inside the canonical reversible engine' {
        $text = Get-Content -LiteralPath $script:statePath -Raw
        $text | Should -Match 'ConvertFrom-MachineWideConnectionKeyName'
        $text | Should -Match 'RawConnectionKeys'
        $text | Should -Match 'PSChildName'
    }
}
