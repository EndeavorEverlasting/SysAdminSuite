#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Start,
    [string]$End,
    [ValidateLength(1, 600)][string]$Observation,
    [ValidateLength(1, 80)][string]$DockType,
    [ValidateLength(1, 80)][string]$DockFirmwareVersion,
    [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Error 'WINDOWS_HOST_REQUIRED: run on the Windows workstation connected to the dock.' -ErrorAction Continue
    exit 1
}

try {
    Import-Module (Join-Path $PSScriptRoot 'SasDockIncident.psm1') -Force
    $now = [DateTimeOffset]::Now
    $window = Resolve-SasDockIncidentWindow -Start $Start -End $End -Now $now
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $localAppData) { throw 'Windows LocalApplicationData was unavailable.' }
    $evidenceRoot = Join-Path $localAppData 'SysAdminSuite\Evidence\Dock'
    $machineGuid = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $hostKey = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$machineGuid))).Replace('-', '')
    } finally { $hasher.Dispose() }

    $previous = $null
    if ($BaselinePath) {
        $previous = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
        if ($previous.Schema -ne 'sas-dock-incident/v1' -or $previous.HostKey -ne $hostKey -or -not $previous.Snapshot) {
            throw 'Use an earlier sas-dock-incident/v1 receipt captured on this same Windows installation.'
        }
    }

    $deviceClass = '^(Bluetooth|Display|Monitor|USB|USBDevice|Net|Firmware|UCM|Media)$'
    $dockName = 'Thunderbolt|USB4|UCSI|DisplayLink|Docking|ThinkPad.*Dock|USB.*Hub'
    $snapshotStart = [datetime]::UtcNow
    $hostInfo = Get-SasDockSnapshotSection {
        Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 10 -ErrorAction Stop |
            Select-Object Caption, Version, BuildNumber, LastBootUpTime
    }
    $devices = Get-SasDockSnapshotSection {
        $present = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
            $_.Class -match $deviceClass -or $_.FriendlyName -match $dockName -or $_.InstanceId -like 'USB\VID_17E9*'
        })
        $parents = @{}
        if ($present.Count) {
            Get-PnpDeviceProperty -InstanceId @($present.InstanceId) -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue |
                ForEach-Object { $parents[$_.InstanceId] = $_.Data }
        }
        $present | Sort-Object InstanceId | ForEach-Object {
            [pscustomobject][ordered]@{
                Key = $_.InstanceId
                Class = $_.Class
                Name = $_.FriendlyName
                Status = $_.Status
                Problem = [string]$_.Problem
                Parent = $parents[$_.InstanceId]
            }
        }
    }
    $deviceIds = @{}
    foreach ($item in $devices.Items) { $deviceIds[$item.Key] = $true }
    $drivers = if ($devices.Status -eq 'READ') {
        Get-SasDockSnapshotSection {
            Get-CimInstance -ClassName Win32_PnPSignedDriver -OperationTimeoutSec 10 -ErrorAction Stop |
                Where-Object { $_.DeviceID -and $deviceIds.ContainsKey($_.DeviceID) } |
                Sort-Object DeviceID | Select-Object @{N='Key'; E={$_.DeviceID}}, DriverProviderName, DriverVersion,
                    @{N='DriverDate'; E={if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') }}}, InfName
        }
    } else {
        [pscustomobject]@{ Status = 'DEPENDENCY_UNAVAILABLE'; Items = @(); Detail = 'Present device inventory could not be read.' }
    }
    $services = Get-SasDockSnapshotSection {
        Get-CimInstance -ClassName Win32_Service -Filter "Name='bthserv' OR Name='BluetoothUserService' OR Name LIKE 'BluetoothUserService%'" -OperationTimeoutSec 10 -ErrorAction Stop |
            Sort-Object Name | Select-Object @{N='Key'; E={$_.Name}}, State, StartMode, ExitCode
    }
    $networkAdapters = Get-SasDockSnapshotSection {
        Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object HardwareInterface |
            Sort-Object InterfaceGuid | Select-Object @{N='Key'; E={[string]$_.InterfaceGuid}}, InterfaceDescription, Status, MediaConnectionState, LinkSpeed
    }
    $snapshot = [ordered]@{
        StartedUtc = $snapshotStart.ToString('o')
        EndedUtc = [datetime]::UtcNow.ToString('o')
        Windows = $hostInfo
        Devices = $devices
        Drivers = $drivers
        Services = $services
        NetworkAdapters = $networkAdapters
    }

    $systemProviders = 'Display|Dxg|nvlddmkm|amdkmdag|amdwddmg|igfx|USB|UCSI|Ucm|Thunderbolt|BTH|Bluetooth|PnP|DriverFrameworks|WindowsUpdateClient|Kernel-Power|Power-Troubleshooter|UserModePowerService|Service Control Manager|Lenovo|NDIS'
    $eventLogs = @(
        Get-SasDockEventEvidence -Channel System -Window $window -ProviderPattern $systemProviders
        Get-SasDockEventEvidence -Channel Application -Window $window -ProviderPattern 'Lenovo|DisplayLink|MsiInstaller'
        foreach ($channel in @(
            'Microsoft-Windows-Kernel-PnP/Configuration',
            'Microsoft-Windows-DriverFrameworks-UserMode/Operational',
            'Microsoft-Windows-DeviceSetupManager/Admin',
            'Microsoft-Windows-WindowsUpdateClient/Operational',
            'Microsoft-Windows-USB-USBHUB3/Operational',
            'Microsoft-Windows-DxgKrnl/Operational',
            'Microsoft-Windows-USB-USB4/Operational',
            'Microsoft-Windows-USB-USB4DeviceRouter-EventLogs/Operational',
            'Microsoft-Windows-USB-UCMUCSI-HidMini/Operational'
        )) { Get-SasDockEventEvidence -Channel $channel -Window $window })
    $setup = Get-SasDockSetupEvidence -Path (Join-Path $env:windir 'INF\setupapi.dev.log') -Window $window -Zone ([TimeZoneInfo]::Local)
    $receipt = [ordered]@{
        Schema = 'sas-dock-incident/v1'
        HostKey = $hostKey
        HostTimeZone = [TimeZoneInfo]::Local.Id
        EventWindow = [ordered]@{ StartUtc = $window.Start.ToString('o'); EndUtcExclusive = $window.End.ToString('o') }
        OperatorReport = [ordered]@{ Observation = $Observation; DockType = $DockType; DockFirmwareVersion = $DockFirmwareVersion }
        Snapshot = $snapshot
        EventSources = @($eventLogs | Select-Object Channel, Status, Detail, Enabled, RetainedRecordCount, OldestRetainedUtc, @{N='Matches'; E={@($_.Events).Count}})
        Timeline = @($eventLogs | ForEach-Object Events | Sort-Object TimeUtc, Channel, RecordId)
        SetupApi = $setup
        Comparison = if ($previous) { [ordered]@{ BaselineSnapshotUtc = $previous.Snapshot.StartedUtc; Sections = @(Compare-SasDockSnapshot -Before $previous.Snapshot -After $snapshot) } } else { $null }
    }
    $incomplete = $eventLogs[0].Status -ne 'READ' -or
        @($eventLogs | Where-Object Status -in @('QUERY_FAILED', 'QUERY_PARTIAL', 'TRUNCATED')).Count -gt 0 -or
        $setup.Status -ne 'READ' -or
        @($hostInfo, $devices, $drivers, $services, $networkAdapters | Where-Object Status -ne 'READ').Count -gt 0
    $receipt['Status'] = if ($incomplete) { 'CAPTURE_PARTIAL' } else { 'CAPTURED' }
    $receiptPath = Write-SasDockIncidentReceipt -Root $evidenceRoot -Receipt $receipt
    Write-Output "$($receipt.Status): $receiptPath"
    exit ([int]$incomplete * 2)
} catch {
    Write-Error "CAPTURE_FAILED: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
