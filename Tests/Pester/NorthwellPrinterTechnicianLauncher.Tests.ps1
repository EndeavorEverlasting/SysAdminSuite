#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:launcherPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter.cmd'
    $script:installerPath = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'
    $script:operatorRunPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterOperatorRun.ps1'
    $script:startHerePath = Join-Path $script:repoRoot 'START-HERE-NORTHWELL-PRINTER-MAPPING.md'
    $script:generalStartHerePath = Join-Path $script:repoRoot 'START-HERE-SysAdminSuite.md'
    $script:techTutorialPath = Join-Path $script:repoRoot 'docs\tutorials\NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md'
    $script:managementPath = Join-Path $script:repoRoot 'START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md'
    $script:useCaseMapPath = Join-Path $script:repoRoot 'harness\maps\PRINTER_MAPPING_USE_CASE_MAP.md'
    $script:useCaseReportPath = Join-Path $script:repoRoot 'harness\reports\PRINTER_MAPPING_USE_CASES.md'
    $script:agentsPath = Join-Path $script:repoRoot 'AGENTS.md'
}

Describe 'Northwell non-technical technician printer launcher' {
    It 'provides one obvious technician-facing CMD' {
        Test-Path -LiteralPath $script:launcherPath -PathType Leaf | Should -BeTrue
        $cmd = Get-Content -LiteralPath $script:launcherPath -Raw
        $cmd | Should -Match 'NORTHWELL PRINTER MAPPER'
        $cmd | Should -Match 'SYSTEM-wide for all users'
        $cmd | Should -Match 'hardwire, WAB, or an'
        $cmd | Should -Match 'authenticated Northwell VPN'
        $cmd | Should -Match 'Recent proven PCs and printers'
    }

    It 'uses only installer-owned sibling sas or sibling trusted bootstrap authority' {
        $cmd = Get-Content -LiteralPath $script:launcherPath -Raw
        $siblingIndex = $cmd.IndexOf('call "%~dp0sas.cmd" printer',[System.StringComparison]::Ordinal)
        $bootstrapIndex = $cmd.IndexOf('Bootstrap-SysAdminSuitePrinter.cmd',[System.StringComparison]::Ordinal)
        $siblingIndex | Should -BeGreaterThan -1
        $bootstrapIndex | Should -BeGreaterThan $siblingIndex
        $cmd | Should -Not -Match '(?im)^\s*where\.exe\s+sas\.cmd'
        $cmd | Should -Not -Match '(?im)^\s*call\s+sas\.cmd\s+printer\s*$'
    }

    It 'does not implement or bypass the canonical printer mapper' {
        $cmd = Get-Content -LiteralPath $script:launcherPath -Raw
        $cmd | Should -Not -Match 'Map-NorthwellPrinter-SystemWide\.cmd'
        $cmd | Should -Not -Match 'Invoke-NorthwellPrinter(?:Mapping|State|ResilientQuick)\.ps1'
        $cmd | Should -Not -Match '(?i)PrintUIEntry|rundll32|Add-Printer|Add-PrinterPort|Standard TCP/IP|PrintTestPage'
    }

    It 'preserves failure exit state and tells technicians not to remap blindly' {
        $cmd = Get-Content -LiteralPath $script:launcherPath -Raw
        $cmd | Should -Match 'set "SAS_EXIT=!ERRORLEVEL!"'
        $cmd | Should -Match 'exit /b !SAS_EXIT!'
        $cmd | Should -Match 'Do not keep remapping blindly'
        $cmd | Should -Match 'Keep the error/evidence shown above for your lead'
    }

    It 'is installed beside sas.cmd by the universal launcher installer' {
        $installer = Get-Content -LiteralPath $script:installerPath -Raw
        $installer | Should -Match '\$sourcePrinterTechnicianCmd = Join-Path \$repoRoot ''Map-NorthwellPrinter\.cmd'''
        $installer | Should -Match '\$printerTechnicianCmdDestination = Join-Path \$installRoot ''Map-NorthwellPrinter\.cmd'''
        $installer | Should -Match 'Copy-Item -LiteralPath \$sourcePrinterTechnicianCmd -Destination \$printerTechnicianCmdDestination -Force'
        $installer | Should -Match 'Printer technician CMD:'
    }

    It 'documents the current operator outcome layer without claiming new live proof' {
        Test-Path -LiteralPath $script:operatorRunPath -PathType Leaf | Should -BeTrue
        $operatorRun = Get-Content -LiteralPath $script:operatorRunPath -Raw
        $tutorial = Get-Content -LiteralPath $script:techTutorialPath -Raw
        $operatorRun | Should -Match 'MAPPED NOW:'
        $operatorRun | Should -Match 'ALREADY MAPPED:'
        $operatorRun | Should -Match 'RESULT: READY'
        $operatorRun | Should -Match 'READY NEXT LOGON'
        $tutorial | Should -Match 'MAPPED NOW:'
        $tutorial | Should -Match 'ALREADY MAPPED:'
        $tutorial | Should -Match 'READY NEXT LOGON'
        $tutorial | Should -Match '%LOCALAPPDATA%\\SysAdminSuite\\Cache\\Printer'
        $tutorial | Should -Match '4c5f1252aae24269ac1e0ab28ef9366ea08fd33f'
        $tutorial | Should -Match 'newer one-click technician wrapper still needs its own post-refresh field acceptance'
    }

    It 'keeps technician and advanced tutorials routed to the correct surfaces' {
        $startHere = Get-Content -LiteralPath $script:startHerePath -Raw
        $generalStartHere = Get-Content -LiteralPath $script:generalStartHerePath -Raw
        $tutorial = Get-Content -LiteralPath $script:techTutorialPath -Raw
        $management = Get-Content -LiteralPath $script:managementPath -Raw

        foreach ($text in @($startHere,$generalStartHere,$tutorial,$management)) {
            $text | Should -Match 'Map-NorthwellPrinter\.cmd'
        }
        $startHere | Should -Match 'sas printer'
        $startHere | Should -Match 'Invoke-NorthwellPrinterOperatorRun\.ps1'
        $generalStartHere | Should -Match 'Where is the Northwell printer mapping tutorial'
        $generalStartHere | Should -Match 'Technician walkthrough'
        $tutorial | Should -Match 'Recent proven target PCs'
        $tutorial | Should -Match 'Do not repeatedly run the mapper against the same failure'
        $tutorial | Should -Match 'August 20, 2026'
        $tutorial | Should -Match 'does not by itself claim that a physical document was printed'
        $management | Should -Match 'Advanced Operations'
        $management | Should -Match 'Map-NorthwellPrinter-SystemWide\.cmd'
        $management | Should -Match 'runs\.v1\.jsonl'
    }

    It 'keeps repository governance aligned with human front door versus runtime launcher' {
        $agents = Get-Content -LiteralPath $script:agentsPath -Raw
        $agents | Should -Match '`Map-NorthwellPrinter\.cmd` is the routine human-facing quick/recent-selection technician entrypoint'
        $agents | Should -Match '`Map-NorthwellPrinter-SystemWide\.cmd` remains the trusted current-runtime quick launcher'
        $agents | Should -Match 'installer-owned sibling `sas\.cmd printer` or a sibling trusted printer bootstrap'
        $agents | Should -Match 'routine technician front door, trusted current-runtime quick launcher'
    }

    It 'keeps the use-case harness explicit about human front door versus runtime launcher' {
        $map = Get-Content -LiteralPath $script:useCaseMapPath -Raw
        $report = Get-Content -LiteralPath $script:useCaseReportPath -Raw
        $map | Should -Match 'human-facing entrypoint'
        $map | Should -Match 'Map-NorthwellPrinter-SystemWide\.cmd'
        $map | Should -Match 'Map-NorthwellPrinter\.cmd'
        $map | Should -Match 'Invoke-NorthwellPrinterOperatorRun\.ps1'
        $report | Should -Match 'thin one-click front door'
        $report | Should -Match 'SYSTEM-wide requested printer registration proof in HKLM'
        $report | Should -Match 'MAPPED_NOW'
        $report | Should -Match 'new one-click `Map-NorthwellPrinter\.cmd` wrapper has not yet been separately field-accepted'
        $report | Should -Match 'Physical document output is not claimed'
    }
}
