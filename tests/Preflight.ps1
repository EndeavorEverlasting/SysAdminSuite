<#
.SYNOPSIS
  Preflight permissions & connectivity checks before remote admin tasks.
  This is an ANALYSIS-ONLY tool. It does NOT move computers between OUs.

.PARAMETER Computers
  One or more target computers to probe.

.PARAMETER PrintServers
  One or more print servers to validate (e.g., SWBPNSHPS01V).

.PARAMETER ADGroupsToModify
  One or more AD groups you intend to modify (add/remove members).

.PARAMETER TargetOU
  An OU to ANALYZE for delegation/placement accuracy.
  This script verifies whether you have the correct rights and flags
  computers that may be in forbidden legacy OUs. It never moves objects.

.PARAMETER OutputPath
  Folder to write CSV/JSON reports (default C:\Temp).

.NOTES
  OU PLACEMENT POLICY  (Security / Alex Lent  2025-07-08)
  ────────────────────────────────────────────────────────
  FORBIDDEN (legacy, phased out since 2017):
    \_Workstations\Workstations\
    \_Workstations\Shared_Workstations\
  CORRECT placement:
    Normal laptops & desktops  -> subfolders of \_Workstations\Managed\
    Auto-logon / shared kiosks -> subfolders of \_Workstations\Managed_Shared\
#>

[CmdletBinding()]
param(
  [string[]]$Computers,
  [string[]]$PrintServers,
  [string[]]$ADGroupsToModify,
  [string]$TargetOU = "",
  [string]$OutputPath = "C:\Temp"
)

begin {
  $ErrorActionPreference = 'Continue'
  if ([string]::IsNullOrWhiteSpace($TargetOU)) {
    throw "TargetOU is required. Pass an environment-specific OU, e.g. -TargetOU 'OU=YourOU,DC=example,DC=com'."
  }
  if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

  # Reference links
  $Refs = @{
    PSRemoting   = "https://learn.microsoft.com/powershell/scripting/security/remoting/winrm-security"
    WSManCmd     = "https://learn.microsoft.com/powershell/module/microsoft.powershell.core/enable-psremoting"
    UACRemote    = "https://learn.microsoft.com/troubleshoot/windows-server/windows-security/user-account-control-and-remote-restriction"
    AdminShares  = "https://learn.microsoft.com/troubleshoot/windows-server/networking/problems-administrative-shares-missing"
    WMI_DCOM_FW  = "https://learn.microsoft.com/windows/win32/wmisdk/connecting-to-wmi-remotely-starting-with-vista"
    PortMatrix   = "https://learn.microsoft.com/troubleshoot/windows-server/networking/service-overview-and-network-port-requirements"
    AppLocker    = "https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/applocker/use-the-applocker-windows-powershell-cmdlets"
    PrintMgmt    = "https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/jj190062(v=ws.11)"
    ADPrivGroups = "https://learn.microsoft.com/windows-server/identity/ad-ds/plan/security-best-practices/appendix-b--privileged-accounts-and-groups-in-active-directory"
  }

  $script:Report = New-Object System.Collections.Generic.List[object]

  function Add-Result {
    param([string]$Area,[string]$Target,[string]$Check,[string]$Result,[string]$Detail,[string]$ReferenceKey)
    $script:Report.Add([pscustomobject]@{
      Timestamp = (Get-Date)
      Area      = $Area
      Target    = $Target
      Check     = $Check
      Result    = $Result
      Detail    = $Detail
      Reference = if ($ReferenceKey -and $Refs.ContainsKey($ReferenceKey)) { $Refs[$ReferenceKey] } else { $null }
    })
  }

  function Test-Port {
    param([string]$ComputerName,[int]$Port)
    try {
      $tnc = Test-NetConnection -ComputerName $ComputerName -Port $Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
      return $tnc.TcpTestSucceeded
    } catch { return $false }
  }

  function Test-PathRemote {
    param([string]$UNC)
    try { return Test-Path -Path $UNC -ErrorAction Stop }
    catch { return $false }
  }

  function Get-TokenGroups {
    try {
      $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
      $names = New-Object System.Collections.Generic.List[string]
      foreach ($g in $id.Groups) {
        try {
          $names.Add(($g.Translate([System.Security.Principal.NTAccount]).Value))
        } catch {
          continue
        }
      }
      $names
    } catch { @() }
  }
}

process {
  # Context + token groups check (same as before)...
  # -- SNIPPED for brevity --

  # === AD Group Membership Check (if provided) ===
  if ($ADGroupsToModify){
    if (Get-Module -ListAvailable -Name ActiveDirectory){
      Import-Module ActiveDirectory -ErrorAction SilentlyContinue
      foreach($grp in $ADGroupsToModify){
        try {
          $obj = Get-ADObject -Identity $grp -Properties nTSecurityDescriptor -ErrorAction Stop
          $acl = $obj.nTSecurityDescriptor
          $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
          $groups = Get-TokenGroups
          $sidValue = $sid.Value
          $rules = $acl.Access | Where-Object {
            $idRef = [string]$_.IdentityReference
            $idRef -eq $sidValue -or $groups -contains $idRef
          }
          $hasWriteMembers = $rules | Where-Object { $_.ActiveDirectoryRights.ToString().Contains('WriteProperty') }
          $msg = if ($hasWriteMembers){ "Likely can modify members" } else { "No explicit 'Write members' ACE found" }
          Add-Result -Area 'AD / Rights' -Target $grp -Check 'Write members (hint)' -Result ($(if($hasWriteMembers){'Pass'}else{'Warn'})) -Detail $msg -ReferenceKey 'ADPrivGroups'
        } catch {
          Add-Result -Area 'AD / Rights' -Target $grp -Check 'Write members (hint)' -Result 'Info' -Detail "Could not evaluate ACL ($($_.Exception.Message))" -ReferenceKey 'ADPrivGroups'
        }
      }
    } else {
      foreach($grp in $ADGroupsToModify){
        Add-Result -Area 'AD / Rights' -Target $grp -Check 'Write members (hint)' -Result 'Info' -Detail "ActiveDirectory module not available; skipping group checks" -ReferenceKey 'ADPrivGroups'
      }
    }
  }

  # === AD OU Placement Analysis (read-only -- never moves objects) ===
  # Forbidden legacy OUs per Security policy (2025-07-08)
  $ForbiddenOUPatterns = @(
    'OU=Workstations,OU=_Workstations'
    'OU=Shared_Workstations,OU=_Workstations'
  )

  if ($TargetOU) {
    # Check whether the target OU itself is a forbidden legacy OU
    foreach ($fp in $ForbiddenOUPatterns) {
      if ($TargetOU -match [regex]::Escape($fp)) {
        Add-Result -Area 'AD / OU Policy' -Target $TargetOU -Check 'Legacy OU check' -Result 'Fail' `
          -Detail "FORBIDDEN: This OU is a legacy path phased out since 2017. Use \_Workstations\Managed\ or \_Workstations\Managed_Shared\ subfolders instead."
      }
    }

    if (Get-Module -ListAvailable -Name ActiveDirectory) {
      try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $ouObj = Get-ADOrganizationalUnit -Identity $TargetOU -Properties nTSecurityDescriptor -ErrorAction Stop
        $acl   = $ouObj.nTSecurityDescriptor

        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $sid = $id.User
        $sidValue = $sid.Value
        $groups = Get-TokenGroups

        $rules = $acl.Access | Where-Object {
          $idRef = [string]$_.IdentityReference
          $idRef -in $groups -or $idRef -eq $sidValue
        }
        $hasWrite = $rules | Where-Object { $_.ActiveDirectoryRights -match "CreateChild|WriteProperty" -and $_.AccessControlType -eq "Allow" }

        if ($hasWrite) {
          Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'Delegation analysis (read-only)' -Result 'Pass' -Detail "Delegated rights detected for CreateChild/WriteProperty."
        } else {
          Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'Delegation analysis (read-only)' -Result 'Warn' -Detail "No delegation found; requires elevated rights."
        }
      } catch {
        Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'Delegation analysis (read-only)' -Result 'Fail' -Detail "Could not read OU: $($_.Exception.Message)"
      }
    } else {
      Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'AD Module' -Result 'Info' -Detail 'ActiveDirectory module not available'
    }
  }

  # === Per-computer and print server checks (same as before) ===
  # -- SNIPPED for brevity --
}

end {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $csv = Join-Path $OutputPath "Preflight_$stamp.csv"
  $json = Join-Path $OutputPath "Preflight_$stamp.json"
  $sorted = $script:Report | Sort-Object Area,Target,Check
  $sorted | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
  $script:Report | ConvertTo-Json -Depth 4 | Set-Content -Path $json -Encoding UTF8
  $sorted | Format-Table -AutoSize | Out-Host
  Write-Host "`nSaved:`n  $csv`n  $json" -ForegroundColor Cyan
  Write-Host "Tip: If ADMIN$ or Public Desktop fail, check UAC remote restrictions and admin shares." -ForegroundColor Yellow
}