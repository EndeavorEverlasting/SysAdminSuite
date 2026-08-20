#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:enginePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:diagnosticPath = Join-Path $script:repoRoot 'mapping\Diagnose-NorthwellPrinterEvidence.ps1'
    $script:engineText = Get-Content -LiteralPath $script:enginePath -Raw
    $script:diagnosticText = Get-Content -LiteralPath $script:diagnosticPath -Raw
}

Describe 'Northwell printer administrative staging fallback' {
    It 'parses under Windows PowerShell-compatible syntax' {
        foreach ($path in @($script:enginePath,$script:diagnosticPath)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
        }
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

    It 'uses a protected SYSTEM-profile path for ADMIN$ instead of Windows Temp' {
        $script:engineText | Should -Match 'AdminRelative = "ProgramData\\\$remoteSubPath"'
        $script:engineText | Should -Match "LocalRoot = 'C:\\ProgramData'"
        $script:engineText | Should -Match 'AdminRelative = "System32\\config\\systemprofile\\AppData\\Local\\\$remoteSubPath"'
        $script:engineText | Should -Match "LocalRoot = '%SystemRoot%\\System32\\config\\systemprofile\\AppData\\Local'"
        $script:engineText | Should -Not -Match 'AdminRelative = "Temp\\'
        $script:engineText | Should -Not -Match "LocalRoot = '%SystemRoot%\\Temp'"
    }

    It 'proves full staging write/read/delete capability and falls through rejected candidates' {
        $script:engineText | Should -Match 'foreach \(\$candidate in \$rootCandidates\.ToArray\(\)\)'
        $script:engineText | Should -Match 'New-Item -ItemType Directory -Path \$candidateDir -Force -ErrorAction Stop'
        $script:engineText | Should -Match "'SAS_STAGING_PROBE' \| Set-Content"
        $script:engineText | Should -Match 'Get-Content -LiteralPath \$probePath -Raw -ErrorAction Stop'
        $script:engineText | Should -Match 'Remove-Item -LiteralPath \$probePath -Force -ErrorAction Stop'
        $script:engineText | Should -Match 'WARN staging candidate \$\(\$candidate\.Name\) rejected'
        $script:engineText | Should -Match 'Admin share unavailable for staging:'
    }

    It 'contains errors from each root probe inside the per-target failure boundary' {
        $tryIndex = $script:engineText.IndexOf('        Write-ControllerLog "[$computer] Preflight administrative staging shares and Task Scheduler."')
        $candidateIndex = $script:engineText.IndexOf('        foreach ($candidate in $stagingCandidates) {')
        $catchMarker = $script:engineText.IndexOf('$probeErrors.Add("$($candidate.Name): $($_.Exception.Message)")')
        $tryIndex | Should -BeGreaterThan -1
        $candidateIndex | Should -BeGreaterThan $tryIndex
        $catchMarker | Should -BeGreaterThan $candidateIndex
        $script:engineText | Should -Match 'Test-Path -LiteralPath \$candidate\.AdminRoot -PathType Container -ErrorAction Stop'
    }

    It 'forces ADMIN$ environment expansion through target-side cmd.exe' {
        $script:engineText | Should -Match '\$remoteTaskAction = if \(\$staging\.Name -eq ''ADMIN\$''\)'
        $script:engineText | Should -Match 'cmd\.exe /d /s /c ""\{0\}""'
        $script:engineText | Should -Match 'New-SasNorthwellPrinterTaskCreateArguments.+-RemoteLauncherLocal \$remoteTaskAction'
    }

    It 'surfaces the selected staging route in read-only evidence diagnostics' {
        $script:engineText | Should -Match 'StagingShare = \$null'
        $script:engineText | Should -Match '\$hostResult\.StagingShare = \[string\]\$staging\.Name'
        $script:diagnosticText | Should -Match 'Get-SasStatusString -Status \$Result -Name ''StagingShare'''
        $script:diagnosticText | Should -Match 'SUMMARY_STAGING_SHARE='
        $script:diagnosticText | Should -Match 'staging_share = \$stagingShare'
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
