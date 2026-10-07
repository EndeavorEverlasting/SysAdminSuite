#Requires -Version 5.1
<#
.SYNOPSIS
  Deterministic ScanSnap stage + silent-install orchestrator (Admin Box control plane).

.DESCRIPTION
  Runs on Admin Box 1 (LPW003ASI173). Treats each listed computer as a remote target.
  Stages package to \\HOST\C$\SoftwareRepo\ScanSnap\, executes via schtasks as SYSTEM,
  polls remote result evidence, then evaluates DetectType/DetectValue.

  /WhatIf validates package + classifies targets without remote mutation.

.NOTES
  Reuses SysAdminSuite contracts:
  - EnvSetup/Deploy-Shortcuts.bat argument style (via Deploy-ScanSnap.cmd)
  - mapping NoWinRM schtasks/SYSTEM pattern
  - Config SoftwareRepo staging path convention
  - scripts/SasNorthwellNetworkAuthority.psm1 for mode classification (no ScanSnap-specific network stack)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string[]]$ComputerList,
  [string]$HostsFile,
  [string]$DnsSuffix = '',
  [string]$PackageRoot,
  [string]$ManifestPath,
  [int]$MaxWaitSeconds = 300,
  [int]$PollSeconds = 5,
  [switch]$WhatIfPreferenceOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Semantic WhatIf = no remote mutation. Do NOT set $WhatIfPreference — that would
# suppress local evidence writes (New-Item/Add-Content/Export-Csv).
$script:SsWhatIf = [bool]$WhatIfPreferenceOverride -or [bool]$WhatIfPreference
$WhatIfPreference = $false

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
  $PackageRoot = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
  $PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
if (-not $ManifestPath) {
  $ManifestPath = Join-Path $script:PackageRoot 'package.manifest.json'
}

# Repo root is two levels above Config/SoftwareDeploy/ScanSnap
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:PackageRoot))
$authorityModule = Join-Path $script:RepoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
if (-not (Test-Path -LiteralPath $authorityModule)) {
  throw "Northwell network authority module not found: $authorityModule"
}
Import-Module $authorityModule -Force -ErrorAction Stop

function Write-SsLog {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -LiteralPath $script:LogTxt -Value $line -Encoding UTF8
  Write-Host $line
}

function Resolve-SsDeploymentMode {
  param(
    [Parameter(Mandatory)]
    $Authority,
    [Parameter(Mandatory)]
    [string]$TargetHost
  )
  $route = [string]$Authority.Route
  if (-not [bool]$Authority.Allowed) {
    # Denied authority is never allowed to mutate. Preserve PTop only as a no-mutation WhatIf diagnostic.
    if ($script:SsWhatIf -and $TargetHost -match '(?i)^(CheexMcClappeth)(\.|$)') { return 'LAB_LOCAL' }
    return 'UNKNOWN_BLOCKED'
  }
  switch ($route) {
    'WAB_WIFI' { return 'NORTHWELL_PROTECTED' }
    'PROTECTED_NON_WIFI' { return 'NORTHWELL_PROTECTED' }
    'DOMAIN_AUTHENTICATED_NON_WIFI' { return 'NORTHWELL_VPN' }
    default { return 'UNKNOWN_BLOCKED' }
  }
}

function New-EvidenceRow {
  param(
    [string]$AdminHost,
    [string]$TargetHost,
    [string]$ResolvedName,
    [string]$NetworkRoute,
    [string]$DeploymentMode,
    [bool]$AuthorityAllowed,
    [string]$AccessClass,
    [string]$PackageSha256,
    [string]$StageStatus,
    [string]$TaskCreateStatus,
    [string]$TaskRunStatus,
    [string]$InstallerResult,
    [string]$DetectStatus,
    [string]$FinalClass,
    [string]$Detail,
    [string]$EvidencePath
  )
  [pscustomobject]@{
    Timestamp         = (Get-Date -Format 'o')
    AdminHost         = $AdminHost
    TargetHost        = $TargetHost
    ResolvedName      = $ResolvedName
    NetworkRoute      = $NetworkRoute
    DeploymentMode    = $DeploymentMode
    AuthorityAllowed  = [bool]$AuthorityAllowed
    AccessClass       = $AccessClass
    PackageSha256     = $PackageSha256
    StageStatus       = $StageStatus
    TaskCreateStatus  = $TaskCreateStatus
    TaskRunStatus     = $TaskRunStatus
    InstallerResult   = $InstallerResult
    DetectStatus      = $DetectStatus
    FinalClass        = $FinalClass
    Detail            = $Detail
    EvidencePath      = $EvidencePath
    WhatIf            = [bool]$script:SsWhatIf
  }
}

function Get-HostList {
  $names = New-Object System.Collections.Generic.List[string]
  if ($ComputerList) {
    foreach ($c in $ComputerList) {
      foreach ($part in ($c -split '[,;\s]+')) {
        if ($part -and $part.Trim()) { [void]$names.Add($part.Trim()) }
      }
    }
  }
  if ($HostsFile) {
    if (-not [System.IO.Path]::IsPathRooted($HostsFile) -and -not (Test-Path -LiteralPath $HostsFile)) {
      $candidate = Join-Path $script:PackageRoot $HostsFile
      if (Test-Path -LiteralPath $candidate) { $HostsFile = $candidate }
    }
    if (-not (Test-Path -LiteralPath $HostsFile)) {
      throw "Hosts file not found: $HostsFile"
    }
    Get-Content -LiteralPath $HostsFile | ForEach-Object {
      $line = $_.Trim()
      if (-not $line -or $line.StartsWith('#')) { return }
      [void]$names.Add($line)
    }
  }
  if ($names.Count -eq 0) {
    $defaultSmoke = Join-Path $script:PackageRoot 'hosts_smoke.txt'
    if (Test-Path -LiteralPath $defaultSmoke) {
      Get-Content -LiteralPath $defaultSmoke | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        [void]$names.Add($line)
      }
    }
  }
  if ($names.Count -eq 0) {
    throw 'No target hosts specified. Use -ComputerList, -HostsFile, or populate hosts_smoke.txt.'
  }
  # Guard: refuse stale cert host
  $stale = @($names | Where-Object { $_ -ieq 'LPW003ASI105' })
  if ($stale.Count -gt 0) {
    throw 'Stale host LPW003ASI105 is not allowed in this workflow. Use CheexMcClappeth for PTop certification.'
  }
  return @($names | Select-Object -Unique)
}

function Resolve-TargetName {
  param([string]$Name, [string]$Suffix)
  if ($Name -match '^\d+\.\d+\.\d+\.\d+$') { return $Name }
  if ($Name -match '\.') { return $Name }
  if ([string]::IsNullOrWhiteSpace($Suffix)) { return $Name }
  return ('{0}.{1}' -f $Name, $Suffix.TrimStart('.'))
}

function Resolve-SsAccessClassFromText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  if ($Text -match '(?i)cannot contact a domain controller|ERROR_NO_SUCH_DOMAIN|no logon servers|1355') {
    return 'AUTH_DC_UNAVAILABLE'
  }
  if ($Text -match '(?i)user name or password is incorrect|logon failure|1326|0x8007052e') {
    return 'LOGON_FAILURE'
  }
  if ($Text -match '(?i)Access is denied|Unauthorized|0x80070005|System error 5') {
    return 'ACCESS_DENIED'
  }
  if ($Text -match '(?i)network path was not found|network name cannot be found|cannot find path|The network location cannot be reached') {
    return 'UNREACHABLE'
  }
  return $null
}

function Test-TargetAccess {
  param([string]$ResolvedName)
  $share = "\\$ResolvedName\C$"
  $row = [ordered]@{
    ResolvedName = $ResolvedName
    SharePath    = $share
    AccessClass  = 'UNREACHABLE'
    Detail       = ''
  }

  try {
    $null = [System.Net.Dns]::GetHostAddresses($ResolvedName)
  } catch {
    $row.AccessClass = 'RESOLVE_FAILED'
    $row.Detail = $_.Exception.Message
    return [pscustomobject]$row
  }

  # Prefer cmd.exe dir: surfaces DC-unavailable vs bad-password more reliably than Test-Path.
  $dirText = (cmd.exe /c "dir `"$share`" 2>&1" | Out-String)
  if ($LASTEXITCODE -eq 0 -or $dirText -match '(?i)Directory of') {
    try {
      $null = Get-ChildItem -LiteralPath $share -ErrorAction Stop | Select-Object -First 1
      $row.AccessClass = 'ADMIN_SHARE_READY'
      $row.Detail = 'Admin share reachable'
      return [pscustomobject]$row
    } catch {
      # fall through to classifiers below using both texts
      $dirText = ("{0}`n{1}" -f $dirText, $_.Exception.Message)
    }
  }

  $class = Resolve-SsAccessClassFromText -Text $dirText
  if ($class) {
    $row.AccessClass = $class
    $row.Detail = ($dirText.Trim() -replace '\s+', ' ')
    return [pscustomobject]$row
  }

  try {
    $null = Get-ChildItem -LiteralPath $share -ErrorAction Stop | Select-Object -First 1
    $row.AccessClass = 'ADMIN_SHARE_READY'
    $row.Detail = 'Admin share reachable'
    return [pscustomobject]$row
  } catch {
    $msg = $_.Exception.Message
    $class = Resolve-SsAccessClassFromText -Text $msg
    if ($class) {
      $row.AccessClass = $class
      $row.Detail = $msg
      return [pscustomobject]$row
    }
    $netOut = cmd.exe /c "net view \\$ResolvedName 2>&1"
    $netText = if ($null -eq $netOut) { '' } else { ($netOut | Out-String) }
    $class = Resolve-SsAccessClassFromText -Text $netText
    if ($class) {
      $row.AccessClass = $class
      $row.Detail = ("ShareProbe={0}; NetView={1}" -f $msg, ($netText.Trim() -replace '\s+', ' '))
      return [pscustomobject]$row
    }
    $row.AccessClass = 'UNREACHABLE'
    $row.Detail = ("ShareProbe={0}; NetView={1}" -f $msg, ($netText.Trim() -replace '\s+', ' '))
  }
  return [pscustomobject]$row
}

function Read-PackageManifest {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Manifest not found: $Path"
  }
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $m = $raw | ConvertFrom-Json
  return $m
}

function Test-PackageBinding {
  param($Manifest, [string]$InstallersDir)
  $issues = New-Object System.Collections.Generic.List[string]
  $installerPath = $null
  $actualSha = ''

  if ([string]::IsNullOrWhiteSpace([string]$Manifest.InstallerFileName)) {
    [void]$issues.Add('InstallerFileName is empty')
  } else {
    $installerPath = Join-Path $InstallersDir $Manifest.InstallerFileName
    if (-not (Test-Path -LiteralPath $installerPath)) {
      [void]$issues.Add("Installer missing: $installerPath")
    } else {
      $hash = Get-FileHash -LiteralPath $installerPath -Algorithm SHA256
      $actualSha = $hash.Hash.ToUpperInvariant()
      if ([string]::IsNullOrWhiteSpace([string]$Manifest.Sha256)) {
        [void]$issues.Add('Sha256 is empty in manifest')
      } elseif ($actualSha -ne $Manifest.Sha256.ToUpperInvariant()) {
        [void]$issues.Add("SHA256 mismatch. manifest=$($Manifest.Sha256) actual=$actualSha")
      }
    }
  }

  if ([string]::IsNullOrWhiteSpace([string]$Manifest.Type)) {
    [void]$issues.Add('Type is empty')
  }
  if ([string]::IsNullOrWhiteSpace([string]$Manifest.SilentArgs)) {
    [void]$issues.Add('SilentArgs is empty - freeze from package evidence before live install')
  }
  if ([string]::IsNullOrWhiteSpace([string]$Manifest.DetectType) -or [string]::IsNullOrWhiteSpace([string]$Manifest.DetectValue)) {
    [void]$issues.Add('DetectType/DetectValue incomplete - required before declaring install success')
  }
  if ([string]$Manifest.SilentArgs -match '(?i)\.iss') {
    $responseName = [IO.Path]::ChangeExtension([string]$Manifest.InstallerFileName, '.iss')
    $responsePath = Join-Path $InstallersDir $responseName
    if (-not (Test-Path -LiteralPath $responsePath -PathType Leaf)) {
      [void]$issues.Add("Required InstallShield response file missing: $responseName")
    }
  }
  if (-not [bool]$Manifest.Bound) {
    [void]$issues.Add('Manifest Bound=false')
  }

  [pscustomobject]@{
    IsBound       = ($issues.Count -eq 0)
    Issues        = @($issues)
    InstallerPath = $installerPath
    ActualSha256  = $actualSha
  }
}

function Invoke-RobocopyStage {
  param(
    [string]$SourceDir,
    [string]$DestDir,
    [string[]]$Files
  )
  if (-not (Test-Path -LiteralPath $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
  }
  $args = @($SourceDir, $DestDir) + $Files + @('/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
  $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru
  # robocopy 0-7 = success family
  if ($p.ExitCode -ge 8) {
    throw "robocopy failed exit=$($p.ExitCode) src=$SourceDir dst=$DestDir"
  }
  return $p.ExitCode
}

function New-RemoteInstallRunner {
  param(
    [string]$RemoteRootUnc,
    [string]$LocalInstallerName,
    [string]$InstallerType,
    [string]$SilentArgs,
    [string]$DetectType,
    [string]$DetectValue,
    [string]$StageRelativeUnderC
  )

  $runnerLocalName = 'install-runner.ps1'
  $runnerUnc = Join-Path $RemoteRootUnc $runnerLocalName
  $resultName = 'install-result.json'

  $runner = @"
`$ErrorActionPreference = 'Stop'
`$outRoot = 'C:\ProgramData\SysAdminSuite\SoftwareDeploy\ScanSnap'
New-Item -ItemType Directory -Path `$outRoot -Force | Out-Null
`$resultPath = Join-Path `$outRoot '$resultName'
`$installer = Join-Path 'C:\$StageRelativeUnderC' '$LocalInstallerName'
`$installerDir = Split-Path -Parent `$installer
`$started = Get-Date
`$obj = [ordered]@{
  StartedUtc = `$started.ToUniversalTime().ToString('o')
  Installer = `$installer
  Type = '$InstallerType'
  SilentArgs = '$SilentArgs'
  ExitCode = `$null
  InstallerCompleted = `$false
  InstallerSucceeded = `$false
  DetectType = '$DetectType'
  DetectValue = '$DetectValue'
  Detected = `$false
  Error = ''
  FinishedUtc = `$null
}
try {
  if (-not (Test-Path -LiteralPath `$installer)) { throw "Installer not found: `$installer" }
  `$argLine = '$SilentArgs'
  if ('$InstallerType' -ieq 'msi') {
    `$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList (@('/i', `$installer) + (`$argLine -split '\s+' | Where-Object { `$_ })) -Wait -PassThru -NoNewWindow
  } else {
    # Split tokens so InstallShield switches like -s -f1".\file.iss" are separate argv entries.
    `$p = Start-Process -FilePath `$installer -ArgumentList (@(`$argLine -split '\s+' | Where-Object { `$_ })) -WorkingDirectory `$installerDir -Wait -PassThru -NoNewWindow
  }
  `$obj.ExitCode = `$p.ExitCode
  `$obj.InstallerCompleted = `$true
  `$obj.InstallerSucceeded = `$p.ExitCode -in @(0, 1641, 3010)
  `$detected = `$false
  if ('$DetectType' -ieq 'file') {
    `$detected = Test-Path -LiteralPath '$DetectValue'
  } elseif ('$DetectType' -ieq 'regkey') {
    `$detected = Test-Path -LiteralPath ('Registry::{0}' -f '$DetectValue'.Replace('HKLM\','HKEY_LOCAL_MACHINE\').Replace('HKLM:\\','HKEY_LOCAL_MACHINE\'))
    if (-not `$detected) { `$detected = Test-Path -LiteralPath '$DetectValue' }
  }
  `$obj.Detected = [bool]`$detected
} catch {
  `$obj.Error = `$_.Exception.Message
} finally {
  `$obj.FinishedUtc = (Get-Date).ToUniversalTime().ToString('o')
  (`$obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath `$resultPath -Encoding UTF8
}
"@

  Set-Content -LiteralPath $runnerUnc -Value $runner -Encoding UTF8
  return @{
    RunnerUnc   = $runnerUnc
    RunnerLocal = "C:\ProgramData\SysAdminSuite\SoftwareDeploy\ScanSnap\$runnerLocalName"
    ResultUnc   = (Join-Path $RemoteRootUnc $resultName)
    ResultLocal = "C:\ProgramData\SysAdminSuite\SoftwareDeploy\ScanSnap\$resultName"
  }
}

function Invoke-RemoteSchtaskInstall {
  param(
    [string]$ResolvedName,
    [string]$TaskName,
    [string]$RunnerLocalPath,
    [int]$MaxWaitSeconds,
    [int]$PollSeconds,
    [string]$ResultUnc
  )

  $createStatus = 'NOT_ATTEMPTED'
  $runStatus = 'NOT_ATTEMPTED'
  $installerResult = 'NOT_OBSERVED'
  $detectStatus = 'NOT_OBSERVED'
  $detail = ''

  if (Test-Path -LiteralPath $ResultUnc) {
    Remove-Item -LiteralPath $ResultUnc -Force -ErrorAction SilentlyContinue
  }

  $now = Get-Date
  $when = if ($now.Second -ge 50) { $now.AddMinutes(2) } else { $now.AddMinutes(1) }
  $stTime = $when.ToString('HH:mm')
  $stDate = $when.ToString('yyyy-MM-dd')
  $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RunnerLocalPath`""

  $create = & schtasks.exe /Create /S $ResolvedName /RU SYSTEM /SC ONCE /SD $stDate /ST $stTime /TN $TaskName /TR $tr /RL HIGHEST /F 2>&1
  if ($LASTEXITCODE -ne 0) {
    return @{
      TaskCreateStatus = 'FAILED'
      TaskRunStatus    = 'SKIPPED'
      InstallerResult  = 'NOT_OBSERVED'
      DetectStatus     = 'NOT_OBSERVED'
      Detail           = "schtasks /Create failed ($LASTEXITCODE): $create"
      ResultObject     = $null
    }
  }
  $createStatus = 'CREATED'

  $run = & schtasks.exe /Run /S $ResolvedName /TN $TaskName 2>&1
  if ($LASTEXITCODE -ne 0) {
    return @{
      TaskCreateStatus = $createStatus
      TaskRunStatus    = 'FAILED'
      InstallerResult  = 'NOT_OBSERVED'
      DetectStatus     = 'NOT_OBSERVED'
      Detail           = "schtasks /Run failed ($LASTEXITCODE): $run"
      ResultObject     = $null
    }
  }
  $runStatus = 'STARTED'

  $elapsed = 0
  $resultObj = $null
  while ($elapsed -lt $MaxWaitSeconds) {
    if (Test-Path -LiteralPath $ResultUnc) {
      try {
        $raw = Get-Content -LiteralPath $ResultUnc -Raw -Encoding UTF8
        $resultObj = $raw | ConvertFrom-Json
        if ($resultObj.FinishedUtc) { break }
      } catch {
        # partial write; keep polling
      }
    }
    Start-Sleep -Seconds $PollSeconds
    $elapsed += $PollSeconds
  }

  if (-not $resultObj -or -not $resultObj.FinishedUtc) {
    $detail = "Timed out after ${MaxWaitSeconds}s waiting for $ResultUnc"
    return @{
      TaskCreateStatus = $createStatus
      TaskRunStatus    = 'TIMEOUT'
      InstallerResult  = 'NOT_OBSERVED'
      DetectStatus     = 'NOT_OBSERVED'
      Detail           = $detail
      ResultObject     = $resultObj
    }
  }

  $runStatus = 'COMPLETED'
  if ($resultObj.InstallerCompleted) {
    $installerResult = "EXIT:$($resultObj.ExitCode)"
  } elseif ($resultObj.Error) {
    $installerResult = "ERROR:$($resultObj.Error)"
  }

  if ($resultObj.Detected) {
    $detectStatus = 'DETECTED'
  } else {
    $detectStatus = 'NOT_DETECTED'
  }

  & schtasks.exe /Delete /S $ResolvedName /TN $TaskName /F 2>&1 | Out-Null

  return @{
    TaskCreateStatus = $createStatus
    TaskRunStatus    = $runStatus
    InstallerResult  = $installerResult
    DetectStatus     = $detectStatus
    Detail           = $detail
    ResultObject     = $resultObj
  }
}

# --- main ---
$adminHost = $env:COMPUTERNAME
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logRoot = Join-Path $env:SystemDrive 'ScanSnapDeployLogs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$script:LogTxt = Join-Path $logRoot ("DeployScanSnap_{0}.txt" -f $stamp)
$script:LogCsv = Join-Path $logRoot ("DeployScanSnap_{0}.csv" -f $stamp)

Write-SsLog "Deployment started as $env:USERNAME from $adminHost | WhatIf=$($script:SsWhatIf)"
Write-SsLog "PackageRoot=$script:PackageRoot Manifest=$ManifestPath"

$manifest = Read-PackageManifest -Path $ManifestPath
$installersDir = Join-Path $script:PackageRoot 'installers'
$binding = Test-PackageBinding -Manifest $manifest -InstallersDir $installersDir

Write-SsLog ("Package bound={0} sha={1}" -f $binding.IsBound, $binding.ActualSha256)
foreach ($issue in $binding.Issues) {
  Write-SsLog "PACKAGE_ISSUE: $issue" 'WARN'
}

# Reuse repository Northwell authority — do not invent a ScanSnap-only network stack.
$script:NetworkAuthority = Get-SasNorthwellNetworkAuthority
Write-SsLog ("NetworkAuthority Allowed={0} Route={1} Evidence={2}" -f `
    $script:NetworkAuthority.Allowed, $script:NetworkAuthority.Route, $script:NetworkAuthority.Evidence)

$targets = Get-HostList
Write-SsLog ("Targets: {0}" -f ($targets -join ', '))

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
  $resolved = Resolve-TargetName -Name $target -Suffix $DnsSuffix
  $deploymentMode = Resolve-SsDeploymentMode -Authority $script:NetworkAuthority -TargetHost $target
  Write-SsLog "Processing target=$target resolved=$resolved mode=$deploymentMode route=$($script:NetworkAuthority.Route)"

  $stageStatus = 'NOT_ATTEMPTED'
  $taskCreate = 'NOT_ATTEMPTED'
  $taskRun = 'NOT_ATTEMPTED'
  $installerResult = 'NOT_OBSERVED'
  $detectStatus = 'NOT_OBSERVED'
  $final = 'DESIGNED'
  $detail = [string]$script:NetworkAuthority.Evidence
  $evidence = $script:LogCsv
  $accessClass = 'NOT_PROBED'

  # Field targets require an authorized Northwell/VPN route. Lab PTop may proceed as LAB_LOCAL.
  if ($deploymentMode -eq 'UNKNOWN_BLOCKED') {
    $final = 'UNKNOWN_BLOCKED'
    $detail = ("DeploymentMode=UNKNOWN_BLOCKED Route={0}; {1}" -f $script:NetworkAuthority.Route, $script:NetworkAuthority.Evidence)
    $results.Add((New-EvidenceRow -AdminHost $adminHost -TargetHost $target -ResolvedName $resolved `
        -NetworkRoute ([string]$script:NetworkAuthority.Route) -DeploymentMode $deploymentMode `
        -AuthorityAllowed ([bool]$script:NetworkAuthority.Allowed) `
        -AccessClass $accessClass -PackageSha256 $binding.ActualSha256 `
        -StageStatus $stageStatus -TaskCreateStatus $taskCreate -TaskRunStatus $taskRun `
        -InstallerResult $installerResult -DetectStatus $detectStatus -FinalClass $final `
        -Detail $detail -EvidencePath $evidence)) | Out-Null
    continue
  }

  $access = Test-TargetAccess -ResolvedName $resolved
  $accessClass = $access.AccessClass
  $detail = $access.Detail
  Write-SsLog ("AccessClass={0} detail={1}" -f $access.AccessClass, $access.Detail)

  if ($access.AccessClass -ne 'ADMIN_SHARE_READY') {
    $final = $access.AccessClass
    $results.Add((New-EvidenceRow -AdminHost $adminHost -TargetHost $target -ResolvedName $resolved `
        -NetworkRoute ([string]$script:NetworkAuthority.Route) -DeploymentMode $deploymentMode `
        -AuthorityAllowed ([bool]$script:NetworkAuthority.Allowed) `
        -AccessClass $access.AccessClass -PackageSha256 $binding.ActualSha256 `
        -StageStatus $stageStatus -TaskCreateStatus $taskCreate -TaskRunStatus $taskRun `
        -InstallerResult $installerResult -DetectStatus $detectStatus -FinalClass $final `
        -Detail $detail -EvidencePath $evidence)) | Out-Null
    continue
  }

  if ($script:SsWhatIf) {
    $stageStatus = 'WOULD_STAGE'
    $taskCreate = 'WOULD_CREATE_TASK'
    $taskRun = 'WOULD_RUN_TASK'
    $installerResult = 'WOULD_INSTALL'
    $detectStatus = 'WOULD_DETECT'
    if (-not $binding.IsBound) {
      $final = 'WHATIF_PACKAGE_UNBOUND'
      $detail = ($binding.Issues -join '; ')
    } else {
      $final = 'WHATIF_READY'
      $detail = "Would stage to \\$resolved\C$\$($manifest.RemoteStageRelativePath) and run task $($manifest.TaskName)"
    }
    $results.Add((New-EvidenceRow -AdminHost $adminHost -TargetHost $target -ResolvedName $resolved `
        -NetworkRoute ([string]$script:NetworkAuthority.Route) -DeploymentMode $deploymentMode `
        -AuthorityAllowed ([bool]$script:NetworkAuthority.Allowed) `
        -AccessClass $access.AccessClass -PackageSha256 $binding.ActualSha256 `
        -StageStatus $stageStatus -TaskCreateStatus $taskCreate -TaskRunStatus $taskRun `
        -InstallerResult $installerResult -DetectStatus $detectStatus -FinalClass $final `
        -Detail $detail -EvidencePath $evidence)) | Out-Null
    continue
  }

  # Live mutation requires full binding
  if (-not $binding.IsBound) {
    $final = 'PACKAGE_UNBOUND'
    $detail = ($binding.Issues -join '; ')
    $results.Add((New-EvidenceRow -AdminHost $adminHost -TargetHost $target -ResolvedName $resolved `
        -NetworkRoute ([string]$script:NetworkAuthority.Route) -DeploymentMode $deploymentMode `
        -AuthorityAllowed ([bool]$script:NetworkAuthority.Allowed) `
        -AccessClass $access.AccessClass -PackageSha256 $binding.ActualSha256 `
        -StageStatus $stageStatus -TaskCreateStatus $taskCreate -TaskRunStatus $taskRun `
        -InstallerResult $installerResult -DetectStatus $detectStatus -FinalClass $final `
        -Detail $detail -EvidencePath $evidence)) | Out-Null
    continue
  }

  try {
    $stageUnc = "\\$resolved\C$\$($manifest.RemoteStageRelativePath)"
    $progUnc = "\\$resolved\C$\$($manifest.RemoteProgramDataRelativePath)"
    New-Item -ItemType Directory -Path $progUnc -Force | Out-Null

    $stageFiles = New-Object System.Collections.Generic.List[string]
    [void]$stageFiles.Add($manifest.InstallerFileName)
    [void]$stageFiles.Add('package.manifest.json')
    # also place manifest beside installer in a staging bundle folder
    $bundle = Join-Path $env:TEMP ("ScanSnapStage_{0}" -f $stamp)
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    Copy-Item -LiteralPath $binding.InstallerPath -Destination (Join-Path $bundle $manifest.InstallerFileName) -Force
    Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $bundle 'package.manifest.json') -Force
    # InstallShield silent response sibling required when SilentArgs uses -f1".\*.iss"
    $issName = [IO.Path]::ChangeExtension([string]$manifest.InstallerFileName, '.iss')
    if (-not [string]::IsNullOrWhiteSpace($issName)) {
      $issSrc = Join-Path $installersDir $issName
      if (-not (Test-Path -LiteralPath $issSrc -PathType Leaf)) {
        throw "Required InstallShield response file missing before staging: $issSrc"
      }
      Copy-Item -LiteralPath $issSrc -Destination (Join-Path $bundle $issName) -Force
      [void]$stageFiles.Add($issName)
    }

    $rc = Invoke-RobocopyStage -SourceDir $bundle -DestDir $stageUnc -Files @($stageFiles)
    $stageStatus = "STAGED:rc=$rc"
    Write-SsLog "Staged to $stageUnc (rc=$rc)"

    $runnerInfo = New-RemoteInstallRunner -RemoteRootUnc $progUnc `
      -LocalInstallerName $manifest.InstallerFileName `
      -InstallerType $manifest.Type `
      -SilentArgs $manifest.SilentArgs `
      -DetectType $manifest.DetectType `
      -DetectValue $manifest.DetectValue `
      -StageRelativeUnderC ($manifest.RemoteStageRelativePath -replace '/', '\')

    $exec = Invoke-RemoteSchtaskInstall -ResolvedName $resolved -TaskName $manifest.TaskName `
      -RunnerLocalPath $runnerInfo.RunnerLocal -MaxWaitSeconds $MaxWaitSeconds `
      -PollSeconds $PollSeconds -ResultUnc $runnerInfo.ResultUnc

    $taskCreate = $exec.TaskCreateStatus
    $taskRun = $exec.TaskRunStatus
    $installerResult = $exec.InstallerResult
    $detectStatus = $exec.DetectStatus
    $detail = $exec.Detail
    $evidence = $runnerInfo.ResultUnc

    $installerSucceeded = [bool]($exec.ResultObject -and $exec.ResultObject.InstallerSucceeded)
    if ($installerSucceeded -and $detectStatus -eq 'DETECTED') {
      $final = 'INSTALLATION_DETECTED'
    } elseif ($taskRun -eq 'COMPLETED' -and -not $installerSucceeded) {
      $final = 'INSTALLER_FAILED'
    } elseif ($taskRun -eq 'COMPLETED' -and $detectStatus -eq 'NOT_DETECTED') {
      $final = 'INSTALLER_DONE_NOT_DETECTED'
    } elseif ($taskCreate -eq 'FAILED' -or $taskRun -eq 'FAILED') {
      $final = 'TASK_FAILED'
    } elseif ($taskRun -eq 'TIMEOUT') {
      $final = 'TASK_TIMEOUT'
    } else {
      $final = 'INCOMPLETE'
    }
  } catch {
    $final = 'ERROR'
    $detail = $_.Exception.Message
    Write-SsLog $detail 'ERROR'
  }

  $results.Add((New-EvidenceRow -AdminHost $adminHost -TargetHost $target -ResolvedName $resolved `
      -NetworkRoute ([string]$script:NetworkAuthority.Route) -DeploymentMode $deploymentMode `
      -AuthorityAllowed ([bool]$script:NetworkAuthority.Allowed) `
      -AccessClass $access.AccessClass -PackageSha256 $binding.ActualSha256 `
      -StageStatus $stageStatus -TaskCreateStatus $taskCreate -TaskRunStatus $taskRun `
      -InstallerResult $installerResult -DetectStatus $detectStatus -FinalClass $final `
      -Detail $detail -EvidencePath $evidence)) | Out-Null
}

$results | Export-Csv -Path $script:LogCsv -NoTypeInformation -Encoding UTF8
Write-SsLog "Wrote CSV evidence: $script:LogCsv"
Write-SsLog "Wrote text log: $script:LogTxt"

$results | Format-Table TargetHost, DeploymentMode, NetworkRoute, AccessClass, StageStatus, TaskCreateStatus, TaskRunStatus, DetectStatus, FinalClass -AutoSize | Out-String | Write-Host

# Exit codes: 0 all good/whatif classified; 2 package unbound blocking live; 3 access failures; 1 hard error mix
$failedAccess = @($results | Where-Object { $_.AccessClass -in @('RESOLVE_FAILED', 'UNREACHABLE', 'ACCESS_DENIED', 'AUTH_DC_UNAVAILABLE', 'LOGON_FAILURE') })
$blockedMode = @($results | Where-Object { $_.FinalClass -eq 'UNKNOWN_BLOCKED' })
$unbound = @($results | Where-Object { $_.FinalClass -in @('PACKAGE_UNBOUND', 'WHATIF_PACKAGE_UNBOUND') })
$installOk = @($results | Where-Object { $_.FinalClass -eq 'INSTALLATION_DETECTED' -or $_.FinalClass -eq 'WHATIF_READY' })

if (-not $script:SsWhatIf -and $unbound.Count -gt 0) { exit 2 }
if (($failedAccess.Count + $blockedMode.Count) -eq $results.Count -and $results.Count -gt 0) { exit 3 }
if (($results.Count -gt 0) -and ($installOk.Count -eq 0) -and -not $script:SsWhatIf) { exit 1 }
exit 0
