#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:startPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:enginePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:statePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:diagnosticPath = Join-Path $script:repoRoot 'mapping\Diagnose-NorthwellPrinterEvidence.ps1'
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

    It 'captures lower-level engine chatter but automatically summarizes a failed fresh proof' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match '& \$engine @invokeParameters \*>&1'
        $text | Should -Match '\$actionVerb = if \(\$Action -eq ''Map''\) \{ ''Mapping'' \} else \{ ''Unmapping'' \}'
        $text | Should -Match '\{0\} \{1\} queue\(s\) on \{2\} target\(s\)'
        $text | Should -Not -Match '\{0\}ing \{1\} queue\(s\)'
        $text | Should -Not -Match '(?i)Maping'
        $text | Should -Match 'PASS: requested printer \{0\} is proven SYSTEM-wide in HKLM'
        $text | Should -Match 'FAIL: authoritative machine-wide printer proof was not obtained'
        $text | Should -Match 'Write-SasPrinterFailureDiagnostic -EvidenceRoot \$evidenceRoot'
        $text | Should -Match 'Diagnose-NorthwellPrinterEvidence\.ps1'
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

    It 'requires fresh run-scoped evidence and preserves the exact engine failure after diagnosis' {
        $text = Get-Content -LiteralPath $script:startPath -Raw
        $text | Should -Match '\$previousEvidenceRoot = Get-SasLatestPrinterEvidenceRoot'
        $text | Should -Match '\$freshEvidence ='
        $text | Should -Match '\$authoritativeSuccess = \$freshEvidence -and'
        $text | Should -Match 'if \(\$freshEvidence\) \{ Write-SasPrinterFailureDiagnostic -EvidenceRoot \$evidenceRoot \}'
        $text | Should -Match 'if \(\$null -ne \$engineError\) \{ throw \$engineError\.Exception\.Message \}'
        $text | Should -Not -Match 'fresh evidence but did not prove the requested SYSTEM-wide HKLM state'
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

    It 'classifies an existing user-visible printer as machine-wide missing when HKLM proof is absent' {
        $root = Join-Path $TestDrive 'missing-machine-wide'
        $target = Join-Path $root 'lpw003asi173.nslijhs.net'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        [ordered]@{
            Success = $false
            DesiredState = 'Present'
            TotalTargets = 1
            Mode = 'MachineWidePerComputer'
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'Summary.json') -Encoding UTF8
        [ordered]@{
            ComputerName = 'LPW003ASI173'
            Identity = 'NT AUTHORITY\SYSTEM'
            DesiredState = 'Present'
            Success = $false
            Requested = @('\\SYKPNHPHPS01V\LS001-EMS01')
            BeforeMachineWideUNC = @()
            MachineWideUNC = @()
            ChangedPrinters = @()
            AlreadyDesiredPrinters = @()
            Missing = @('\\SYKPNHPHPS01V\LS001-EMS01')
            StillPresent = @()
            RawConnectionKeys = @('{synthetic-guid}')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $target 'Status.json') -Encoding UTF8

        $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:diagnosticPath -EvidenceRoot $root 2>&1)
        $LASTEXITCODE | Should -Be 0
        $text = $output -join "`n"
        $text | Should -Match 'DIAGNOSTIC_STATUS=COMPLETED'
        $text | Should -Match 'MAPPING_PROOF=AUTHORITATIVE_MACHINE_WIDE_PROOF_NOT_PRESENT'
        $text | Should -Match 'CLASSIFICATION=MACHINE_WIDE_REGISTRATION_MISSING'
        $text | Should -Match 'MISSING_MACHINE_WIDE=\\\\SYKPNHPHPS01V\\LS001-EMS01'
        $text | Should -Match 'TARGET_CONTACT_PERFORMED=False'
        $text | Should -Match 'TARGET_MUTATION_PERFORMED=False'
        $text | Should -Match 'TEST_PAGE_PRINTED=False'
    }

    It 'recognizes a true already-desired HKLM no-op as authoritative machine-wide proof' {
        $root = Join-Path $TestDrive 'already-machine-wide'
        $target = Join-Path $root 'pc001.nslijhs.net'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        [ordered]@{ Success=$true;DesiredState='Present';TotalTargets=1;Mode='MachineWidePerComputer' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'Summary.json') -Encoding UTF8
        [ordered]@{
            ComputerName='PC001';Identity='NT AUTHORITY\SYSTEM';DesiredState='Present';Success=$true
            Requested=@('\\PRINTSRV01\QUEUE01');BeforeMachineWideUNC=@('\\PRINTSRV01\QUEUE01')
            MachineWideUNC=@('\\PRINTSRV01\QUEUE01');ChangedPrinters=@();AlreadyDesiredPrinters=@('\\PRINTSRV01\QUEUE01')
            Missing=@();StillPresent=@();RawConnectionKeys=@(',,PRINTSRV01,QUEUE01')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $target 'Status.json') -Encoding UTF8

        $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:diagnosticPath -EvidenceRoot $root 2>&1)
        $LASTEXITCODE | Should -Be 0
        $text = $output -join "`n"
        $text | Should -Match 'MAPPING_PROOF=AUTHORITATIVE_MACHINE_WIDE_PROOF_PRESENT'
        $text | Should -Match 'CLASSIFICATION=MACHINE_WIDE_REGISTRATION_PROVEN'
        $text | Should -Match 'ALREADY_DESIRED_MACHINE_WIDE=\\\\PRINTSRV01\\QUEUE01'
    }

    It 'keeps the evidence diagnostic strictly local and read-only' {
        $text = Get-Content -LiteralPath $script:diagnosticPath -Raw
        $text | Should -Not -Match '(?i)Test-Connection'
        $text | Should -Not -Match '(?i)schtasks\.exe'
        $text | Should -Not -Match '(?i)rundll32\.exe'
        $text | Should -Not -Match '(?i)Invoke-Command'
        $text | Should -Match 'target_contact_performed = \$false'
        $text | Should -Match 'target_mutation_performed = \$false'
        $text | Should -Match 'test_page_printed = \$false'
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
