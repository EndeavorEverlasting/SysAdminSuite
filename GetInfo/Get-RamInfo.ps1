<#
.SYNOPSIS
    Collects detailed RAM (physical memory) information from one or more remote computers.

.DESCRIPTION
    Reads a host list, queries Win32_PhysicalMemory via CIM on each machine in
    parallel (throttled), and exports per-stick detail rows to a CSV.
    Offline and error conditions produce placeholder rows so every queried host
    always appears in the output.

.PARAMETER ListPath
    Path to a plain-text file containing one hostname per line.
    Default: C:\Temp\hostlist.txt

.PARAMETER OutputPath
    Destination CSV file.
    Default: C:\Temp\RamInfo.csv

.PARAMETER Throttle
    Maximum number of concurrent background jobs.
    Default: 15

.EXAMPLE
    .\Get-RamInfo.ps1 -ListPath .\hosts.txt -OutputPath .\RamInfo.csv
#>
param(
    [string]$ListPath   = 'C:\Temp\hostlist.txt',
    [string]$OutputPath = 'C:\Temp\RamInfo.csv',
    [int]$Throttle      = 15
)

if (-not (Test-Path -Path $ListPath)) {
    throw "List file not found: $ListPath"
}

$Computers = Get-Content -Path $ListPath |
    Where-Object { $_ -and $_.Trim() -ne '' } |
    ForEach-Object { $_.Trim() } |
    Sort-Object -Unique

if (-not $Computers) { throw "No hosts found in $ListPath." }

function Start-RamQueryJob {
    param([string]$Computer)

    Start-Job -Name "RAM_$Computer" -ScriptBlock {
        param($Computer)

        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        function Resolve-MemoryType {
            param([int]$Code)
            switch ($Code) {
                20 { 'DDR' }          21 { 'DDR2' }
                22 { 'DDR2 FB-DIMM' } 24 { 'DDR3' }
                26 { 'DDR4' }         27 { 'LPDDR' }
                28 { 'LPDDR2' }       29 { 'LPDDR3' }
                30 { 'LPDDR4' }       31 { 'Logical non-volatile device' }
                32 { 'HBM' }          33 { 'HBM2' }
                34 { 'DDR5' }
                default { "Unknown ($Code)" }
            }
        }

        function Resolve-FormFactor {
            param([int]$Code)
            switch ($Code) {
                0  { 'Unknown' }  1  { 'Other' }    2  { 'SIP' }
                3  { 'DIP' }      4  { 'ZIP' }       5  { 'SOJ' }
                6  { 'Proprietary' } 7  { 'SIMM' }   8  { 'DIMM' }
                9  { 'TSOP' }     10 { 'PGA' }       11 { 'RIMM' }
                12 { 'SODIMM' }   13 { 'SRIMM' }     14 { 'SMD' }
                15 { 'SSMP' }     16 { 'QFP' }       17 { 'TQFP' }
                18 { 'SOIC' }     19 { 'LCC' }       20 { 'PLCC' }
                21 { 'BGA' }      22 { 'FPBGA' }     23 { 'LGA' }
                default { "Unknown ($Code)" }
            }
        }

        if (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
            try {
                $sticks = Get-CimInstance -ClassName Win32_PhysicalMemory `
                    -ComputerName $Computer -ErrorAction Stop

                if (-not $sticks) {
                    # Reachable but no sticks reported
                    return [pscustomobject]@{
                        Timestamp            = $timestamp
                        HostName             = $Computer
                        DeviceLocator        = ''
                        BankLabel            = ''
                        Manufacturer         = ''
                        PartNumber           = ''
                        SerialNumber         = ''
                        CapacityGB           = ''
                        Speed                = ''
                        ConfiguredClockSpeed = ''
                        MemoryType           = ''
                        FormFactor           = ''
                        TotalWidth           = ''
                        DataWidth            = ''
                        ConfiguredVoltage    = ''
                        MinVoltage           = ''
                        MaxVoltage           = ''
                        InterleavePosition   = ''
                        InterleaveDataDepth  = ''
                        PositionInRow        = ''
                        Attributes           = ''
                        Status               = 'No Sticks Reported'
                        ErrorMessage         = ''
                    }
                }

                $sticks | ForEach-Object {
                    [pscustomobject]@{
                        Timestamp            = $timestamp
                        HostName             = $Computer
                        DeviceLocator        = $_.DeviceLocator
                        BankLabel            = $_.BankLabel
                        Manufacturer         = $_.Manufacturer
                        PartNumber           = $_.PartNumber
                        SerialNumber         = $_.SerialNumber
                        CapacityGB           = [math]::Round($_.Capacity / 1GB, 2)
                        Speed                = $_.Speed
                        ConfiguredClockSpeed = $_.ConfiguredClockSpeed
                        MemoryType           = Resolve-MemoryType $_.SMBIOSMemoryType
                        FormFactor           = Resolve-FormFactor $_.FormFactor
                        TotalWidth           = $_.TotalWidth
                        DataWidth            = $_.DataWidth
                        ConfiguredVoltage    = $_.ConfiguredVoltage
                        MinVoltage           = $_.MinVoltage
                        MaxVoltage           = $_.MaxVoltage
                        InterleavePosition   = $_.InterleavePosition
                        InterleaveDataDepth  = $_.InterleaveDataDepth
                        PositionInRow        = $_.PositionInRow
                        Attributes           = $_.Attributes
                        Status               = 'OK'
                        ErrorMessage         = ''
                    }
                }
            } catch {
                [pscustomobject]@{
                    Timestamp            = $timestamp
                    HostName             = $Computer
                    DeviceLocator        = ''
                    BankLabel            = ''
                    Manufacturer         = ''
                    PartNumber           = ''
                    SerialNumber         = ''
                    CapacityGB           = ''
                    Speed                = ''
                    ConfiguredClockSpeed = ''
                    MemoryType           = ''
                    FormFactor           = ''
                    TotalWidth           = ''
                    DataWidth            = ''
                    ConfiguredVoltage    = ''
                    MinVoltage           = ''
                    MaxVoltage           = ''
                    InterleavePosition   = ''
                    InterleaveDataDepth  = ''
                    PositionInRow        = ''
                    Attributes           = ''
                    Status               = 'Query Failed'
                    ErrorMessage         = $_.Exception.Message
                }
            }
        } else {
            [pscustomobject]@{
                Timestamp            = $timestamp
                HostName             = $Computer
                DeviceLocator        = ''
                BankLabel            = ''
                Manufacturer         = ''
                PartNumber           = ''
                SerialNumber         = ''
                CapacityGB           = ''
                Speed                = ''
                ConfiguredClockSpeed = ''
                MemoryType           = ''
                FormFactor           = ''
                TotalWidth           = ''
                DataWidth            = ''
                ConfiguredVoltage    = ''
                MinVoltage           = ''
                MaxVoltage           = ''
                InterleavePosition   = ''
                InterleaveDataDepth  = ''
                PositionInRow        = ''
                Attributes           = ''
                Status               = 'Offline'
                ErrorMessage         = ''
            }
        }
    } -ArgumentList $Computer
}

$jobs = @()
foreach ($c in $Computers) {
    $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
    while ($runningJobs.Count -ge $Throttle) {
        Wait-Job -Any $runningJobs | Out-Null
        $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
    }
    $jobs += Start-RamQueryJob -Computer $c
}

if ($jobs) { Wait-Job -Job $jobs | Out-Null }

$results = $jobs | Receive-Job

$dir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($dir)) {
    $dir = (Get-Location).Path
}
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

$results | Sort-Object HostName, DeviceLocator | Export-Csv -Path $OutputPath -NoTypeInformation

$jobs | Remove-Job -Force | Out-Null
Write-Host "Done. Output saved to $OutputPath" -ForegroundColor Green

