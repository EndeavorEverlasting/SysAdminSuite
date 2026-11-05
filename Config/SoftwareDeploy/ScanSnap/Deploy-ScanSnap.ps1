#Requires -Version 5.1
<#
.SYNOPSIS
  Deterministic ScanSnap stage + silent-install orchestrator (Admin Box control plane).

.DESCRIPTION
  Runs on the approved Admin Box control plane. Treats each listed computer as an
  independently classified remote target. ScanSnap owns package binding, target
  classification, and result presentation; the canonical SysAdminSuite SMB
  scheduled-task adapter owns staging, hash proof, SYSTEM execution, validation,
  result retrieval, and teardown.

  /WhatIf validates package + classifies targets without remote mutation.

.NOTES
  Reuses SysAdminSuite contracts:
  - EnvSetup/Deploy-Shortcuts.bat argument style (via Deploy-ScanSnap.cmd)
  - scripts/SasNorthwellNetworkAuthority.psm1 for protected-route classification
  - scripts/SasSoftwareDeploymentAdapter.psm1 for canonical SMB/SYSTEM deployment
  - exact post-install executable validation; no ScanSnap-specific transport engine
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
$deploymentAdapterModule = Join-Path $script:RepoRoot 'scripts\SasSoftwareDeploymentAdapter.psm1'
if (-not (Test-Path -LiteralPath $deploymentAdapterModule -PathType Leaf)) {
  throw "Canonical software deployment adapter not found: $deploymentAdapterModule"
}
Import-Module $deploymentAdapterModule -Force -ErrorAction Stop

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
  $candidate = if ($Name -match '\.' -or [string]::IsNullOrWhiteSpace($Suffix)) {
    $Name
  } else {
    ('{0}.{1}' -f $Name, $Suffix.TrimStart('.'))
  }
  try {
    $entry = [System.Net.Dns]::GetHostEntry($candidate)
    if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.HostName)) {
      return [string]$entry.HostName
    }
  } catch {
    # Access classification below owns the resolvability result.
  }
  return $candidate
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
    } elseif ($deploymentMode -in @('NORTHWELL_PROTECTED','NORTHWELL_VPN') -and -not (Test-SasDeploymentFqdn -ComputerName $resolved)) {
      $final = 'WHATIF_IDENTITY_UNBOUND'
      $detail = "Protected deployment requires one exact authorized FQDN; resolved='$resolved'."
    } else {
      $final = 'WHATIF_READY'
      $detail = "Canonical adapter ready: exact target=$resolved; package hash and admin-share preflight passed; no target mutation performed."
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
    if ($deploymentMode -in @('NORTHWELL_PROTECTED','NORTHWELL_VPN') -and -not (Test-SasDeploymentFqdn -ComputerName $resolved)) {
      throw "Protected deployment requires one exact authorized FQDN; resolved='$resolved'."
    }

    $issName = [IO.Path]::ChangeExtension([string]$manifest.InstallerFileName, '.iss')
    $issSrc = Join-Path $installersDir $issName
    if (-not (Test-Path -LiteralPath $issSrc -PathType Leaf)) {
      throw "Required InstallShield response file missing before canonical staging: $issSrc"
    }

    $installerArguments = @([regex]::Matches([string]$manifest.SilentArgs, '(?:"[^"]*"|\S+)') | ForEach-Object { [string]$_.Value })
    $validationChecks = @(
      [pscustomobject][ordered]@{
        id = 'scansnap-home-executable'
        type = 'FileExists'
        required = $true
        path = [string]$manifest.DetectValue
      }
    )
    $runId = 'software-install-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $safeTarget = ($resolved -replace '[^A-Za-z0-9._-]', '_')
    $adapterRunRoot = Join-Path $logRoot ("adapter_{0}_{1}" -f $safeTarget, $runId)
    New-Item -ItemType Directory -Path $adapterRunRoot -Force | Out-Null

    $adapter = Invoke-SasSmbScheduledTaskDeployment `
      -ComputerName $resolved `
      -InstallerPath $binding.InstallerPath `
      -ExpectedSourceSha256 $binding.ActualSha256 `
      -PackageName ([string]$manifest.ProductName) `
      -InstallerArguments $installerArguments `
      -SupportFilePaths @($issSrc) `
      -ValidationChecks $validationChecks `
      -RunId $runId `
      -LocalRunRoot $adapterRunRoot `
      -ResultTimeoutSeconds $MaxWaitSeconds `
      -InstallerTimeoutSeconds ([Math]::Max($MaxWaitSeconds, 600))

    $adapterEvidence = Join-Path $adapterRunRoot 'scansnap-adapter-result.json'
    $adapter | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $adapterEvidence -Encoding UTF8
    $evidence = $adapterEvidence
    $stageStatus = if ([bool]$adapter.hashes_verified) { 'STAGED_HASH_VERIFIED' } elseif ([bool]$adapter.target_mutation_performed) { 'STAGING_ATTEMPTED' } else { 'NOT_STAGED' }
    $taskCreate = if ([bool]$adapter.task.created) { 'CREATED' } elseif ([bool]$adapter.task.create_attempted) { 'FAILED' } else { 'NOT_ATTEMPTED' }
    $taskRun = if ([bool]$adapter.result_retrieval.succeeded) { 'COMPLETED' } elseif ([bool]$adapter.task.started) { 'STARTED_NO_RESULT' } elseif ([bool]$adapter.task.run_attempted) { 'FAILED' } else { 'NOT_ATTEMPTED' }
    $installerResult = if ($null -ne $adapter.execution.installer_exit_code) { "EXIT:$($adapter.execution.installer_exit_code)" } elseif ($adapter.error) { "ERROR:$($adapter.error)" } else { 'NOT_OBSERVED' }
    $detectStatus = if ([bool]$adapter.validation.before_payload_cleanup_succeeded -and [bool]$adapter.validation.after_payload_cleanup_succeeded) { 'DETECTED' } else { 'NOT_DETECTED' }

    $canonicalFinal = if ([string]$adapter.status -eq 'failed_before_staging') {
      'FAILED_BEFORE_STAGING'
    } else {
      Resolve-SasSmbDeploymentFinalizationStatus -Result $adapter
    }
    $final = if ($canonicalFinal -eq 'COMPLETED_VALIDATED_FINALIZED') { 'INSTALLATION_DETECTED' } else { $canonicalFinal }
    $cleanupVerified = (-not [bool]$adapter.cleanup.task_remaining -and -not [bool]$adapter.cleanup.run_root_remaining)
    $detail = if ($adapter.error) { [string]$adapter.error } else { "canonical_status=$($adapter.status); finalization=$canonicalFinal; cleanup_verified=$cleanupVerified" }
    Write-SsLog "Canonical adapter target=$resolved status=$($adapter.status) finalization=$canonicalFinal evidence=$adapterEvidence"

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
