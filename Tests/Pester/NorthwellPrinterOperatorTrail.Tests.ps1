#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:journalModule = Join-Path $script:repoRoot 'scripts\SasPrinterRunJournal.psm1'
    $script:operatorRunner = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterOperatorRun.ps1'
    $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
    Import-Module $script:journalModule -Force
}

Describe 'Northwell printer local operator trail and outcome UX' {
    It 'parses the local journal and operator wrapper under Windows PowerShell syntax' {
        foreach ($path in @($script:journalModule,$script:operatorRunner)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path -LiteralPath $path),
                [ref]$tokens,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }

    It 'writes only to an explicitly local per-user cache root and leaves sharing to the operator' {
        $cacheRoot = Join-Path $TestDrive 'local-user-cache'
        $summary = [pscustomobject]@{
            Success = $true
            Operation = 'Map'
            DesiredState = 'Present'
            ProofLevel = 'MACHINE_WIDE_REGISTRATION_PRESENT'
            Computers = @('PC001')
            Printers = @('\\PRINT01\QUEUE01')
            Results = @([pscustomobject]@{
                Computer='PC001';Success=$true;Stage='VerifiedPresent';Message='verified';DesiredState='Present'
                ChangedPrinters=@();AlreadyDesiredPrinters=@('\\PRINT01\QUEUE01');StagingShare='NONE';Transport='REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'
            })
        }
        $result = Write-SasPrinterRunJournalEvent -SessionId 'fixture-run' -Event 'RUN_COMPLETED' -Outcome 'READY' -Message 'fixture' -Summary $summary -CacheRoot $cacheRoot
        $result | Should -Not -BeNullOrEmpty
        $result.JournalPath.StartsWith([IO.Path]::GetFullPath($cacheRoot),[System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        Test-Path -LiteralPath $result.JournalPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.LatestPath -PathType Leaf | Should -BeTrue
        $latest = Get-Content -LiteralPath $result.LatestPath -Raw | ConvertFrom-Json
        $latest.StorageScope | Should -Be 'LOCAL_USER_CACHE_ONLY'
        $latest.Sharing | Should -Be 'OPERATOR_DECIDES'
        $latest.Operation | Should -Be 'Map'
        $latest.DesiredState | Should -Be 'Present'
        @($latest.Targets) | Should -Contain 'PC001'
        @($latest.Printers) | Should -Contain '\\PRINT01\QUEUE01'
        @($latest.TargetResults).Count | Should -Be 1
        $latest.TargetResults[0].Stage | Should -Be 'VerifiedPresent'
        $latest.TargetResults[0].Transport | Should -Be 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'
        @($latest.TargetResults[0].AlreadyDesiredPrinters) | Should -Contain '\\PRINT01\QUEUE01'
    }

    It 'keeps the local JSONL trail bounded instead of allowing unbounded field-log growth' {
        $cacheRoot = Join-Path $TestDrive 'bounded-cache'
        for ($i = 0; $i -lt 14; $i++) {
            $null = Write-SasPrinterRunJournalEvent -SessionId "fixture-$i" -Event 'PROGRESS' -Outcome 'IN_PROGRESS' -Message ('x' * 1800) -CacheRoot $cacheRoot -MaxJournalBytes 16384
        }
        $paths = Get-SasPrinterRunJournalPaths -CacheRoot $cacheRoot
        Test-Path -LiteralPath $paths.JournalPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $paths.PreviousJournalPath -PathType Leaf | Should -BeTrue
        (Get-Item -LiteralPath $paths.JournalPath).Length | Should -BeLessThan 20000
    }

    It 'distinguishes a new machine-wide mapping from an authoritative already-mapped no-op' {
        $already = [pscustomobject]@{
            Success = $true
            Results = @([pscustomobject]@{ ChangedPrinters=@(); AlreadyDesiredPrinters=@('\\PRINT01\QUEUE01') })
        }
        $changed = [pscustomobject]@{
            Success = $true
            Results = @([pscustomobject]@{ ChangedPrinters=@('\\PRINT01\QUEUE01'); AlreadyDesiredPrinters=@() })
        }
        (Get-SasPrinterMachineWideOutcome -Summary $already -Action Map) | Should -Be 'ALREADY_MAPPED'
        (Get-SasPrinterMachineWideOutcome -Summary $changed -Action Map) | Should -Be 'MAPPED_NOW'
    }

    It 'turns DNS printer-server absence into a friendly NOT FOUND outcome without inventing endpoint changes' {
        $friendly = Get-SasPrinterFriendlyFailure -Message "Print server 'PRINT-MISSING' did not resolve in DNS. No endpoint changes were made."
        $friendly.Outcome | Should -Be 'NOT_FOUND'
        $friendly.Headline | Should -Match '^NOT FOUND:'
        $friendly.Headline | Should -Match 'No endpoint changes were made'
    }

    It 'journals progress before mapping, then preserves the existing mapper and active-user finalizer order' {
        $text = Get-Content -LiteralPath $script:operatorRunner -Raw
        $journalIndex = $text.IndexOf("-Event 'RUN_STARTED'")
        $mapperIndex = $text.IndexOf('& $mapper -Action $Action')
        $finalizerIndex = $text.IndexOf('& $finalizer')
        $journalIndex | Should -BeGreaterThan -1
        $mapperIndex | Should -BeGreaterThan $journalIndex
        $finalizerIndex | Should -BeGreaterThan $mapperIndex
        $text | Should -Match 'ALREADY MAPPED:'
        $text | Should -Match 'MAPPED NOW:'
        $text | Should -Match 'NOT FOUND:'
        $text | Should -Match 'RESULT: READY'
    }

    It 'keeps durable operator journaling local-only and does not add target probes or printer mutation primitives' {
        $journalText = Get-Content -LiteralPath $script:journalModule -Raw
        $runnerText = Get-Content -LiteralPath $script:operatorRunner -Raw
        $combined = $journalText + "`n" + $runnerText
        $journalText | Should -Match 'LocalApplicationData'
        $journalText | Should -Match 'SysAdminSuite\\Cache\\Printer'
        $journalText | Should -Match 'LOCAL_USER_CACHE_ONLY'
        $journalText | Should -Match 'OPERATOR_DECIDES'
        $journalText | Should -Not -Match '(?i)schtasks\.exe|rundll32\.exe|Invoke-Command|Test-Connection|PrintTestPage|Add-Printer'
        $combined | Should -Not -Match '(?i)Test-Connection|PrintTestPage|Add-Printer\s+-ConnectionName'
        $combined | Should -Not -Match '(?i)KeepRemoteArtifacts'
    }

    It 'routes the CMD front door through the operator wrapper and explicitly keeps the terminal open' {
        $text = Get-Content -LiteralPath $script:cmdPath -Raw
        $text | Should -Match 'Invoke-NorthwellPrinterOperatorRun\.ps1'
        $text | Should -Match 'SasPrinterRunJournal\.psm1'
        $text | Should -Match 'terminal remains open'
        $text | Should -Match '(?im)^pause\s*$'
        $text | Should -Not -Match '-File "%~dp0mapping\\Invoke-NorthwellPrinterResilientQuick\.ps1"'
        $text | Should -Not -Match '-File "%~dp0mapping\\Confirm-NorthwellPrinterActiveUserMaterializationResilient\.ps1"'
    }
}
