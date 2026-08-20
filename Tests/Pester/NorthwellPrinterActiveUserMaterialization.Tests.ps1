#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:finalizerPath = Join-Path $script:repoRoot 'mapping\Confirm-NorthwellPrinterActiveUserMaterialization.ps1'
    $script:batchFinalizerPath = Join-Path $script:repoRoot 'mapping\Confirm-NorthwellPrinterBatchActiveUserMaterialization.ps1'
    $script:agentPath = Join-Path $script:repoRoot 'mapping\Agents\Invoke-NorthwellPrinterActiveUserAgent.ps1'
    $script:sharelessActiveUserPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterSharelessActiveUser.ps1'
    $script:operatorPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterOperatorRun.ps1'
    $script:quickCmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
    $script:batchCmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinters-Batch.cmd'
}

Describe 'Northwell active-user printer materialization regression' {
    It 'parses the Windows PowerShell 5.1 finalization surfaces' {
        foreach ($path in @($script:finalizerPath, $script:batchFinalizerPath, $script:agentPath, $script:sharelessActiveUserPath, $script:operatorPath)) {
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

    It 'preserves durable /ga proof while adding quiet immediate /in for the existing user token' {
        $text = Get-Content -LiteralPath $script:agentPath -Raw
        $text | Should -Match "'printui\.dll,PrintUIEntry' '/in' '/q'"
        $text | Should -Match 'PrintUI native UI is advisory'
        $text | Should -Match "ProofAuthority = 'CURRENT_USER_PRINTER_CONNECTION_REGISTRY'"
        $text | Should -Match "NativePrintUi = 'QUIET_ADVISORY_ONLY'"
        $text | Should -Match 'TASK_LOGON_INTERACTIVE_TOKEN'
        $text | Should -Match 'RegisterTaskDefinition'
        $text | Should -Match 'LogonType = 3'
        $text | Should -Match 'Win32_ComputerSystem'
        $text | Should -Match 'HKEY_USERS\\\$Sid\\Printers\\Connections'
        $text | Should -Match 'HKEY_CURRENT_USER\\Printers\\Connections'
        $text | Should -Match 'ACTIVE_USER_CONNECTION_VERIFIED'
    }

    It 'keeps shareless active-user PrintUI quiet and trusts HKU proof over native dialog noise' {
        $text = Get-Content -LiteralPath $script:sharelessActiveUserPath -Raw
        $text | Should -Match 'PrintUIEntry /in /q /n'
        $text | Should -Match 'Native Windows printer-install dialogs are advisory only'
        $text | Should -Match 'Get-SasRemoteUserPrinterConnections'
        $text | Should -Match '\$missing = @\(\$Queues \| Where-Object \{ \$observed -notcontains \$_ \}\)'
        $text | Should -Match 'requested printer connection is proven in every loaded interactive user hive'
        $text | Should -Not -Match 'PrintTestPage|Add-Printer\s+-ConnectionName'
    }

    It 'fails closed when an already logged-on user connection is not actually observed' {
        $text = Get-Content -LiteralPath $script:agentPath -Raw
        $text | Should -Match 'MissingFromHku'
        $text | Should -Match 'ACTIVE_USER_CONNECTION_NOT_VERIFIED'
        $text | Should -Match '\$materialized = \(\[bool\]\$userStatus\.Success -and \$missingFromHku\.Count -eq 0\)'

        $finalizer = Get-Content -LiteralPath $script:finalizerPath -Raw
        $finalizer | Should -Match 'if \(-not \[bool\]\$materialization\.Success\)'
        $finalizer | Should -Match 'Printer registration exists, but immediate active-user connection failed'
    }

    It 'reports no logged-on user as pending next logon instead of fake immediate availability' {
        $text = Get-Content -LiteralPath $script:agentPath -Raw
        $text | Should -Match 'MACHINE_WIDE_REGISTERED_PENDING_NEXT_LOGON'
        $text | Should -Match 'MACHINE_WIDE_REGISTRATION_PENDING_LOGON'
        $text | Should -Match 'PendingNextLogon = \$true'

        $finalizer = Get-Content -LiteralPath $script:finalizerPath -Raw
        $finalizer | Should -Match '/ga will apply at the next logon'
    }

    It 'does not introduce a test page, direct-IP mapping, stored-password flow, or Add-Printer fallback' {
        $text = (Get-Content -LiteralPath $script:finalizerPath -Raw) + "`n" +
            (Get-Content -LiteralPath $script:batchFinalizerPath -Raw) + "`n" +
            (Get-Content -LiteralPath $script:agentPath -Raw) + "`n" +
            (Get-Content -LiteralPath $script:sharelessActiveUserPath -Raw)
        $text | Should -Not -Match 'PrintTestPage'
        $text | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $text | Should -Not -Match 'Get-Credential'
        $text | Should -Not -Match '(?i)/RP\b'
        $text | Should -Match 'DirectIpMapping = \$false'
        $text | Should -Match 'TestPagesPrinted = \$false'
    }

    It 'requires prior SYSTEM plus HKLM proof before active-user materialization' {
        $text = Get-Content -LiteralPath $script:finalizerPath -Raw
        $text | Should -Match 'Assert-SasNorthwellPrinterStatusProof'
        $text | Should -Match 'Active-user materialization requires an already successful machine-wide mapping run'
        $text | Should -Match 'New-SasNorthwellPrinterTaskCreateArguments'
    }

    It 'keeps the quick mapper on resilient active-user finalization after resilient machine-wide mapping' {
        $cmd = Get-Content -LiteralPath $script:quickCmdPath -Raw
        $operator = Get-Content -LiteralPath $script:operatorPath -Raw
        $mapperIndex = $operator.IndexOf('Invoke-NorthwellPrinterResilientQuick.ps1')
        $finalizerIndex = $operator.IndexOf('Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1')
        $cmd | Should -Match 'Invoke-NorthwellPrinterOperatorRun\.ps1.*-Action Map'
        $mapperIndex | Should -BeGreaterThan -1
        $finalizerIndex | Should -BeGreaterThan $mapperIndex
        $operator | Should -Match '-File \$finalizer -EvidenceRoot \$evidenceRoot'
        $cmd | Should -Not -Match '-File "%~dp0mapping\\Confirm-NorthwellPrinterActiveUserMaterialization\.ps1"'
        $cmd | Should -Match 'Printer run did not complete.*local admin trail'
        $cmd | Should -Match '(?im)^pause\s*$'
    }

    It 'finalizes batch Map groups without reconnecting Unmap groups' {
        $batchCmd = Get-Content -LiteralPath $script:batchCmdPath -Raw
        $batchCmd | Should -Match 'Confirm-NorthwellPrinterBatchActiveUserMaterialization\.ps1'
        $batchCmd | Should -Match 'Map rows only'

        $batchFinalizer = Get-Content -LiteralPath $script:batchFinalizerPath -Raw
        $batchFinalizer | Should -Match '\$action\s*='
        $batchFinalizer | Should -Match '\$action\.Equals'
        $batchFinalizer | Should -Match '\$skippedUnmapGroups\+\+'
        $batchFinalizer | Should -Match 'Confirm-NorthwellPrinterActiveUserMaterialization\.ps1'
        $batchFinalizer | Should -Match 'SkippedUnmapGroups = \$skippedUnmapGroups'
        $batchFinalizer | Should -Match 'Machine-wide batch state succeeded, but active-user finalization failed'
    }
}
