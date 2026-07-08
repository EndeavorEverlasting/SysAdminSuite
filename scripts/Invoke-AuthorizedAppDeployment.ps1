<#
.SYNOPSIS
Manifest-driven authorized application deployment orchestrator.
.DESCRIPTION
Runs from an administrative orchestrator computer. Defaults to dry-run planning and requires
-Execute before any target mutation. Runtime evidence is written to output/deployments/<id>/.
The script never clears, deletes, mutates, or suppresses host/audit/security logs.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'output/deployments'),
  [string]$DeploymentId = ("deploy-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss')),
  [string]$SingleHost,
  [ValidateRange(1,10000)][int]$TargetLimit,
  [string[]]$AllowedShareRoot,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RequiredFields = @('TargetHostname','ApplicationName','NetworkSharePath','InstallerPath','ExpectedSha256','SilentInstallArguments','InstallDetectionMethod','Owner','RequestReference','ChangeReference','TicketReference')
$Script:DeploymentTempBase = 'C:\ProgramData\SysAdminSuite\DeploymentTemp'

function Test-SasSafeDeploymentCleanupPath {
  param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$DeploymentId)
  if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($DeploymentId)) { return $false }
  $normalized = $Path.Trim().TrimEnd('\')
  $expected = (Join-Path $Script:DeploymentTempBase $DeploymentId).TrimEnd('\')
  if ($normalized -in @('C:','C:\','\','/','.')) { return $false }
  if ($normalized -notlike "$($Script:DeploymentTempBase)*") { return $false }
  return ($normalized -eq $expected -or $normalized.StartsWith($expected + '\',[System.StringComparison]::OrdinalIgnoreCase))
}

function Get-SasManifestRows {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Manifest not found: $Path" }
  $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -eq '.json') {
    $raw = Get-Content -LiteralPath $Path -Raw
    $json = $raw | ConvertFrom-Json
    return @($json)
  }
  if ($ext -eq '.csv') { return @(Import-Csv -LiteralPath $Path) }
  throw "Unsupported manifest extension '$ext'. Use .csv or .json."
}

function Resolve-SasInstallerSourcePath {
  param($Row)
  if ([System.IO.Path]::IsPathRooted([string]$Row.InstallerPath)) { return [string]$Row.InstallerPath }
  return (Join-Path ([string]$Row.NetworkSharePath) ([string]$Row.InstallerPath))
}

function Test-SasManifestRows {
  param([object[]]$Rows,[string[]]$AllowedShareRoot)
  $errors = New-Object System.Collections.Generic.List[object]
  $rowNumber = 1
  foreach ($row in $Rows) {
    foreach ($field in $RequiredFields) {
      if (-not ($row.PSObject.Properties.Name -contains $field) -or [string]::IsNullOrWhiteSpace([string]$row.$field)) {
        $errors.Add([pscustomobject]@{ row = $rowNumber; field = $field; category = 'MissingRequiredField'; message = "Missing required field $field" })
      }
    }
    if ([string]$row.NetworkSharePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
      $errors.Add([pscustomobject]@{ row = $rowNumber; field = 'NetworkSharePath'; category = 'InvalidSharePath'; message = 'NetworkSharePath must be a UNC share path.' })
    }
    if ($AllowedShareRoot -and -not ($AllowedShareRoot | Where-Object { [string]$row.NetworkSharePath -like "$($_.TrimEnd('\'))*" })) {
      $errors.Add([pscustomobject]@{ row = $rowNumber; field = 'NetworkSharePath'; category = 'ShareRootNotAllowed'; message = 'NetworkSharePath is outside the configured allowlist.' })
    }
    if ([string]$row.ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
      $errors.Add([pscustomobject]@{ row = $rowNumber; field = 'ExpectedSha256'; category = 'InvalidSha256'; message = 'ExpectedSha256 must be a 64-character hex string.' })
    }
    if ([string]$row.TargetHostname -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
      $errors.Add([pscustomobject]@{ row = $rowNumber; field = 'TargetHostname'; category = 'InvalidTargetHostname'; message = 'TargetHostname must be a hostname, not an IP range or command.' })
    }
    $source = Resolve-SasInstallerSourcePath -Row $row
    if (-not (Test-Path -LiteralPath $source)) {
      $errors.Add([pscustomobject]@{ row = $rowNumber; field = 'InstallerPath'; category = 'InstallerNotFound'; message = "Installer not found at source path: $source" })
    }
    $rowNumber++
  }
  return @($errors)
}

function ConvertTo-SasBoolean {
  param($Value)
  if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $false }
  return ([string]$Value).Trim() -match '^(?i:true|1|yes)$'
}

function New-SasResultRecord {
  param($Row,[string]$Status,[string]$Category,[string]$Message)
  [ordered]@{
    DeploymentId = $DeploymentId; Hostname = [string]$Row.TargetHostname; Application = [string]$Row.ApplicationName; ManifestRow = [string]$Row.ManifestRow
    StartTime = (Get-Date).ToString('o'); EndTime = $null; NetworkSharePath = [string]$Row.NetworkSharePath; InstallerName = [System.IO.Path]::GetFileName([string]$Row.InstallerPath)
    ExpectedSha256 = [string]$Row.ExpectedSha256; ActualSha256 = $null; HashValidationStatus = 'NotChecked'; InstallAttempted = $false; InstallerExitCode = $null
    InstallResult = $Status; RebootRequired = (ConvertTo-SasBoolean -Value $Row.RebootRequired)
    CleanupAttempted = $false; CleanupResult = 'NotAttempted'; ErrorCategory = $Category; ErrorMessage = $Message; NextRecommendedAction = 'Review validation report and manifest/source path.'
  }
}

function Invoke-SasRemoteInstall {
  param($Row,[string]$TargetTempRoot)
  $source = Resolve-SasInstallerSourcePath -Row $Row
  $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne ([string]$Row.ExpectedSha256).ToLowerInvariant()) { throw "HASH_MISMATCH expected $($Row.ExpectedSha256) actual $actualHash" }
  if (-not (Test-SasSafeDeploymentCleanupPath -Path $TargetTempRoot -DeploymentId $DeploymentId)) { throw "Unsafe cleanup/staging root refused: $TargetTempRoot" }
  $session = New-PSSession -ComputerName ([string]$Row.TargetHostname)
  try {
    Invoke-Command -Session $session -ScriptBlock { param($p) New-Item -Path $p -ItemType Directory -Force | Out-Null } -ArgumentList $TargetTempRoot
    $targetInstaller = Join-Path $TargetTempRoot ([System.IO.Path]::GetFileName($source))
    Copy-Item -LiteralPath $source -Destination $targetInstaller -ToSession $session -Force
    $remote = Invoke-Command -Session $session -ScriptBlock {
      param($Installer,$Args,$TempRoot,$DeploymentId)
      $hash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
      $p = Start-Process -FilePath $Installer -ArgumentList $Args -Wait -PassThru
      $cleanup = 'NotAttempted'
      if ($TempRoot -like "C:\ProgramData\SysAdminSuite\DeploymentTemp\$DeploymentId*") {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
        $cleanup = 'Success'
      }
      [pscustomobject]@{ ActualSha256 = $hash; ExitCode = $p.ExitCode; CleanupResult = $cleanup }
    } -ArgumentList $targetInstaller,([string]$Row.SilentInstallArguments),$TargetTempRoot,$DeploymentId
    return $remote
  } finally {
    if ($session) { Remove-PSSession -Session $session }
  }
}

$runDir = Join-Path $OutputRoot $DeploymentId
$logsDir = Join-Path $runDir 'logs'
New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
$rows = Get-SasManifestRows -Path $ManifestPath
$i = 1; foreach ($r in $rows) { Add-Member -InputObject $r -NotePropertyName ManifestRow -NotePropertyValue $i -Force; $i++ }
if ($SingleHost) { $rows = @($rows | Where-Object { $_.TargetHostname -ieq $SingleHost }) }
if ($PSBoundParameters.ContainsKey('TargetLimit')) { $rows = @($rows | Select-Object -First $TargetLimit) }
$validationErrors = Test-SasManifestRows -Rows $rows -AllowedShareRoot $AllowedShareRoot
$validationReport = [ordered]@{ deploymentId = $DeploymentId; manifestPath = $ManifestPath; execute = [bool]$Execute; rowCount = @($rows).Count; errors = @($validationErrors) }
$validationReport | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $runDir 'validation-report.json') -Encoding UTF8
if ($validationErrors.Count -gt 0) { throw "Manifest validation failed. See $(Join-Path $runDir 'validation-report.json')" }

Write-Host "Deployment ID: $DeploymentId"
Write-Host ("Mode: {0}" -f ($(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })))
Write-Host "Manifest loaded: $ManifestPath"
Write-Host "Targets: $(@($rows | Select-Object -ExpandProperty TargetHostname -Unique).Count); Applications: $(@($rows | Select-Object -ExpandProperty ApplicationName -Unique).Count)"

$results = @()
foreach ($row in $rows) {
  $targetTempRoot = Join-Path $Script:DeploymentTempBase $DeploymentId
  $record = New-SasResultRecord -Row $row -Status ($(if ($Execute) { 'Pending' } else { 'DryRunValidated' })) -Category '' -Message ''
  try {
    $source = Resolve-SasInstallerSourcePath -Row $row
    $record.ActualSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $record.HashValidationStatus = ($(if ($record.ActualSha256 -eq $record.ExpectedSha256.ToLowerInvariant()) { 'Match' } else { 'Mismatch' }))
    if ($record.HashValidationStatus -ne 'Match') { throw "HASH_MISMATCH expected $($record.ExpectedSha256) actual $($record.ActualSha256)" }
    if ($Execute) {
      $record.InstallAttempted = $true; $record.CleanupAttempted = $true
      $remote = Invoke-SasRemoteInstall -Row $row -TargetTempRoot $targetTempRoot
      $record.InstallerExitCode = $remote.ExitCode; $record.CleanupResult = $remote.CleanupResult; $record.InstallResult = ($(if ($remote.ExitCode -eq 0) { 'Success' } elseif ($remote.ExitCode -eq 3010) { 'SuccessRebootRequired' } else { 'Failed' }))
    }
    Write-Host "$($row.TargetHostname) $($row.ApplicationName): $($record.InstallResult)"
  } catch {
    $record.ErrorCategory = ($(if ($_.Exception.Message -like 'HASH_MISMATCH*') { 'HashMismatch' } else { 'DeploymentError' }))
    $record.ErrorMessage = $_.Exception.Message; $record.InstallResult = 'Failed'; Write-Host "$($row.TargetHostname) $($row.ApplicationName): Failed"
  } finally { $record.EndTime = (Get-Date).ToString('o'); $results += [pscustomobject]$record }
}
$results | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $runDir 'deployment-results.json') -Encoding UTF8
$results | Export-Csv -Path (Join-Path $runDir 'deployment-results.csv') -NoTypeInformation
@("# Deployment Summary", "", "Deployment ID: $DeploymentId", "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })", "Results: deployment-results.json and deployment-results.csv", "Validation: validation-report.json") | Set-Content -Path (Join-Path $runDir 'deployment-summary.md') -Encoding UTF8
Write-Host "Output: $runDir"
