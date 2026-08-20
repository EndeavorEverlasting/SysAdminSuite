#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statusPath = Join-Path $WorkDir 'MaterializationStatus.json'
$taskService = $null
$taskFolder = $null
$userTaskName = $null
$userStatusPath = $null

function ConvertFrom-SasPrinterConnectionKeyName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $trimmed = $Name.Trim()
    if ($trimmed -match '^,,([^,]+),(.+)$') {
        return ('\\{0}\{1}' -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }
    if ($trimmed -match '^\\\\[^\\]+\\[^\\]+$') {
        return $trimmed.ToLowerInvariant()
    }
    return $null
}

function Get-SasUserPrinterConnections {
    param([Parameter(Mandatory)][string]$Sid)

    $key = "Registry::HKEY_USERS\$Sid\Printers\Connections"
    if (-not (Test-Path -LiteralPath $key)) { return @() }

    $connections = New-Object System.Collections.Generic.List[string]
    foreach ($subKey in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
        $candidate = ConvertFrom-SasPrinterConnectionKeyName -Name ([string]$subKey.PSChildName)
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $connections.Add($candidate)
        }
    }
    return @($connections.ToArray() | Sort-Object -Unique)
}

function Write-SasStatus {
    param([Parameter(Mandatory)]$Value)
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $queues = @(
        $config.Printers |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    if ($queues.Count -eq 0) { throw 'No printer queues were supplied for active-user materialization.' }
    foreach ($queue in $queues) {
        if ($queue -notmatch '^\\\\[^\\]+\\[^\\]+$') { throw "Unsafe/non-UNC queue reached active-user agent: $queue" }
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($identity -notmatch 'SYSTEM$') { throw "Active-user coordinator did not run as SYSTEM (identity: $identity)." }

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $activeUser = ([string]$computerSystem.UserName).Trim()
    if ([string]::IsNullOrWhiteSpace($activeUser)) {
        Write-SasStatus -Value ([ordered]@{
            Success = $true
            Identity = $identity
            ComputerName = $env:COMPUTERNAME
            ActiveUser = $null
            ActiveUserSid = $null
            Printers = $queues
            Materialized = $false
            PendingNextLogon = $true
            Disposition = 'MACHINE_WIDE_REGISTERED_PENDING_NEXT_LOGON'
            ProofLevel = 'MACHINE_WIDE_REGISTRATION_PENDING_LOGON'
            Finished = (Get-Date).ToString('o')
        })
        return
    }

    $account = New-Object System.Security.Principal.NTAccount($activeUser)
    $sidObject = $account.Translate([System.Security.Principal.SecurityIdentifier])
    $sid = $sidObject.Value

    $profileKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    $profile = [string](Get-ItemPropertyValue -LiteralPath $profileKey -Name ProfileImagePath -ErrorAction Stop)
    $profile = [Environment]::ExpandEnvironmentVariables($profile)
    $userTemp = Join-Path $profile 'AppData\Local\Temp'
    if (-not (Test-Path -LiteralPath $userTemp -PathType Container)) { throw "Active user temp directory was not found: $userTemp" }

    $runToken = [guid]::NewGuid().ToString('N')
    $userAgentPath = Join-Path $WorkDir 'UserAgent.ps1'
    $userStatusPath = Join-Path $userTemp "SysAdminSuite-PrinterMaterialize-$runToken.json"
    Remove-Item -LiteralPath $userStatusPath -Force -ErrorAction SilentlyContinue

    $userAgentCode = @'
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$StatusPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-SasPrinterConnectionKeyName {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $trimmed = $Name.Trim()
    if ($trimmed -match '^,,([^,]+),(.+)$') {
        return ('\\{0}\{1}' -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }
    if ($trimmed -match '^\\\\[^\\]+\\[^\\]+$') { return $trimmed.ToLowerInvariant() }
    return $null
}

function Get-SasCurrentUserPrinterConnections {
    $key = 'Registry::HKEY_CURRENT_USER\Printers\Connections'
    if (-not (Test-Path -LiteralPath $key)) { return @() }
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($subKey in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
        $candidate = ConvertFrom-SasPrinterConnectionKeyName -Name ([string]$subKey.PSChildName)
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $items.Add($candidate) }
    }
    return @($items.ToArray() | Sort-Object -Unique)
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $queues = @($config.Printers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    foreach ($queue in $queues) {
        if ($queue -notmatch '^\\\\[^\\]+\\[^\\]+$') { throw "Unsafe/non-UNC queue reached user materializer: $queue" }
        & "$env:SystemRoot\System32\rundll32.exe" 'printui.dll,PrintUIEntry' '/in' "/n$queue"
    }

    $deadline = (Get-Date).AddSeconds(30)
    do {
        $observed = @(Get-SasCurrentUserPrinterConnections)
        $missing = @($queues | Where-Object { $observed -notcontains $_ })
        if ($missing.Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    $success = ($missing.Count -eq 0)
    [ordered]@{
        Success = $success
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Requested = $queues
        UserConnections = $observed
        Missing = $missing
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatusPath -Encoding UTF8

    if (-not $success) { exit 7 }
    exit 0
}
catch {
    [ordered]@{
        Success = $false
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Error = $_.Exception.Message
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatusPath -Encoding UTF8
    exit 8
}
'@
    Set-Content -LiteralPath $userAgentPath -Value $userAgentCode -Encoding UTF8

    foreach ($readPath in @($userAgentPath, $ConfigPath)) {
        $acl = Get-Acl -LiteralPath $readPath -ErrorAction Stop
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $null = $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $readPath -AclObject $acl -ErrorAction Stop
    }

    $taskService = New-Object -ComObject 'Schedule.Service'
    $taskService.Connect()
    $taskFolder = $taskService.GetFolder('\')
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = 'SysAdminSuite immediate printer materialization for the active user.'
    $taskDefinition.Principal.UserId = $activeUser
    $taskDefinition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
    $taskDefinition.Principal.RunLevel = 0
    $taskDefinition.Settings.Enabled = $true
    $taskDefinition.Settings.Hidden = $true
    $taskDefinition.Settings.AllowDemandStart = $true
    $taskDefinition.Settings.ExecutionTimeLimit = 'PT2M'

    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ConfigPath "{1}" -StatusPath "{2}"' -f $userAgentPath, $ConfigPath, $userStatusPath

    $userTaskName = "SysAdminSuite_NorthwellPrinterUser_$runToken"
    $registeredTask = $taskFolder.RegisterTaskDefinition($userTaskName, $taskDefinition, 6, $activeUser, $null, 3, $null)
    $null = $registeredTask.Run($null)

    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Test-Path -LiteralPath $userStatusPath -PathType Leaf) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Path -LiteralPath $userStatusPath -PathType Leaf)) {
        throw "Interactive-token printer task did not produce user proof within 45 seconds for $activeUser."
    }

    $userStatus = Get-Content -LiteralPath $userStatusPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $hkuConnections = @(Get-SasUserPrinterConnections -Sid $sid)
    $missingFromHku = @($queues | Where-Object { $hkuConnections -notcontains $_ })
    $materialized = ([bool]$userStatus.Success -and $missingFromHku.Count -eq 0)

    Write-SasStatus -Value ([ordered]@{
        Success = $materialized
        Identity = $identity
        ComputerName = $env:COMPUTERNAME
        ActiveUser = $activeUser
        ActiveUserSid = $sid
        Printers = $queues
        Materialized = $materialized
        PendingNextLogon = $false
        UserTaskProof = $userStatus
        HkuUserConnections = $hkuConnections
        MissingFromHku = $missingFromHku
        Disposition = if ($materialized) { 'ACTIVE_USER_CONNECTION_VERIFIED' } else { 'ACTIVE_USER_CONNECTION_NOT_VERIFIED' }
        ProofLevel = if ($materialized) { 'MACHINE_WIDE_REGISTRATION_AND_ACTIVE_USER_CONNECTION' } else { 'ACTIVE_USER_CONNECTION_FAILED' }
        Finished = (Get-Date).ToString('o')
    })
}
catch {
    Write-SasStatus -Value ([ordered]@{
        Success = $false
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        ComputerName = $env:COMPUTERNAME
        Materialized = $false
        PendingNextLogon = $false
        Disposition = 'ACTIVE_USER_MATERIALIZATION_ERROR'
        Error = $_.Exception.Message
        Finished = (Get-Date).ToString('o')
    })
}
finally {
    if ($null -ne $taskFolder -and -not [string]::IsNullOrWhiteSpace($userTaskName)) {
        try { $taskFolder.DeleteTask($userTaskName, 0) } catch {}
    }
    if (-not [string]::IsNullOrWhiteSpace($userStatusPath)) {
        Remove-Item -LiteralPath $userStatusPath -Force -ErrorAction SilentlyContinue
    }
}
