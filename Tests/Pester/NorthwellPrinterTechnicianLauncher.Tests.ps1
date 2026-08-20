#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:launcherPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter.cmd'
    $script:installerPath = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'
    $script:startHerePath = Join-Path $script:repoRoot 'START-HERE-NORTHWELL-PRINTER-MAPPING.md'
    $script:techTutorialPath = Join-Path $script:repoRoot 'docs\tutorials\NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md'
    $script:managementPath = Join-Path $script:repoRoot 'START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md'
    $script:useCaseMapPath = Join-Path $script:repoRoot 'harness\maps\PRINTER_MAPPING_USE_CASE_MAP.md'
    $script:useCaseReportPath = Join-Path $script:repoRoot 'harness\reports\PRINTER_MAPPING_USE_CASES.md'
}

Describe 'Northwell non-technical technician printer launcher' {
    It 'provides one obvious technician-facing CMD' {
        Test-Path -LiteralPath $script:launcherPath -PathType Leaf | Should -BeTrue
        $cmd = Get-Content -LiteralPath $script:launcherPath -Raw
        $cmd | Should -Match 'NORTHWELL PRINTER MAPPER'
        $cmd | Should -Match 'SYSTEM-wide for all users'
        $cmd | Should -Match 'hardwire, WAB, or an'
        $cmd | Should -Match 'authenticated Northwell VPN'
        $cmd | Should -Match 'Recent|recent'
    }

    It 'delegates to the installed sas printer path before trusted bootstrap fallback' {
        $cmd = Get-Content -LiteralPath $script:launcherPath -Raw
        $siblingIndex = $cmd.IndexOf('call "%~dp0sas.cmd" printer',[System.StringComparison]::Ordinal)
        $pathIndex = $cmd.IndexOf('call sas.cmd printer',[System.StringComparison]::Ordinal)
        $bootstrapIndex = $cmd.IndexOf('Bootstrap-SysAdminSuitePrinter.cmd',[System.StringComparison]::Ordinal)
        $siblingIndex | Should -BeGreaterThan -1
        $pathIndex | Should -BeGreaterThan $siblingIndex
        $bootstrapIndex | Should -BeGreaterThan $pathIndex
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
        $installer | Should -Match "\$sourcePrinterTechnicianCmd = Join-Path \$repoRoot 'Map-NorthwellPrinter\.cmd'"
        $installer | Should -Match "\$printerTechnicianCmdDestination = Join-Path \$installRoot 'Map-NorthwellPrinter\.cmd'"
        $installer | Should -Match 'Copy-Item -LiteralPath \$sourcePrinterTechnicianCmd -Destination \$printerTechnicianCmdDestination -Force'
        $installer | Should -Match 'Printer technician CMD:'
    }

    It 'keeps technician and advanced tutorials routed to the correct surfaces' {
        $startHere = Get-Content -LiteralPath $script:startHerePath -Raw
        $tutorial = Get-Content -LiteralPath $script:techTutorialPath -Raw
        $management = Get-Content -LiteralPath $script:managementPath -Raw

        foreach ($text in @($startHere,$tutorial,$management)) {
            $text | Should -Match 'Map-NorthwellPrinter\.cmd'
        }
        $startHere | Should -Match 'sas printer'
        $tutorial | Should -Match 'Recent proven target PCs'
        $tutorial | Should -Match 'PASS: requested printer map is proven SYSTEM-wide in HKLM'
        $tutorial | Should -Match 'Do not repeatedly run the mapper against the same failure'
        $tutorial | Should -Match 'August 20, 2026'
        $tutorial | Should -Match 'does not by itself claim that a physical document was printed'
        $management | Should -Match 'Advanced Operations'
        $management | Should -Match 'Map-NorthwellPrinter-SystemWide\.cmd'
    }

    It 'keeps the use-case harness explicit about human front door versus runtime launcher' {
        $map = Get-Content -LiteralPath $script:useCaseMapPath -Raw
        $report = Get-Content -LiteralPath $script:useCaseReportPath -Raw
        $map | Should -Match 'human-facing entrypoint'
        $map | Should -Match 'Map-NorthwellPrinter-SystemWide\.cmd'
        $map | Should -Match 'Map-NorthwellPrinter\.cmd'
        $report | Should -Match 'thin one-click front door'
        $report | Should -Match 'SYSTEM-wide requested printer registration proof in HKLM'
        $report | Should -Match 'Physical document output is not claimed'
    }
}
