<# 
.SYNOPSIS
  Preflight permissions & connectivity checks before remote admin tasks.

.PARAMETER Computers
  One or more target computers to probe.

.PARAMETER PrintServers
  One or more print servers to validate (e.g., SWBPNSHPS01V).

.PARAMETER ADGroupsToModify
  One or more AD groups you intend to modify (add/remove members).

.PARAMETER TargetOU
  An OU you intend to add/move computers into. Default is gp_tse_allowwindows10printing.

.PARAMETER OutputPath
  Folder to write CSV/JSON reports (default C:\Temp).
#>

[CmdletBinding()]
param(
  [string[]]$Computers,
  [string[]]$PrintServers,
  [string[]]$ADGroupsToModify,
  [string]$TargetOU = "OU=gp_tse_allowwindows10printing,DC=nslijhs,DC=net",
  [string]$OutputPath = "C:\Temp"
)

begin {
  $ErrorActionPreference = 'Continue'
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
      $id.Groups.Translate([System.Security.Principal.NTAccount]) | ForEach-Object { $_.Value }
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
          $rules = $acl.Access | Where-Object { $_.IdentityReference -eq $sid -or $groups -contains $_.IdentityReference.Value }
          $hasWriteMembers = $rules | Where-Object { $_.ActiveDirectoryRights.ToString().Contains('WriteProperty') }
          $msg = if ($hasWriteMembers){ "Likely can modify members" } else { "No explicit 'Write members' ACE found" }
          Add-Result -Area 'AD / Rights' -Target $grp -Check 'Write members (hint)' -Result ($(if($hasWriteMembers){'Pass'}else{'Warn'})) -Detail $msg -ReferenceKey 'ADPrivGroups'
        } catch {
          Add-Result -Area 'AD / Rights' -Target $grp -Check 'Write members (hint)' -Result 'Info' -Detail "Could not evaluate ACL ($($_.Exception.Message))" -ReferenceKey 'ADPrivGroups'
        }
      }
    }
  }

  # === AD OU Placement Check ===
  if ($TargetOU) {
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
      try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $ouObj = Get-ADOrganizationalUnit -Identity $TargetOU -Properties nTSecurityDescriptor -ErrorAction Stop
        $acl   = $ouObj.nTSecurityDescriptor

        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $sid = $id.User
        $groups = Get-TokenGroups

        $rules = $acl.Access | Where-Object { $_.IdentityReference -in $groups -or $_.IdentityReference -eq $sid }
        $hasWrite = $rules | Where-Object { $_.ActiveDirectoryRights -match "CreateChild|WriteProperty" -and $_.AccessControlType -eq "Allow" }

        if ($hasWrite) {
          Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'Can add/move computer objects' -Result 'Pass' -Detail "Delegated rights detected for CreateChild/WriteProperty."
        } else {
          Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'Can add/move computer objects' -Result 'Warn' -Detail "No delegation found; requires elevated rights."
        }
      } catch {
        Add-Result -Area 'AD / Rights' -Target $TargetOU -Check 'Can add/move computer objects' -Result 'Fail' -Detail "Could not read OU: $($_.Exception.Message)"
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
  $script:Report | Sort-Object Area,Target,Check | Tee-Object -FilePath $csv | Out-Null
  $script:Report | ConvertTo-Json -Depth 4 | Set-Content -Path $json -Encoding UTF8
  $script:Report | Sort-Object Area,Target,Check | Format-Table -AutoSize
  Write-Host "`nSaved:`n  $csv`n  $json" -ForegroundColor Cyan
  Write-Host "Tip: If ADMIN$ or Public Desktop fail, check UAC remote restrictions and admin shares." -ForegroundColor Yellow
}
