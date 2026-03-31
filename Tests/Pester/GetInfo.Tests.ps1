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

    It 'Generates HTML report via ConvertTo-SuiteHtml' {
        $script:machineInfoContent | Should -Match 'ConvertTo-SuiteHtml'
    }

    It 'Keeps the ErrorMessage column in every output row shape' {
        $script:machineInfoContent | Should -Match 'Status\s*=\s*''OK''[\s\S]*?ErrorMessage\s*=\s*'''''
        $script:machineInfoContent | Should -Match 'Status\s*=\s*''Query Failed''[\s\S]*?ErrorMessage\s*=\s*\$errMsg'
        $script:machineInfoContent | Should -Match 'Status\s*=\s*''Offline''[\s\S]*?ErrorMessage\s*=\s*'''''
    }

    It 'Detects local machine to avoid remote WMI paths (local fallback)' {
        $script:machineInfoContent | Should -Match '\$isLocal'
        $script:machineInfoContent | Should -Match 'localhost'
        $script:machineInfoContent | Should -Match '127\.0\.0\.1'
    }

    It 'Skips Test-Connection for local targets' {
        $script:machineInfoContent | Should -Match 'if\s*\(\$isLocal\)\s*\{\s*\$true'
    }

    It 'Calls Get-WmiObject without -ComputerName for local targets' {
        # The local branch should call Get-WmiObject -Class Win32_BIOS without -ComputerName
        $script:machineInfoContent | Should -Match 'if\s*\(\$isLocal\)\s*\{[\s\S]*?Get-WmiObject\s+-Class\s+Win32_BIOS\s+-ErrorAction'
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

    It 'Exports DisplayNumber for Windows display identification' {
        $script:moduleContent | Should -Match 'DisplayNumber'
    }

    It 'Exports IsPrimary to identify the main display' {
        $script:moduleContent | Should -Match 'IsPrimary'
    }

    It 'Exports ScreenBounds for display position and size' {
        $script:moduleContent | Should -Match 'ScreenBounds'
    }

    It 'Exports DevicePath for adapter-to-monitor mapping' {
        $script:moduleContent | Should -Match 'DevicePath'
    }

    It 'Contains Get-DisplayDeviceMap helper for Win32 display enumeration' {
        $script:moduleContent | Should -Match 'function\s+Get-DisplayDeviceMap'
    }

    It 'Uses QueryDisplayConfig to resolve display numbers' {
        $script:moduleContent | Should -Match 'QueryDisplayConfig'
    }

    It 'Contains Reset-DisplayDeviceCache for flushing stale EDID data' {
        $script:moduleContent | Should -Match 'function\s+Reset-DisplayDeviceCache'
    }

    It 'Reset-DisplayDeviceCache requires elevation' {
        $script:moduleContent | Should -Match 'IsInRole.*Administrator'
    }

    It 'Reset-DisplayDeviceCache cycles DisplayLink adapters via pnputil' {
        $script:moduleContent | Should -Match 'pnputil\s+/disable-device'
        $script:moduleContent | Should -Match 'pnputil\s+/enable-device'
        $script:moduleContent | Should -Match 'pnputil\s+/scan-devices'
    }

    It 'Reset-DisplayDeviceCache has a SettleSeconds parameter' {
        $script:moduleContent | Should -Match '\$SettleSeconds'
    }

    It 'Contains Invoke-MonitorDiff for before/after analysis' {
        $script:moduleContent | Should -Match 'function\s+Invoke-MonitorDiff'
    }

    It 'Invoke-MonitorDiff accepts a BeforeSnapshot parameter' {
        $script:moduleContent | Should -Match '\$BeforeSnapshot'
    }

    It 'Invoke-MonitorDiff outputs Appeared, Disappeared, Changed, Unchanged statuses' {
        $script:moduleContent | Should -Match "'Disappeared'"
        $script:moduleContent | Should -Match "'Appeared'"
        $script:moduleContent | Should -Match "'Changed'"
        $script:moduleContent | Should -Match "'Unchanged'"
    }

    It 'Contains Export-MonitorInfoHtml for HTML report generation' {
        $script:moduleContent | Should -Match 'function\s+Export-MonitorInfoHtml'
    }

    It 'Export-MonitorInfoHtml accepts MonitorInfo, DiffResults, OutputPath, and Open parameters' {
        $script:moduleContent | Should -Match '\$MonitorInfo'
        $script:moduleContent | Should -Match '\$DiffResults'
        $script:moduleContent | Should -Match '\$OutputPath'
        $script:moduleContent | Should -Match '\[switch\]\$Open'
    }

    It 'Export-MonitorInfoHtml delegates to ConvertTo-SuiteHtml and uses badge/phantom CSS classes' {
        $script:moduleContent | Should -Match 'ConvertTo-SuiteHtml'
        $script:moduleContent | Should -Match 'phantom-row'
        $script:moduleContent | Should -Match 'badge primary'
    }

    It 'Export-MonitorInfoHtml only builds HTML fragments after the suite helper exists' {
        $script:moduleContent | Should -Match 'if\s*\(Test-Path -LiteralPath \$suiteHtmlHelper\)\s*\{[\s\S]*?\.\s+\$suiteHtmlHelper[\s\S]*?\$bodyFragments[\s\S]*?\$chips[\s\S]*?ConvertTo-SuiteHtml'
    }

    It 'Export-MonitorInfoHtml warns and skips generation when the suite helper is missing' {
        $script:moduleContent | Should -Match 'Write-Warning\s+"ConvertTo-SuiteHtml helper not found'
    }

    It 'Export-MonitorInfoHtml detects phantom monitors and dock adapters' {
        $script:moduleContent | Should -Match 'phantom'
        $script:moduleContent | Should -Match 'VID_17E9'
        $script:moduleContent | Should -Match 'Reset-DisplayDeviceCache'
    }

    It 'Export-MonitorInfoHtml includes a diff section when DiffResults are provided' {
        $script:moduleContent | Should -Match 'diffSection'
        $script:moduleContent | Should -Match 'diff-gone'
        $script:moduleContent | Should -Match 'diff-new'
        $script:moduleContent | Should -Match 'diff-changed'
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

    It 'Generates HTML report via ConvertTo-SuiteHtml' {
        $script:queueContent | Should -Match 'ConvertTo-SuiteHtml'
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

    It 'Generates HTML report via ConvertTo-SuiteHtml' {
        $script:kronosInfoContent | Should -Match 'ConvertTo-SuiteHtml'
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
            # DNS search-suffix or NRPT rules may duplicate the unresolvable target;
            # assert at least one result row and validate the first one.
            $results.Count | Should -BeGreaterOrEqual 1
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



Describe 'Get-WindowsKey.ps1 -- script-level checks' {
    BeforeAll {
        $windowsKeyPath = Join-Path $repoRoot 'GetInfo\Get-WindowsKey.ps1'
        $script:windowsKeyContent = Get-Content -Path $windowsKeyPath -Raw
    }

    It 'Script file exists' {
        (Join-Path $repoRoot 'GetInfo\Get-WindowsKey.ps1') | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repoRoot 'GetInfo\Get-WindowsKey.ps1'),
            [ref]$tokens, [ref]$errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Has a -Targets parameter defaulting to the local machine' {
        $script:windowsKeyContent | Should -Match '\$Targets'
        $script:windowsKeyContent | Should -Match '\$env:COMPUTERNAME'
    }

    It 'Has a -OutputPath parameter' {
        $script:windowsKeyContent | Should -Match '\$OutputPath'
    }

    It 'Uses WMI SoftwareLicensingService for key retrieval' {
        $script:windowsKeyContent | Should -Match 'SoftwareLicensingService'
        $script:windowsKeyContent | Should -Match 'Get-CimInstance'
    }

    It 'Falls back to registry OA3xOriginalProductKey' {
        $script:windowsKeyContent | Should -Match 'OA3xOriginalProductKey'
    }

    It 'Uses the OA3 registry fallback without an unused regPath alias' {
        $script:windowsKeyContent | Should -Match '\$regOA3\s*=\s*''HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion'''
        $script:windowsKeyContent | Should -Match 'Get-ItemProperty -Path \$regOA3 -Name ''OA3xOriginalProductKey'''
        $script:windowsKeyContent | Should -Not -Match '\$regPath\b'
    }

    It 'Does not query a DigitalProductId registry value before the OA3 fallback' {
        $script:windowsKeyContent | Should -Not -Match "-Name 'DigitalProductId'"
        $script:windowsKeyContent | Should -Not -Match 'Name\s+"DigitalProductId"'
    }

    It 'Reports the key source in output' {
        $script:windowsKeyContent | Should -Match 'KeySource'
    }

    It 'Includes all expected output columns' {
        foreach ($col in @('Timestamp','HostName','ProductKey','KeySource','Edition','Status','ErrorMessage')) {
            $script:windowsKeyContent | Should -Match $col -Because "column '$col' must appear in output"
        }
    }

    It 'Exports results to CSV' {
        $script:windowsKeyContent | Should -Match 'Export-Csv'
    }

    It 'Generates HTML report via ConvertTo-SuiteHtml' {
        $script:windowsKeyContent | Should -Match 'ConvertTo-SuiteHtml'
    }

    It 'Retrieves the local Windows key without errors' {
        $csvPath = Join-Path $env:TEMP 'WindowsKeyTest.csv'
        try {
            # Run the script; pipeline capture may include Format-Table artefacts
            # on cold sessions, so validate via the CSV which is always clean.
            $null = & (Join-Path $repoRoot 'GetInfo\Get-WindowsKey.ps1') -Targets $env:COMPUTERNAME -OutputPath $csvPath
            $csvPath | Should -Exist
            $rows = @(Import-Csv -LiteralPath $csvPath)
            $rows.Count | Should -BeGreaterOrEqual 1
            $rows[0].HostName | Should -Be $env:COMPUTERNAME
            $rows[0].Status | Should -BeIn @('OK','NoKey')
            $rows[0].PSObject.Properties.Name | Should -Contain 'ProductKey'
        }
        finally {
            if (Test-Path $csvPath) { Remove-Item $csvPath -Force -ErrorAction SilentlyContinue }
            $htmlPath = [IO.Path]::ChangeExtension($csvPath, '.html')
            if (Test-Path $htmlPath) { Remove-Item $htmlPath -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Get-RamInfo.ps1 -- script-level checks' {
    BeforeAll {
        $ramInfoPath = Join-Path $repoRoot 'GetInfo\Get-RamInfo.ps1'
        $script:ramInfoContent = Get-Content -Path $ramInfoPath -Raw
    }

    It 'Script file exists' {
        (Join-Path $repoRoot 'GetInfo\Get-RamInfo.ps1') | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repoRoot 'GetInfo\Get-RamInfo.ps1'),
            [ref]$tokens, [ref]$errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Has a -ListPath parameter' {
        $script:ramInfoContent | Should -Match '\$ListPath'
    }

    It 'Has a -OutputPath parameter' {
        $script:ramInfoContent | Should -Match '\$OutputPath'
    }

    It 'Has a -Throttle parameter' {
        $script:ramInfoContent | Should -Match '\$Throttle'
    }

    It 'Uses Start-Job for parallelism' {
        $script:ramInfoContent | Should -Match 'Start-Job'
    }

    It 'Queries Win32_PhysicalMemory via CIM' {
        $script:ramInfoContent | Should -Match 'Win32_PhysicalMemory'
        $script:ramInfoContent | Should -Match 'Get-CimInstance'
    }

    It 'Exports results to CSV' {
        $script:ramInfoContent | Should -Match 'Export-Csv'
    }

    It 'Generates HTML report via ConvertTo-SuiteHtml' {
        $script:ramInfoContent | Should -Match 'ConvertTo-SuiteHtml'
    }

    It 'Resolves human-readable MemoryType labels' {
        $script:ramInfoContent | Should -Match 'SMBIOSMemoryType'
        $script:ramInfoContent | Should -Match "'DDR4'"
        $script:ramInfoContent | Should -Match "'DDR5'"
    }

    It 'Resolves human-readable FormFactor labels' {
        $script:ramInfoContent | Should -Match "'DIMM'"
        $script:ramInfoContent | Should -Match "'SODIMM'"
    }

    It 'Captures CapacityGB as a rounded value' {
        $script:ramInfoContent | Should -Match 'CapacityGB'
        $script:ramInfoContent | Should -Match '\[math\]::Round'
    }

    It 'Includes all expected output columns' {
        $expectedColumns = @(
            'Timestamp', 'HostName', 'DeviceLocator', 'BankLabel',
            'Manufacturer', 'PartNumber', 'SerialNumber', 'CapacityGB',
            'Speed', 'ConfiguredClockSpeed', 'MemoryType', 'FormFactor',
            'TotalWidth', 'DataWidth', 'ConfiguredVoltage',
            'MinVoltage', 'MaxVoltage', 'InterleavePosition',
            'InterleaveDataDepth', 'PositionInRow', 'Attributes',
            'Status', 'ErrorMessage'
        )
        foreach ($col in $expectedColumns) {
            $script:ramInfoContent | Should -Match $col -Because "column '$col' must appear in all output rows"
        }
    }

    It 'Has an OK row shape with an empty ErrorMessage' {
        $script:ramInfoContent | Should -Match "Status\s*=\s*'OK'"
        $script:ramInfoContent | Should -Match "ErrorMessage\s*=\s*''"
    }

    It 'Has a Query Failed row shape that captures the exception message' {
        $script:ramInfoContent | Should -Match "Status\s*=\s*'Query Failed'"
        $script:ramInfoContent | Should -Match 'ErrorMessage\s*=\s*\$_\.Exception\.Message'
    }

    It 'Has an Offline row shape with an empty ErrorMessage' {
        $script:ramInfoContent | Should -Match "Status\s*=\s*'Offline'"
    }

    It 'Has a No Sticks Reported row shape for reachable hosts with no DIMMs' {
        $script:ramInfoContent | Should -Match "'No Sticks Reported'"
    }

    It 'Sorts output by HostName then DeviceLocator before exporting' {
        $script:ramInfoContent | Should -Match 'Sort-Object\s+HostName,?\s*DeviceLocator'
    }

    It 'Does not use the deprecated Get-WmiObject cmdlet' {
        $script:ramInfoContent | Should -Not -Match 'Get-WmiObject'
    }
}
