Describe 'Northwell printer shareless Task Scheduler + Remote Registry fallback' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:fallbackPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterTaskRegistryFallback.ps1'
        $script:resilientPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterResilientQuick.ps1'
        $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
        $script:corePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
        $script:fallbackText = Get-Content -LiteralPath $script:fallbackPath -Raw
        $script:resilientText = Get-Content -LiteralPath $script:resilientPath -Raw
        $script:cmdText = Get-Content -LiteralPath $script:cmdPath -Raw

        $tokens = $null
        $errors = $null
        $script:fallbackAst = [System.Management.Automation.Language.Parser]::ParseFile($script:fallbackPath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { throw ($errors | ForEach-Object Message | Out-String) }
        $tokens = $null
        $errors = $null
        $script:resilientAst = [System.Management.Automation.Language.Parser]::ParseFile($script:resilientPath,[ref]$tokens,[ref]$errors)
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

    It 'parses both new PowerShell entrypoints' {
        $script:fallbackAst | Should -Not -BeNullOrEmpty
        $script:resilientAst | Should -Not -BeNullOrEmpty
    }

    It 'defines canonical HKLM connection-key conversion to lowercase UNC' {
        $script:convertFnText | Should -Match [regex]::Escape("'^,,([^,]+),(.+)$'")
        $script:convertFnText | Should -Match [regex]::Escape("('\\{0}\{1}' -f `$Matches[1],`$Matches[2]).ToLowerInvariant()")
    }

    It 'builds a direct rundll32 task action without cmd or a staged script' {
        $script:taskActionFnText | Should -Match [regex]::Escape("Join-Path `$SystemRoot 'System32\rundll32.exe'")
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

    It 'routes the quick mapper through the resilient orchestrator' {
        $script:cmdText | Should -Match 'Invoke-NorthwellPrinterResilientQuick\.ps1'
        $script:cmdText | Should -Match 'Start-NorthwellPrinterMapping\.ps1 -Action Map'
        $script:cmdText | Should -Not -Match '-File "%~dp0mapping\\Start-NorthwellPrinterMapping\.ps1" -Action Map'
    }
}