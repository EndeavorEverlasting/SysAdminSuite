#Requires -Version 5.1
Set-StrictMode -Version 2.0

$script:SasFieldPlatformSchema = 'sas-field-platform/v1'
$script:SasDefaultRuntimeRoot = 'C:\SASAL'
$script:SasWabPrefix = if ($env:SAS_NETWORK_GUARD_PREFIX) { [string]$env:SAS_NETWORK_GUARD_PREFIX } else { 'NSLIJHS-WAB' }

function Test-SasLocalControllerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][scriptblock]$DriveTypeResolver
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^(?:\\\\|//)') { return $false }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
    if ($full -notmatch '^[A-Za-z]:\\') { return $false }

    $drive = $full.Substring(0,2).ToUpperInvariant()
    if ($null -eq $DriveTypeResolver) {
        $DriveTypeResolver = {
            param($DeviceId)
            $driveName = $DeviceId.TrimEnd(':')

            # A mapped FileSystem PSDrive exposes its network root without requiring CIM.
            try {
                $psDrive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction Stop
                if ($null -ne $psDrive -and
                    -not [string]::IsNullOrWhiteSpace([string]$psDrive.DisplayRoot) -and
                    [string]$psDrive.DisplayRoot -match '^(?:\\\\|//)') {
                    return 4
                }
            }
            catch { }

            # DriveInfo is local and normally available even when WMI/CIM is restricted.
            try {
                $driveInfo = New-Object IO.DriveInfo ($DeviceId + '\')
                switch ([string]$driveInfo.DriveType) {
                    'Fixed' { return 3 }
                    'Network' { return 4 }
                    default { return 0 }
                }
            }
            catch { }

            # CIM is a final corroborating source, not the sole locality authority.
            try {
                $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $DeviceId) -ErrorAction Stop
                return [int]$disk.DriveType
            }
            catch { return 0 }
        }
    }

    $driveType = 0
    try { $driveType = [int](& $DriveTypeResolver $drive) } catch { $driveType = 0 }
    # Fail closed: only a positively proven fixed local disk is controller/runtime authority.
    return ($driveType -eq 3)
}

function Test-SasControllerSurface {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-SasLocalControllerPath -Path $Root)) { return $false }
    foreach ($relative in @(
        'scripts\SasNetworkGuard.psm1',
        'scripts\Confirm-SasNorthwellNetwork.ps1',
        'scripts\SasPortableLauncher.ps1',
        'Run-AutoLogonOnsite.cmd'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) { return $false }
    }
    return $true
}

function Get-SasMachineStateCandidates {
    [CmdletBinding()]
    param()

    $items = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @(
        $env:SAS_MACHINE_STATE_ROOT,
        $(if ($env:ProgramData) { Join-Path $env:ProgramData 'SysAdminSuite' } else { $null }),
        $(if ($env:SystemDrive) { Join-Path $env:SystemDrive 'ProgramData\SysAdminSuite' } else { $null }),
        (Join-Path $script:SasDefaultRuntimeRoot '.state')
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        try { $full = [IO.Path]::GetFullPath([string]$candidate) } catch { continue }
        if (-not (Test-SasLocalControllerPath -Path $full)) { continue }
        if (-not $items.Contains($full)) { [void]$items.Add($full) }
    }
    return @($items)
}

function Get-SasMachineStateRoot {
    [CmdletBinding()]
    param([switch]$Create, [switch]$Required)

    foreach ($candidate in @(Get-SasMachineStateCandidates)) {
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        if ($Create) {
            try {
                New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
                return $candidate
            }
            catch { }
        }
    }
    if ($Required) { throw 'No writable machine-local SysAdminSuite state root is available.' }
    return $null
}

function Add-SasControllerCandidate {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List,
        [AllowNull()][string]$Path
    )
    if ([string]::IsNullOrWhiteSpace([string]$Path)) { return }
    try { $full = [IO.Path]::GetFullPath(([string]$Path).Trim()) } catch { return }
    if (-not (Test-SasLocalControllerPath -Path $full)) { return }
    if (-not $List.Contains($full)) { [void]$List.Add($full) }
}

function Find-SasControllerRootFromAncestor {
    [CmdletBinding()]
    param([AllowNull()][string]$StartPath)

    if ([string]::IsNullOrWhiteSpace($StartPath)) { return $null }
    try { $current = [IO.DirectoryInfo]([IO.Path]::GetFullPath($StartPath)) } catch { return $null }
    if (-not $current.Exists) { return $null }
    while ($null -ne $current) {
        if (Test-SasControllerSurface -Root $current.FullName) { return $current.FullName }
        $current = $current.Parent
    }
    return $null
}

function Resolve-SasControllerRoot {
    [CmdletBinding()]
    param([AllowNull()][string]$CallerRoot)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    Add-SasControllerCandidate -List $candidates -Path $env:SAS_RUNTIME_ROOT
    Add-SasControllerCandidate -List $candidates -Path $script:SasDefaultRuntimeRoot
    Add-SasControllerCandidate -List $candidates -Path $env:SAS_REPO_ROOT
    Add-SasControllerCandidate -List $candidates -Path $CallerRoot

    $ancestor = Find-SasControllerRootFromAncestor -StartPath (Get-Location).Path
    Add-SasControllerCandidate -List $candidates -Path $ancestor

    foreach ($stateRoot in @(Get-SasMachineStateCandidates)) {
        $cache = Join-Path $stateRoot 'repo-root.txt'
        if (-not (Test-Path -LiteralPath $cache -PathType Leaf)) { continue }
        try { Add-SasControllerCandidate -List $candidates -Path ((Get-Content -LiteralPath $cache -Raw).Trim()) } catch { }
    }

    foreach ($candidate in $candidates) {
        if (Test-SasControllerSurface -Root $candidate) { return $candidate }
    }
    throw 'No machine-local SysAdminSuite controller surface was found. Use a local checkout or prepare the canonical C:\SASAL runtime.'
}

function Save-SasControllerRootCache {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-SasControllerSurface -Root $Root)) { throw "Not a valid local controller surface: $Root" }
    try {
        $stateRoot = Get-SasMachineStateRoot -Create
        if ($null -eq $stateRoot) { return $null }
        $path = Join-Path $stateRoot 'repo-root.txt'
        Set-Content -LiteralPath $path -Value ([IO.Path]::GetFullPath($Root)) -Encoding ASCII -ErrorAction Stop
        return $path
    }
    catch {
        # Cache persistence is an optimization only. A read/execute-only ProgramData installation must
        # remain usable by other technicians when C:\SASAL or another valid controller is already found.
        return $null
    }
}

function Get-SasUsableConnectionProfiles {
    [CmdletBinding()]
    param([AllowNull()][object[]]$ConnectionProfiles)

    if (-not $PSBoundParameters.ContainsKey('ConnectionProfiles')) {
        try { $ConnectionProfiles = @(Get-NetConnectionProfile -ErrorAction Stop) } catch { return @() }
    }
    $usable = @('Subnet','LocalNetwork','Internet')
    return @($ConnectionProfiles | Where-Object {
        $null -ne $_ -and (
            ([string]$_.IPv4Connectivity -in $usable) -or
            ([string]$_.IPv6Connectivity -in $usable)
        )
    })
}

function Get-SasProtectedNetworkAuthority {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$RepoRoot,
        [AllowNull()][object[]]$ConnectionProfiles,
        [AllowNull()][string]$WifiSsid,
        [AllowNull()][scriptblock]$AddressResolver
    )

    $profilesArgs = @{}
    if ($PSBoundParameters.ContainsKey('ConnectionProfiles')) { $profilesArgs.ConnectionProfiles = $ConnectionProfiles }
    $profiles = @(Get-SasUsableConnectionProfiles @profilesArgs)

    foreach ($profile in $profiles) {
        $alias = [string]$profile.InterfaceAlias
        $name = [string]$profile.Name
        if ($alias -match '(?i)(wi-?fi|wireless|wlan)' -and
            -not [string]::IsNullOrWhiteSpace($name) -and
            $name.StartsWith($script:SasWabPrefix, [StringComparison]::Ordinal)) {
            return [pscustomobject][ordered]@{
                schema_version = $script:SasFieldPlatformSchema
                approved = $true
                authority = 'WAB_WIFI'
                interface_alias = $alias
                network_label = $name
                network_category = [string]$profile.NetworkCategory
                controller_runtime_scope = 'LOCAL_MACHINE_ONLY'
            }
        }
    }

    foreach ($profile in $profiles) {
        $alias = [string]$profile.InterfaceAlias
        if ([string]$profile.NetworkCategory -ne 'DomainAuthenticated') { continue }
        if ($alias -match '(?i)(wi-?fi|wireless|wlan)') { continue }

        $interfaceIndex = [int]$profile.InterfaceIndex
        $addresses = @()
        try {
            if ($null -ne $AddressResolver) { $addresses = @(& $AddressResolver $interfaceIndex) }
            else { $addresses = @(Get-NetIPAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue) }
        }
        catch { $addresses = @() }
        $validAddress = $false
        foreach ($address in $addresses) {
            $ip = if ($address -is [string]) { [string]$address } else { [string]$address.IPAddress }
            if (-not [string]::IsNullOrWhiteSpace($ip) -and $ip -notmatch '^127\.' -and $ip -notmatch '^169\.254\.') { $validAddress = $true; break }
        }
        if (-not $validAddress) { continue }

        $isVpn = $alias -match '(?i)(vpn|citrix|virtual|anyconnect|globalprotect|forti|pulse|zscaler|secure access)'
        return [pscustomobject][ordered]@{
            schema_version = $script:SasFieldPlatformSchema
            approved = $true
            authority = $(if ($isVpn) { 'DOMAIN_AUTHENTICATED_VPN' } else { 'DOMAIN_AUTHENTICATED_WIRED' })
            interface_alias = $alias
            network_label = [string]$profile.Name
            network_category = [string]$profile.NetworkCategory
            controller_runtime_scope = 'LOCAL_MACHINE_ONLY'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($WifiSsid) -and
        $WifiSsid.StartsWith($script:SasWabPrefix, [StringComparison]::Ordinal)) {
        return [pscustomobject][ordered]@{
            schema_version = $script:SasFieldPlatformSchema
            approved = $true
            authority = 'WAB_WIFI'
            interface_alias = 'unknown'
            network_label = $WifiSsid
            network_category = 'unknown'
            controller_runtime_scope = 'LOCAL_MACHINE_ONLY'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $guard = Join-Path $RepoRoot 'scripts\SasNetworkGuard.psm1'
        if (Test-Path -LiteralPath $guard -PathType Leaf) {
            try {
                Import-Module $guard -Force
                $ssid = if ($PSBoundParameters.ContainsKey('WifiSsid')) { $WifiSsid } else { Get-SasCurrentWifiSsid }
                if (Test-SasNorthwellWifiSsid -Ssid $ssid) {
                    return [pscustomobject][ordered]@{
                        schema_version=$script:SasFieldPlatformSchema; approved=$true; authority='WAB_WIFI';
                        interface_alias='unknown'; network_label=$ssid; network_category='unknown'; controller_runtime_scope='LOCAL_MACHINE_ONLY'
                    }
                }
                if (Test-SasNorthwellWiredEvidence -NetworkText (Get-SasLocalNetworkText)) {
                    return [pscustomobject][ordered]@{
                        schema_version=$script:SasFieldPlatformSchema; approved=$true; authority='CONFIGURED_PROTECTED_PATH';
                        interface_alias='unknown'; network_label='unknown'; network_category='unknown'; controller_runtime_scope='LOCAL_MACHINE_ONLY'
                    }
                }
            }
            catch { }
        }
    }

    return [pscustomobject][ordered]@{
        schema_version = $script:SasFieldPlatformSchema
        approved = $false
        authority = 'UNPROVEN'
        interface_alias = 'unknown'
        network_label = 'unknown'
        network_category = 'unknown'
        controller_runtime_scope = 'LOCAL_MACHINE_ONLY'
    }
}

function Assert-SasProtectedNetworkAuthority {
    [CmdletBinding()]
    param([AllowNull()][string]$RepoRoot)
    $authority = Get-SasProtectedNetworkAuthority -RepoRoot $RepoRoot
    if (-not [bool]$authority.approved) {
        throw 'No approved protected network authority is active. Use Northwell hardwire, NSLIJHS-WAB, or an authenticated DomainAuthenticated VPN path.'
    }
    return $authority
}

function Resolve-SasExecutionRuntimeRoot {
    [CmdletBinding()]
    param([AllowNull()][string]$ControllerRoot)

    foreach ($candidate in @($env:SAS_RUNTIME_ROOT,$script:SasDefaultRuntimeRoot,$ControllerRoot)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        try { $full = [IO.Path]::GetFullPath([string]$candidate) } catch { continue }
        if (-not (Test-SasLocalControllerPath -Path $full)) { continue }
        if (Test-SasControllerSurface -Root $full) { return $full }
    }
    throw 'No local controller runtime is available. SysAdminSuite will not execute from a UNC share, mapped network drive, or target machine path.'
}

Export-ModuleMember -Function Test-SasLocalControllerPath,Test-SasControllerSurface,Get-SasMachineStateCandidates,Get-SasMachineStateRoot,Resolve-SasControllerRoot,Save-SasControllerRootCache,Get-SasProtectedNetworkAuthority,Assert-SasProtectedNetworkAuthority,Resolve-SasExecutionRuntimeRoot
