[CmdletBinding()]
param(
    [ValidateSet('None', 'Quick', 'Full')]
    [string]$HealthDepth = 'Quick',

    [ValidatePattern('^[A-Za-z]:\\?$')]
    [string]$BackupTarget,

    [string]$BackupVersion,
    [string]$OutputPath,
    [switch]$IncludeSerials,
    [switch]$DeepStorage,
    [string]$FixturePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-ToDriveRoot {
    param([Parameter(Mandatory)][string]$Drive)
    return ($Drive.Substring(0, 1).ToUpperInvariant() + ':')
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @()
    )

    $lines = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    [pscustomobject]@{
        exit_code = $code
        output = $lines
    }
}

function Measure-PathBytes {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $sum = (Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

function Write-Result {
    param([Parameter(Mandatory)]$Value)
    $json = $Value | ConvertTo-Json -Depth 12
    if ($OutputPath) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
    }
    $json
}

if ($FixturePath) {
    if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
        throw "Fixture not found: $FixturePath"
    }
    $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    Write-Result -Value $fixture
    exit 0
}

$isAdmin = Test-IsAdministrator
$systemDrive = Convert-ToDriveRoot -Drive $env:SystemDrive
$warnings = New-Object System.Collections.Generic.List[string]
$warnings.Add('Drive letters are locators, not identities. Confirm disk number, model, bus, size, filesystem, and label before any write operation.')
$warnings.Add('GPU AdapterRAM is intentionally omitted because Win32_VideoController can truncate or misreport dedicated VRAM.')
$warnings.Add('A registered Windows image is not a restore test. Preserve the source until restore or evacuation requirements are independently satisfied.')

$storageMappings = @()
foreach ($volume in (Get-Volume | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter)) {
    $drive = "$($volume.DriveLetter):"
    try {
        $partition = Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        $storageMappings += [pscustomobject]@{
            drive = $drive
            disk_number = $disk.Number
            disk_model = $disk.FriendlyName
            disk_serial = if ($IncludeSerials) { "$($disk.SerialNumber)".Trim() } else { $null }
            bus_type = "$($disk.BusType)"
            disk_size_bytes = [int64]$disk.Size
            partition_number = $partition.PartitionNumber
            partition_size_bytes = [int64]$partition.Size
            filesystem = "$($volume.FileSystem)"
            label = "$($volume.FileSystemLabel)"
            free_bytes = [int64]$volume.SizeRemaining
            volume_health = "$($volume.HealthStatus)"
        }
    }
    catch {
        $storageMappings += [pscustomobject]@{
            drive = $drive
            disk_number = $null
            disk_model = $null
            disk_serial = $null
            bus_type = $null
            disk_size_bytes = $null
            partition_number = $null
            partition_size_bytes = $null
            filesystem = "$($volume.FileSystem)"
            label = "$($volume.FileSystemLabel)"
            free_bytes = [int64]$volume.SizeRemaining
            volume_health = "$($volume.HealthStatus)"
        }
    }
}

$physicalDisks = @()
foreach ($disk in (Get-PhysicalDisk | Sort-Object DeviceId)) {
    $reliability = $null
    try { $reliability = $disk | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
    $physicalDisks += [pscustomobject]@{
        device_id = "$($disk.DeviceId)"
        model = "$($disk.FriendlyName)"
        serial = if ($IncludeSerials) { "$($disk.SerialNumber)".Trim() } else { $null }
        media_type = "$($disk.MediaType)"
        health_status = "$($disk.HealthStatus)"
        operational_status = @($disk.OperationalStatus | ForEach-Object { "$_" })
        size_bytes = [int64]$disk.Size
        reliability = if ($reliability) {
            [pscustomobject]@{
                temperature_c = $reliability.Temperature
                wear = $reliability.Wear
                power_on_hours = $reliability.PowerOnHours
                read_errors_total = $reliability.ReadErrorsTotal
                write_errors_total = $reliability.WriteErrorsTotal
                read_errors_uncorrected = $reliability.ReadErrorsUncorrected
                write_errors_uncorrected = $reliability.WriteErrorsUncorrected
            }
        } else { $null }
    }
}

$backup = [ordered]@{
    status = 'not_requested'
    target = $null
    versions = $null
    items = $null
    artifact = $null
}

if ($BackupTarget) {
    $target = Convert-ToDriveRoot -Drive $BackupTarget
    $backup.target = $target
    $targetVolume = $storageMappings | Where-Object { $_.drive -eq $target } | Select-Object -First 1
    if (-not $targetVolume) {
        $backup.status = 'target_not_mounted'
    }
    elseif (-not (Get-Command wbadmin.exe -ErrorAction SilentlyContinue)) {
        $backup.status = 'wbadmin_unavailable'
    }
    else {
        $versions = Invoke-NativeCapture -FilePath 'wbadmin.exe' -ArgumentList @('get', 'versions', "-backupTarget:$target")
        $backup.versions = $versions
        $backup.status = if ($versions.exit_code -eq 0) { 'catalog_observed' } else { 'catalog_query_failed' }
        if ($BackupVersion) {
            $backup.items = Invoke-NativeCapture -FilePath 'wbadmin.exe' -ArgumentList @('get', 'items', "-version:$BackupVersion", "-backupTarget:$target")
        }
        $imageRoot = "$target\WindowsImageBackup"
        if (Test-Path -LiteralPath $imageRoot -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $imageRoot -Force -File -Recurse -ErrorAction SilentlyContinue)
            $backup.artifact = [pscustomobject]@{
                path = $imageRoot
                exists = $true
                file_count = $files.Count
                total_bytes = [int64](($files | Measure-Object Length -Sum).Sum)
            }
        }
        else {
            $backup.artifact = [pscustomobject]@{ path = $imageRoot; exists = $false; file_count = 0; total_bytes = 0 }
        }
    }
}

$winre = if (Get-Command reagentc.exe -ErrorAction SilentlyContinue) {
    Invoke-NativeCapture -FilePath 'reagentc.exe' -ArgumentList @('/info')
} else { $null }

$health = [ordered]@{
    depth = $HealthDepth
    administrator = $isAdmin
    winre = $winre
    dism = $null
    chkdsk = $null
    sfc = $null
}

if ($HealthDepth -ne 'None') {
    if (-not $isAdmin) {
        $warnings.Add("Health depth '$HealthDepth' requested without elevation; DISM/SFC/CHKDSK checks were skipped.")
    }
    else {
        if ($HealthDepth -eq 'Quick') {
            $health.dism = Invoke-NativeCapture -FilePath 'DISM.exe' -ArgumentList @('/Online', '/Cleanup-Image', '/CheckHealth')
        }
        elseif ($HealthDepth -eq 'Full') {
            $warnings.Add('Full health checks can remain at one displayed percentage for a long time. A static DISM percentage alone does not prove a stall.')
            $health.chkdsk = Invoke-NativeCapture -FilePath 'chkdsk.exe' -ArgumentList @($systemDrive, '/scan')
            $health.dism = Invoke-NativeCapture -FilePath 'DISM.exe' -ArgumentList @('/Online', '/Cleanup-Image', '/ScanHealth')
            $health.sfc = Invoke-NativeCapture -FilePath 'sfc.exe' -ArgumentList @('/verifyonly')
        }
    }
}

$ramModules = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    [pscustomobject]@{
        slot = "$($_.DeviceLocator)"
        manufacturer = "$($_.Manufacturer)"
        part_number = "$($_.PartNumber)".Trim()
        capacity_bytes = [int64]$_.Capacity
        rated_speed_mts = $_.Speed
        configured_speed_mts = $_.ConfiguredClockSpeed
        configured_voltage_mv = $_.ConfiguredVoltage
    }
})

$systemProduct = Get-CimInstance Win32_ComputerSystemProduct | Select-Object -First 1
$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
$gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object {
    [pscustomobject]@{ name = "$($_.Name)"; driver_version = "$($_.DriverVersion)" }
})

$hardware = [pscustomobject]@{
    system = [pscustomobject]@{
        vendor = "$($systemProduct.Vendor)"
        model = "$($systemProduct.Name)"
        version = "$($systemProduct.Version)"
        bios_version = "$($bios.SMBIOSBIOSVersion)"
        bios_release_date = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToUniversalTime().ToString('o') } else { $null }
    }
    cpu = [pscustomobject]@{
        name = "$($cpu.Name)"
        cores = $cpu.NumberOfCores
        logical_processors = $cpu.NumberOfLogicalProcessors
    }
    memory = [pscustomobject]@{
        total_visible_bytes = [int64]$os.TotalVisibleMemorySize * 1KB
        free_physical_bytes = [int64]$os.FreePhysicalMemory * 1KB
        modules = $ramModules
    }
    gpu = $gpu
}

$storagePressure = [ordered]@{ status = if ($DeepStorage) { 'observed' } else { 'not_requested' }; paths = @() }
if ($DeepStorage) {
    $profile = $env:USERPROFILE
    $paths = @(
        'C:\Users', 'C:\Windows', 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData', 'C:\$Recycle.Bin',
        (Join-Path $profile 'Downloads'), (Join-Path $profile 'Desktop'), (Join-Path $profile 'Documents'),
        (Join-Path $profile 'AppData\Local\Temp'), (Join-Path $profile 'AppData\Local\Docker'), (Join-Path $profile '.cache')
    ) | Select-Object -Unique
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            $bytes = Measure-PathBytes -Path $path
            $storagePressure.paths += [pscustomobject]@{ path = $path; bytes = $bytes }
        }
    }
}

$result = [pscustomobject]@{
    schema_version = '1.0'
    captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    host = [pscustomobject]@{
        computer_name = $env:COMPUTERNAME
        system_drive = $systemDrive
        administrator = $isAdmin
    }
    storage = [pscustomobject]@{
        drive_mappings = $storageMappings
        physical_disks = $physicalDisks
        pressure = $storagePressure
    }
    backup = [pscustomobject]$backup
    windows_health = [pscustomobject]$health
    hardware = $hardware
    proof = [pscustomobject]@{
        destructive_actions_performed = $false
        serials_included = [bool]$IncludeSerials
        proof_ceiling = 'Observed local metadata and command results only; no backup restore, destructive cleanup, firmware validation, or hardware compatibility certification is performed.'
        warnings = @($warnings)
    }
}

Write-Result -Value $result
