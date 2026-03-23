function Get-NativeResolution {
    param([Parameter(Mandatory)][string]$InstanceName)

    try {
        $raw = (Get-CimInstance -Namespace root\wmi -Class WmiMonitorDescriptorMethods `
                -Filter "InstanceName='$InstanceName'" -ErrorAction Stop).GetMonitorDescriptor(0,0).Descriptor

        if ($raw.Count -lt 18) { return "Unknown" }

        $h = $raw[2] + ((($raw[4] -shr 4) -band 0xF) * 256)
        $v = $raw[5] + ((($raw[7] -shr 4) -band 0xF) * 256)

        if ($h -gt 0 -and $v -gt 0) {
            return "$h`x$v"
        } else { return "Unknown" }
    }
    catch { return "Unknown" }
}

function Get-ConnectionType {
    param([Parameter(Mandatory)][string]$InstanceName)

    $techMap = @{
        '-2'='UNINITIALIZED'; '-1'='OTHER'; '0'='VGA'; '1'='S-VIDEO'; '2'='COMPOSITE';
        '3'='COMPONENT'; '4'='DVI'; '5'='HDMI'; '10'='DISPLAYPORT'; '11'='DP (embedded)';
        '13'='eDP'; '16'='USB-C/Alt-DP'; '2147483648'='INTERNAL'
    }

    try {
        $conn = Get-CimInstance -Namespace root\wmi -Class WmiMonitorConnectionParams |
                Where-Object { $_.InstanceName -eq $InstanceName }

        if (-not $conn) { return "UNKNOWN" }

        $code = [string]$conn.VideoOutputTechnology
        $tech = $techMap[$code]
        if (-not $tech) { return "UNKNOWN" }

        if ($tech -eq 'DISPLAYPORT') {
            try {
                $locationInfo = (Get-CimInstance Win32_PnPEntity `
                               -Filter "DeviceID='$InstanceName'" -ErrorAction Stop).LocationInformation
                if ($locationInfo -match 'USB|TYPEC|TBT') { return 'USB-C (DP-Alt)' }
            } catch {}
        }
        return $tech
    }
    catch { return "UNKNOWN" }
}

function Get-MonitorInfo {
    [CmdletBinding()]
    param()

    $monitors = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID
    $desktopMonitors = Get-WmiObject Win32_DesktopMonitor
    $videoAdapters = Get-WmiObject Win32_VideoController

    $monitorData = @()

    foreach ($monitor in $monitors) {
        $instanceName = $monitor.InstanceName

        $modelBytes = $monitor.UserFriendlyName | Where-Object { $_ -ne 0 }
        $model = if ($modelBytes.Count -gt 0) { [System.Text.Encoding]::ASCII.GetString($modelBytes -as [byte[]]) } else { "Unknown" }

        $serialBytes = $monitor.SerialNumberID | Where-Object { $_ -ne 0 }
        $serial = if ($serialBytes.Count -gt 0) { [System.Text.Encoding]::ASCII.GetString($serialBytes -as [byte[]]) } else { "Unknown" }

        $manufacturerBytes = $monitor.ManufacturerName | Where-Object { $_ -ne 0 }
        $manufacturer = if ($manufacturerBytes.Count -gt 0) { [System.Text.Encoding]::ASCII.GetString($manufacturerBytes -as [byte[]]) } else { "Unknown" }

        $resolution = Get-NativeResolution -InstanceName $instanceName
        if ($resolution -eq "Unknown") {
            $desktopMonitor = $desktopMonitors | Where-Object { $_.PNPDeviceID -like "*$($instanceName.split('\')[0])*" }
            $resolution = if ($desktopMonitor) { "$($desktopMonitor.ScreenWidth)x$($desktopMonitor.ScreenHeight)" } else { "Unknown" }
        }

        $connectionType = Get-ConnectionType -InstanceName $instanceName

        $adapterName = "Unknown"
        foreach ($adapter in $videoAdapters) {
            if ($instanceName -like "*$($adapter.DeviceID)*" -or $model -like "*$($adapter.Name)*") {
                $adapterName = $adapter.Name
                break
            }
        }

        $monitorData += [PSCustomObject]@{
            Model         = $model
            Serial        = $serial
            Manufacturer  = $manufacturer
            Resolution    = $resolution
            Connection    = $connectionType
            Adapter       = $adapterName
        }
    }

    return $monitorData
}