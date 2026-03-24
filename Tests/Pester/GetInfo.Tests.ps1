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

Describe 'Get-MachineInfo.ps1 -- script-level checks' {
    BeforeAll {
        $script:machineInfoContent = Get-Content -Path $machineInfoPath -Raw
    }

    It 'Script file exists' {
        $machineInfoPath | Should -Exist
    }

    It 'Does not use $Host as a variable name (Bug-Log fix)' {
        # $Host as standalone (not $HostName, $HostList, etc.)
        $script:machineInfoContent | Should -Not -Match '\$Host\b(?!Name|List|Path|File|Entry|s\b)'
    }

    It 'Has a -ListPath parameter' {
        $script:machineInfoContent | Should -Match '\$ListPath'
    }

    It 'Has a -OutputPath parameter' {
        $script:machineInfoContent | Should -Match '\$OutputPath'
    }

    It 'Has a throttle/parallelism parameter' {
        $script:machineInfoContent | Should -Match '\$Throttle'
    }

    It 'Uses Start-Job for parallelism' {
        $script:machineInfoContent | Should -Match 'Start-Job'
    }

    It 'Exports results to CSV' {
        $script:machineInfoContent | Should -Match 'Export-Csv'
    }

    It 'Keeps the ErrorMessage column in every output row shape' {
        $script:machineInfoContent | Should -Match 'Status\s*=\s*''OK''[\s\S]*?ErrorMessage\s*=\s*'''''
        $script:machineInfoContent | Should -Match 'Status\s*=\s*''Query Failed''[\s\S]*?ErrorMessage\s*=\s*\$errMsg'
        $script:machineInfoContent | Should -Match 'Status\s*=\s*''Offline''[\s\S]*?ErrorMessage\s*=\s*'''''
    }
}

Describe 'Get-MonitorInfo.psm1 -- module checks' {
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

Describe 'QueueInventory.ps1 -- script-level checks' {
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

Describe 'Get-KronosClockInfo.ps1 -- script-level checks' {
    BeforeAll {
        $script:kronosInfoContent = Get-Content -Path $kronosInfoPath -Raw
    }

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
        $script:kronosInfoContent | Should -Match '\$InventoryPath'
        $script:kronosInfoContent | Should -Match '\$LookupValue'
        $script:kronosInfoContent | Should -Match '\$LookupBy'
    }

    It 'Collects clock identity fields useful for Kronos onboarding' {
        $script:kronosInfoContent | Should -Match 'SerialNumber'
        $script:kronosInfoContent | Should -Match 'MACAddress'
        $script:kronosInfoContent | Should -Match 'IPAddress'
        $script:kronosInfoContent | Should -Match 'Model'
        $script:kronosInfoContent | Should -Match 'SysDescr'
        $script:kronosInfoContent | Should -Match 'SysObjectID'
    }

    It 'Uses safe protocol fallbacks instead of assuming one vendor API' {
        $script:kronosInfoContent | Should -Match 'snmpget|snmpwalk'
        $script:kronosInfoContent | Should -Match 'Invoke-WebRequest'
        $script:kronosInfoContent | Should -Match 'arp -a'
    }

    It 'Exports the exact Kronos probe schema for unresolved targets' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        $tempCsv = Join-Path $tempRoot 'KronosClockInventory.csv'
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        try {
            $results = @(& $kronosInfoPath -Targets 'definitely-not-a-real-kronos-host.invalid' -OutCsv $tempCsv)
            $results.Count | Should -Be 1
            ($results[0].PSObject.Properties.Name -join ',') | Should -Be 'QueryInput,Reachable,IPAddress,ReverseDns,HostName,DeviceName,MACAddress,SerialNumber,Model,Manufacturer,Firmware,SysName,SysDescr,SysObjectID,DeviceID,Source,Notes'
            $results[0].Reachable | Should -BeFalse
            $results[0].Source | Should -Be 'Resolution'
            $results[0].Notes | Should -Be 'Could not resolve target to an IPv4 address.'
            (Get-Content -Path $tempCsv -First 1) | Should -Be '"QueryInput","Reachable","IPAddress","ReverseDns","HostName","DeviceName","MACAddress","SerialNumber","Model","Manufacturer","Firmware","SysName","SysDescr","SysObjectID","DeviceID","Source","Notes"'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Performs MAC lookup against inventory rows using normalized formatting' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        $tempCsv = Join-Path $tempRoot 'KronosClockInventory.csv'
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        @'
QueryInput,Reachable,IPAddress,ReverseDns,HostName,DeviceName,MACAddress,SerialNumber,Model,Manufacturer,Firmware,SysName,SysDescr,SysObjectID,DeviceID,Source,Notes
KRONOS-CLOCK-01,True,10.10.40.25,KRONOS-CLOCK-01.domain.local,KRONOS-CLOCK-01,Clock-FrontDesk,00-11-22-33-44-55,SN12345,InTouch DX,Kronos/UKG,1.0,KRONOS-CLOCK-01,UKG Clock,1.3.6.1.4.1.999,DX-01,SNMP,
'@ | Set-Content -Path $tempCsv -Encoding UTF8

        try {
            $results = @(& $kronosInfoPath -InventoryPath $tempCsv -LookupBy MAC -LookupValue '00:11:22:33:44:55')
            $results.Count | Should -Be 1
            $results[0].HostName | Should -Be 'KRONOS-CLOCK-01'
            $results[0].MACAddress | Should -Be '00-11-22-33-44-55'
            $results[0].SerialNumber | Should -Be 'SN12345'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

