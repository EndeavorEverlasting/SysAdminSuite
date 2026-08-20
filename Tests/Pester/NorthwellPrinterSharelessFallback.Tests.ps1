Describe 'Northwell printer shareless Task Scheduler + Remote Registry fallback' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:fallbackPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterTaskRegistryFallback.ps1'
        $script:resilientPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterResilientQuick.ps1'
        $script:activeRouterPath = Join-Path $script:repoRoot 'mapping\Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1'
        $script:sharelessActivePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterSharelessActiveUser.ps1'
        $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
        $script:corePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
        $script:fallbackText = Get-Content -LiteralPath $script:fallbackPath -Raw
        $script:resilientText = Get-Content -LiteralPath $script:resilientPath -Raw
        $script:activeRouterText = Get-Content -LiteralPath $script:activeRouterPath -Raw
        $script:sharelessActiveText = Get-Content -LiteralPath $script:sharelessActivePath -Raw
        $script:cmdText = Get-Content -LiteralPath $script:cmdPath -Raw

        $tokens = $null
        $errors = $null
        $script:fallbackAst = [System.Management.Automation.Language.Parser]::ParseFile($script:fallbackPath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { throw ($errors | ForEach-Object Message | Out-String) }
        $tokens = $null
        $errors = $null
        $script:resilientAst = [System.Management.Automation.Language.Parser]::ParseFile($script:resilientPath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { throw ($errors | ForEach-Object Message | Out-String) }
        $tokens = $null
        $errors = $null
        $script:activeRouterAst = [System.Management.Automation.Language.Parser]::ParseFile($script:activeRouterPath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { throw ($errors | ForEach-Object Message | Out-String) }
        $tokens = $null
        $errors = $null
        $script:sharelessActiveAst = [System.Management.Automation.Language.Parser]::ParseFile($script:sharelessActivePath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { throw ($errors | ForEach-Object Message | Out-String) }

        $script:convertFnText = ($script:fallbackAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'ConvertFrom-SasRemotePrinterConnectionKey'
        },$true)).Extent.Text
        $script:taskActionFnText = ($script:fallbackAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'New-SasSharelessPrinterTaskAction'
        },$true)).Extent.Text
        Import-Module $script:corePath -Force
    }

    It 'parses all resilient mapping and active-user entrypoints' {
        $script:fallbackAst | Should -Not -BeNullOrEmpty
        $script:resilientAst | Should -Not -BeNullOrEmpty
        $script:activeRouterAst | Should -Not -BeNullOrEmpty
        $script:sharelessActiveAst | Should -Not -BeNullOrEmpty
    }

    It 'defines canonical HKLM connection-key conversion to lowercase UNC' {
        $script:convertFnText | Should -Match ([regex]::Escape("'^,,([^,]+),(.+)$'"))
        $script:convertFnText | Should -Match ([regex]::Escape("('\\{0}\{1}' -f `$Matches[1],`$Matches[2]).ToLowerInvariant()"))
    }

    It 'builds a direct rundll32 task action without cmd or a staged script' {
        $script:taskActionFnText | Should -Match ([regex]::Escape("Join-Path `$SystemRoot 'System32\rundll32.exe'"))
        $script:taskActionFnText | Should -Match 'printui\.dll,PrintUIEntry'
        $script:taskActionFnText | Should -Match '\{1\} /n"\{2\}"'
        $script:taskActionFnText | Should -Not -Match '(?i)cmd\.exe|powershell|\.ps1'
    }

    It 'keeps the scheduled task principal SYSTEM and elevated through the canonical builder' {
        $args = New-SasNorthwellPrinterTaskCreateArguments -Computer 'fixture.example.invalid' -TaskName 'Fixture' -RemoteLauncherLocal 'rundll32.exe fixture'
        ($args -join ' ') | Should -Match '(?i)/RU SYSTEM'
        ($args -join ' ') | Should -Match '(?i)/RL HIGHEST'
    }

    It 'proves Remote Registry authority before any Task Scheduler mutation' {
        $registryIndex = $script:fallbackText.IndexOf('Get-SasRemoteSystemRoot -Computer $computer',[System.StringComparison]::Ordinal)
        $taskCreateIndex = $script:fallbackText.IndexOf('New-SasNorthwellPrinterTaskCreateArguments',[System.StringComparison]::Ordinal)
        $registryIndex | Should -BeGreaterThan -1
        $taskCreateIndex | Should -BeGreaterThan $registryIndex
    }

    It 'accepts success only from post-task remote HKLM desired-state proof' {
        $script:fallbackText | Should -Match ([regex]::Escape('$afterProof = Get-SasRemoteMachineWidePrinterConnections -Computer $computer'))
        $script:fallbackText | Should -Match ([regex]::Escape("StatusAuthority = 'CONTROLLER_REMOTE_REGISTRY'"))
        $script:fallbackText | Should -Match ([regex]::Escape("Transport = 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'"))
    }

    It 'records mutation attempts separately from proven changed printers' {
        $script:fallbackText | Should -Match 'MutationAttemptedPrinters'
        $script:fallbackText | Should -Match 'ChangedPrinters'
        $script:fallbackText | Should -Match 'Get-SasChangedRequestedPrinters'
    }

    It 'does not introduce test-page or direct-IP printer behavior' {
        $script:fallbackText | Should -Not -Match '(?i)PrintTestPage|TestPagePrinted\s*=\s*\$true|Add-PrinterPort|Standard TCP/IP|/if\b'
        $script:fallbackText | Should -Match 'TestPagesPrinted\s*=\s*\$false'
        $script:sharelessActiveText | Should -Not -Match '(?i)PrintTestPage|Add-PrinterPort|Standard TCP/IP'
        $script:sharelessActiveText | Should -Match 'TestPagesPrinted=\$false'
    }

    It 'permits replay only for complete pre-mutation administrative-staging failures' {
        $script:resilientText | Should -Match 'Test-SasAdministrativeStagingFailureBeforeMutation'
        $script:resilientText | Should -Match ([regex]::Escape("Get-ChildItem -LiteralPath `$EvidenceRoot -Filter 'Status.json'"))
        $script:resilientText | Should -Match ([regex]::Escape("`$message -notmatch '(?i)^Admin share unavailable"))
        $script:resilientText | Should -Match 'ChangedPrinters'
        $script:resilientText | Should -Match 'StagingShare'
    }

    It 'preserves the failed staging evidence before invoking the shareless helper' {
        $preserveIndex = $script:resilientText.IndexOf('AdministrativeStagingFailure.ResolvedPlan.json',[System.StringComparison]::Ordinal)
        $fallbackIndex = $script:resilientText.IndexOf('& $fallbackScript',[System.StringComparison]::Ordinal)
        $preserveIndex | Should -BeGreaterThan -1
        $fallbackIndex | Should -BeGreaterThan $preserveIndex
    }

    It 'routes active-user finalization according to the successful machine-wide transport' {
        $script:activeRouterText | Should -Match ([regex]::Escape("REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE"))
        $script:activeRouterText | Should -Match 'Invoke-NorthwellPrinterSharelessActiveUser\.ps1'
        $script:activeRouterText | Should -Match 'Confirm-NorthwellPrinterActiveUserMaterialization\.ps1'
    }

    It 'normalizes successful child finalizers to exit zero instead of leaking native command state' {
        $script:activeRouterText | Should -Not -Match '\$LASTEXITCODE'
        $script:activeRouterText | Should -Match '(?s)& \$shareless -EvidenceRoot \$EvidenceRoot -TimeoutSeconds \$TimeoutSeconds\s+exit 0'
        $script:activeRouterText | Should -Match '(?s)& \$canonical @invoke\s+exit 0'
    }

    It 'uses remote InteractiveToken tasks and HKU proof for loaded users without SMB staging' {
        $script:sharelessActiveText | Should -Match "New-Object -ComObject 'Schedule\.Service'"
        $script:sharelessActiveText | Should -Match '\.Connect\(\$Computer\)'
        $script:sharelessActiveText | Should -Match 'Principal\.LogonType = 3'
        $script:sharelessActiveText | Should -Match 'RegisterTaskDefinition'
        $script:sharelessActiveText | Should -Match 'PrintUIEntry /in'
        $script:sharelessActiveText | Should -Match 'HKU\\\$Sid\\Printers\\Connections'
        $script:sharelessActiveText | Should -Match 'Assert-SasNorthwellPrinterStatusProof'
        $script:sharelessActiveText | Should -Not -Match '(?i)\\C\$|\\ADMIN\$|Copy-Item.+\\\\'
    }

    It 'reports no loaded interactive user as durable machine-wide registration pending next logon' {
        $script:sharelessActiveText | Should -Match 'MACHINE_WIDE_REGISTERED_PENDING_NEXT_LOGON'
        $script:sharelessActiveText | Should -Match 'PendingNextLogon=\$true'
    }

    It 'verifies all resilient helper files are tracked and clean at runtime HEAD before execution' {
        foreach ($name in @(
            'Invoke-NorthwellPrinterResilientQuick.ps1',
            'Invoke-NorthwellPrinterTaskRegistryFallback.ps1',
            'Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1',
            'Invoke-NorthwellPrinterSharelessActiveUser.ps1'
        )) { $script:cmdText | Should -Match ([regex]::Escape($name)) }
        $script:cmdText | Should -Match 'ls-files --error-unmatch'
        $script:cmdText | Should -Match 'diff --quiet HEAD'
        $integrityIndex = $script:cmdText.IndexOf('ls-files --error-unmatch',[System.StringComparison]::Ordinal)
        $launchIndex = $script:cmdText.IndexOf('-File "%~dp0mapping\Invoke-NorthwellPrinterResilientQuick.ps1"',[System.StringComparison]::Ordinal)
        $integrityIndex | Should -BeGreaterThan -1
        $launchIndex | Should -BeGreaterThan $integrityIndex
    }

    It 'routes the quick mapper through resilient mapping and resilient active-user finalization' {
        $script:cmdText | Should -Match 'Invoke-NorthwellPrinterResilientQuick\.ps1'
        $script:cmdText | Should -Match 'Confirm-NorthwellPrinterActiveUserMaterializationResilient\.ps1'
        $script:cmdText | Should -Match 'Start-NorthwellPrinterMapping\.ps1 -Action Map'
        $script:cmdText | Should -Not -Match '-File "%~dp0mapping\\Start-NorthwellPrinterMapping\.ps1" -Action Map'
        $script:cmdText | Should -Not -Match '-File "%~dp0mapping\\Confirm-NorthwellPrinterActiveUserMaterialization\.ps1"'
    }
}
