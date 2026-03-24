#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline unit tests for GetInfo\ scripts.
    Validates parameter contracts and output shapes without real WMI/network calls.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $machineInfoPath = Join-Path $repoRoot 'GetInfo\Get-MachineInfo.ps1'
    $kronosInfoPath = Join-Path $repoRoot 'GetInfo\Get-KronosClockInfo.ps1'
}

Describe 'Get-MachineInfo.ps1 — script-level checks' {
    It 'Script file exists' {
        $machineInfoPath | Should -Exist
    }

    It 'Does not use $Host as a variable name (Bug-Log fix)' {
        $content = Get-Content -Path $machineInfoPath -Raw
        # $Host as standalone (not $HostName, $HostList, etc.)
        $content | Should -Not -Match '\$Host\b(?!Name|List|Path|File|Entry|s\b)'
    }

    It 'Has a -ListPath parameter' {
        $content = Get-Content -Path $machineInfoPath -Raw
        $content | Should -Match '\$ListPath'
    }

    It 'Has a -OutputPath parameter' {
        $content = Get-Content -Path $machineInfoPath -Raw
        $content | Should -Match '\$OutputPath'
    }

    It 'Has a throttle/parallelism parameter' {
        $content = Get-Content -Path $machineInfoPath -Raw
        $content | Should -Match '\$Throttle'
    }

    It 'Uses Start-Job for parallelism' {
        $content = Get-Content -Path $machineInfoPath -Raw
        $content | Should -Match 'Start-Job'
    }

    It 'Exports results to CSV' {
        $content = Get-Content -Path $machineInfoPath -Raw
        $content | Should -Match 'Export-Csv'
    }
}

Describe 'Get-MonitorInfo.psm1 — module checks' {
    BeforeAll {
        $modulePath = Join-Path $repoRoot 'GetInfo\Get-MonitorInfo.psm1'
        $script:moduleContent = $null
        if (Test-Path -Path $modulePath) {
            $script:moduleContent = Get-Content -Path $modulePath -Raw -ErrorAction Stop
        }
    }

    It 'Module file exists' {
        (Join-Path $repoRoot 'GetInfo\Get-MonitorInfo.psm1') | Should -Exist
    }

    It 'Contains a function definition' {
        $script:moduleContent | Should -Match 'function\s+\w+'
    }

    It 'Uses WmiMonitorID or CIM for monitor data' {
        $script:moduleContent | Should -Match 'WmiMonitorID|Get-CimInstance|Get-WmiObject'
    }
}

Describe 'QueueInventory.ps1 — script-level checks' {
    BeforeAll {
        $queuePath = Join-Path $repoRoot 'GetInfo\QueueInventory.ps1'
        $script:queueContent = $null
        if (Test-Path -Path $queuePath) {
            $script:queueContent = Get-Content -Path $queuePath -Raw -ErrorAction Stop
        }
    }

    It 'Script file exists' {
        (Join-Path $repoRoot 'GetInfo\QueueInventory.ps1') | Should -Exist
    }

    It 'References printer queue enumeration (Win32_Printer or Get-Printer)' {
        $script:queueContent | Should -Match 'Win32_Printer|Get-Printer'
    }
}

Describe 'Get-KronosClockInfo.ps1 — script-level checks' {
    It 'Script file exists' {
        $kronosInfoPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($kronosInfoPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Supports lookup mode by inventory and identifier' {
        $content = Get-Content -Path $kronosInfoPath -Raw
        $content | Should -Match '\$InventoryPath'
        $content | Should -Match '\$LookupValue'
        $content | Should -Match '\$LookupBy'
    }

    It 'Collects clock identity fields useful for Kronos onboarding' {
        $content = Get-Content -Path $kronosInfoPath -Raw
        $content | Should -Match 'SerialNumber'
        $content | Should -Match 'MACAddress'
        $content | Should -Match 'IPAddress'
        $content | Should -Match 'Model'
        $content | Should -Match 'SysDescr'
        $content | Should -Match 'SysObjectID'
    }

    It 'Uses safe protocol fallbacks instead of assuming one vendor API' {
        $content = Get-Content -Path $kronosInfoPath -Raw
        $content | Should -Match 'snmpget|snmpwalk'
        $content | Should -Match 'Invoke-WebRequest'
        $content | Should -Match 'arp -a'
    }
}

