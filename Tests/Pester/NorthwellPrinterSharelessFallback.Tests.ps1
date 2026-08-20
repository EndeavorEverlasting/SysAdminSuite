Describe 'Northwell printer shareless Task Scheduler + Remote Registry fallback' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:fallbackPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterTaskRegistryFallback.ps1'
        $script:startPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
        $script:corePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
        $script:fallbackText = Get-Content -LiteralPath $script:fallbackPath -Raw
        $script:startText = Get-Content -LiteralPath $script:startPath -Raw

        $tokens = $null
        $errors = $null
        $script:fallbackAst = [System.Management.Automation.Language.Parser]::ParseFile($script:fallbackPath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { throw ($errors | ForEach-Object Message | Out-String) }

        function Import-SasFunctionFromAst {
            param([Parameter(Mandatory)][string]$Name)
            $fn = $script:fallbackAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
            },$true)
            if (-not $fn) { throw "Function not found in fallback: $Name" }
            Invoke-Expression $fn.Extent.Text
        }

        Import-SasFunctionFromAst -Name 'ConvertFrom-SasRemotePrinterConnectionKey'
        Import-SasFunctionFromAst -Name 'New-SasSharelessPrinterTaskAction'
        Import-Module $script:corePath -Force
    }

    It 'parses under the current PowerShell parser' {
        $script:fallbackAst | Should -Not -BeNullOrEmpty
    }

    It 'converts owning HKLM connection subkeys to canonical UNC values' {
        ConvertFrom-SasRemotePrinterConnectionKey -Name ',,SYKPNHPHPS01V,LS001-EMS01' |
            Should -Be '\\sykpnhphps01v\ls001-ems01'
    }

    It 'builds a direct rundll32 task action without cmd or a staged script' {
        $action = New-SasSharelessPrinterTaskAction -SystemRoot 'C:\Windows' -NativeSwitch '/ga' -Queue '\\SYKPNHPHPS01V\LS001-EMS01'
        $action | Should -Be '"C:\Windows\System32\rundll32.exe" printui.dll,PrintUIEntry /ga /n"\\SYKPNHPHPS01V\LS001-EMS01"'
        $action | Should -Not -Match '(?i)cmd\.exe|powershell|\.ps1'
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
        $script:fallbackText | Should -Match [regex]::Escape("$afterProof = Get-SasRemoteMachineWidePrinterConnections -Computer $computer")
        $script:fallbackText | Should -Match [regex]::Escape("StatusAuthority = 'CONTROLLER_REMOTE_REGISTRY'")
        $script:fallbackText | Should -Match [regex]::Escape("Transport = 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'")
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

    It 'is wired only behind operation-scoped pre-mutation administrative-staging failure evidence' {
        $script:startText | Should -Match 'Test-SasAdministrativeStagingFailureBeforeMutation'
        $script:startText | Should -Match 'Invoke-NorthwellPrinterTaskRegistryFallback\.ps1'
        $script:startText | Should -Match 'AdministrativeStagingFailure\.json'
        $script:startText | Should -Match 'Status\.json'
    }
}
