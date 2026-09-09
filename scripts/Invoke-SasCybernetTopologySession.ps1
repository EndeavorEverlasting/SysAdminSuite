#Requires -Version 5.1
<#
.SYNOPSIS
  Run one Cybernet topology survey iteration: absorb evidence, recompute
  eligibility, and publish the next bounded probe plan.

.DESCRIPTION
  Safe to run repeatedly. The first run bootstraps the local session; every later
  run merges anything new, compares against the previous run, and rewrites the
  probe plan and operator handoff.

  This script performs no network activity and never classifies device hardware.

.PARAMETER Action
  Status  - default; bootstrap, absorb inbox/ingest, recompute, publish plan.
  Import  - merge one named bundle, then publish.
  Export  - publish and write a shareable bundle to outbox.

.EXAMPLE
  .\scripts\Invoke-SasCybernetTopologySession.ps1

.EXAMPLE
  .\scripts\Invoke-SasCybernetTopologySession.ps1 -Action Import -BundlePath C:\Temp\from-colleague.json
#>
[CmdletBinding()]
param(
  [ValidateSet('Status', 'Import', 'Export')]
  [string]$Action = 'Status',

  [string]$BundlePath,

  [string]$SessionRoot,

  [switch]$OpenResults,

  [datetime]$AsOf = (Get-Date).ToUniversalTime()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sessionModule = Join-Path $repoRoot 'scripts\SasCybernetTopologySession.psm1'
$eligibilityModule = Join-Path $repoRoot 'DeploymentTracker\CybernetTopology.Eligibility.psm1'

Import-Module -Name $sessionModule -Force
Import-Module -Name $eligibilityModule -Force

if ($Action -eq 'Import' -and [string]::IsNullOrWhiteSpace($BundlePath)) {
  Write-Error 'Import requires -BundlePath pointing at a shared bundle file.'
  exit 2
}
if ($Action -eq 'Import' -and -not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
  Write-Error "Bundle not found: $BundlePath"
  exit 2
}

$session = Initialize-SasCybernetTopologySession -RepoRoot $repoRoot -SessionRoot $SessionRoot -AsOf $AsOf
$paths = $session.Paths
# Run ids are second-precision, so two clicks inside the same second would otherwise
# share a run directory and overwrite each other's plan, summary, and handoff.
$baseRunId = New-SasCybernetTopologyRunId -AsOf $AsOf
$runId = $baseRunId
$runDir = Join-Path $paths.RunsDir $runId
$suffix = 1
while (Test-Path -LiteralPath $runDir) {
  $suffix++
  $runId = "{0}-{1:D2}" -f $baseRunId, $suffix
  $runDir = Join-Path $paths.RunsDir $runId
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$registry = Read-SasTopologyJsonFile -Path $paths.RegistryPath
$mergeLog = New-Object System.Collections.Generic.List[object]
$rejectedLog = New-Object System.Collections.Generic.List[object]

function Add-SasTopologyMerge {
  <#
    Merge one staged file. A file the technician named explicitly is allowed to fail
    the run; a file found by scanning is quarantined instead, so one bad drop can
    never brick every future click.
  #>
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][bool]$Archive,
    [Parameter(Mandatory)][bool]$QuarantineOnFailure
  )

  $name = Split-Path -Leaf $Path
  try {
    $result = Import-SasCybernetTopologyBundle -Registry $script:registry -Path $Path
  }
  catch {
    if (-not $QuarantineOnFailure) { throw }
    $reason = $_.Exception.Message
    [void]$script:rejectedLog.Add([pscustomobject]@{ source = $name; reason = $reason })
    $quarantine = Join-Path $paths.RejectedDir ("{0}__{1}" -f $runId, $name)
    Move-Item -LiteralPath $Path -Destination $quarantine -Force
    Set-Content -LiteralPath ($quarantine + '.reason.txt') -Encoding UTF8 -Value $reason
    Write-Warning "Rejected $name and moved it to inbox\rejected. Reason: $reason"
    return
  }

  $script:registry = $result.Registry
  [void]$script:mergeLog.Add($result.Stats)
  if ($Archive) {
    $destination = Join-Path $paths.ArchiveDir ("{0}__{1}" -f $runId, $name)
    Move-Item -LiteralPath $Path -Destination $destination -Force
  }
}

# Explicit import first so a named bundle is never skipped, and fails loudly.
if ($Action -eq 'Import') {
  Add-SasTopologyMerge -Path $BundlePath -Archive:$false -QuarantineOnFailure:$false
}

# Bundles shared by other technicians.
foreach ($file in @(Get-ChildItem -LiteralPath $paths.InboxDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
  Add-SasTopologyMerge -Path $file.FullName -Archive:$true -QuarantineOnFailure:$true
}

# Locally produced probe evidence staged for this session.
foreach ($file in @(Get-ChildItem -LiteralPath $paths.IngestDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
  Add-SasTopologyMerge -Path $file.FullName -Archive:$true -QuarantineOnFailure:$true
}

$registry = Update-CybernetTopologyRegistryEligibility -Registry $registry -AsOf $AsOf
$registry.generated_at = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-SasTopologyJsonFile -Path $paths.RegistryPath -InputObject $registry

$plan = New-SasCybernetTopologyProbePlan -Registry $registry

$previousStatus = [ordered]@{}
$previousRunId = ''
if (Test-Path -LiteralPath $paths.StatePath) {
  $state = Read-SasTopologyJsonFile -Path $paths.StatePath
  if ($state.PSObject.Properties['last_run_id']) { $previousRunId = [string]$state.last_run_id }
  if ($state.PSObject.Properties['status_by_subnet_id'] -and $null -ne $state.status_by_subnet_id) {
    foreach ($prop in $state.status_by_subnet_id.PSObject.Properties) {
      $previousStatus[$prop.Name] = [string]$prop.Value
    }
  }
}

$hadPreviousRun = -not [string]::IsNullOrWhiteSpace($previousRunId)
$delta = Get-SasCybernetTopologyDelta `
  -PreviousStatusById $previousStatus `
  -CurrentStatusById $plan.StatusById `
  -HadPreviousRun:$hadPreviousRun

$planCsv = Join-Path $runDir 'next_probe_targets.csv'
$reviewCsv = Join-Path $runDir 'review_required.csv'
$summaryJson = Join-Path $runDir 'iteration_summary.json'
$handoffTxt = Join-Path $runDir 'operator_handoff.txt'

if ($plan.PlanRows.Count -gt 0) {
  $plan.PlanRows | Export-Csv -LiteralPath $planCsv -NoTypeInformation -Encoding UTF8
}
else {
  Set-Content -LiteralPath $planCsv -Encoding UTF8 -Value 'OrganizationId,SiteId,SubnetId,Cidr,DiscoveryProfile,AllowedPorts,Retries,BudgetDeclared,ReasonCodes'
}

if ($plan.ReviewRows.Count -gt 0) {
  $plan.ReviewRows | Export-Csv -LiteralPath $reviewCsv -NoTypeInformation -Encoding UTF8
}
else {
  Set-Content -LiteralPath $reviewCsv -Encoding UTF8 -Value 'OrganizationId,SiteId,SubnetId,Cidr,Status,BlockingReasonCodes,NextEvidenceNeeded'
}

$statusCounts = [ordered]@{}
foreach ($subnetId in $plan.StatusById.Keys) {
  $status = [string]$plan.StatusById[$subnetId]
  if (-not $statusCounts.Contains($status)) { $statusCounts[$status] = 0 }
  $statusCounts[$status] = [int]$statusCounts[$status] + 1
}

$bundlePathOut = ''
if ($Action -eq 'Export' -or $plan.StatusById.Keys.Count -gt 0) {
  $bundlePathOut = Join-Path $paths.OutboxDir ("cybernet-topology-evidence-{0}.json" -f $runId)
  Export-SasCybernetTopologyBundle -Registry $registry -Path $bundlePathOut -RunId $runId -AsOf $AsOf | Out-Null
}

$summary = [ordered]@{
  schema_version                     = 'sas-cybernet-topology-iteration-summary/v1'
  run_id                             = $runId
  generated_at                       = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
  action                             = $Action
  first_run                          = [bool]$session.FirstRun
  previous_run_id                    = $previousRunId
  network_activity_performed         = $false
  decides_device_identity            = $false
  sources_merged_this_run            = @($mergeLog.ToArray())
  sources_rejected_this_run          = @($rejectedLog.ToArray())
  subnets_total                      = $plan.StatusById.Keys.Count
  status_counts                      = $statusCounts
  eligible_probe_targets             = $plan.PlanRows.Count
  review_required_rows               = $plan.ReviewRows.Count
  newly_eligible_subnet_ids          = $delta.NewlyEligible
  no_longer_eligible_subnet_ids      = $delta.NoLongerEligible
  new_subnet_ids                     = $delta.NewSubnets
  status_changes                     = $delta.Changed
  probe_plan_path                    = $planCsv
  review_path                        = $reviewCsv
  shareable_bundle_path              = $bundlePathOut
  next_command                       = 'Run-CybernetTopologySurvey.cmd'
}
Write-SasTopologyJsonFile -Path $summaryJson -InputObject $summary

$handoff = New-Object System.Collections.Generic.List[string]
[void]$handoff.Add('SysAdminSuite - Cybernet Topology Survey Iteration')
[void]$handoff.Add('=================================================')
[void]$handoff.Add("Run id           : $runId")
[void]$handoff.Add("Action           : $Action")
if ($session.FirstRun) {
  [void]$handoff.Add('Session          : created on this run (first click)')
}
else {
  [void]$handoff.Add("Session          : reused; previous run $previousRunId")
}
[void]$handoff.Add('Network activity : none. This planner never probes and never identifies hardware.')
[void]$handoff.Add('')
[void]$handoff.Add('WHAT THIS RUN ABSORBED')
if ($mergeLog.Count -eq 0) {
  [void]$handoff.Add('  Nothing new. No bundles in inbox and no files in ingest.')
}
else {
  foreach ($entry in $mergeLog.ToArray()) {
    [void]$handoff.Add(("  {0}: +{1} sites, +{2} subnets, +{3} evidence, {4} evidence refreshed" -f `
          $entry.source, $entry.sites_added, $entry.subnets_added, $entry.evidence_added, $entry.evidence_updated))
  }
}
if ($rejectedLog.Count -gt 0) {
  [void]$handoff.Add('')
  [void]$handoff.Add('FILES REJECTED THIS RUN')
  foreach ($entry in $rejectedLog.ToArray()) {
    [void]$handoff.Add(("  {0}: {1}" -f $entry.source, $entry.reason))
  }
  [void]$handoff.Add("  Moved to $($paths.RejectedDir). Nothing else was affected; keep clicking as normal.")
}
[void]$handoff.Add('')
[void]$handoff.Add('WHAT CHANGED SINCE THE PREVIOUS RUN')
if (-not $delta.HasPreviousRun) {
  [void]$handoff.Add('  No previous run to compare against.')
}
elseif ($delta.Changed.Count -eq 0 -and $delta.NewSubnets.Count -eq 0) {
  [void]$handoff.Add('  No status changes. Adding new evidence is what moves these rows.')
}
else {
  foreach ($line in $delta.Changed) { [void]$handoff.Add("  changed: $line") }
  foreach ($line in $delta.NewSubnets) { [void]$handoff.Add("  new subnet: $line") }
}
[void]$handoff.Add('')
[void]$handoff.Add('SUBNETS APPROVED FOR A BOUNDED TARGETED PASS')
if ($plan.PlanRows.Count -eq 0) {
  [void]$handoff.Add('  None. No CIDR currently has enough deployment evidence.')
}
else {
  foreach ($row in $plan.PlanRows) {
    [void]$handoff.Add(("  {0}  profile={1}  ports={2}  retries={3}" -f $row.Cidr, $row.DiscoveryProfile, $row.AllowedPorts, $row.Retries))
  }
  [void]$handoff.Add('  This authorizes only the listed bounded profile. It is not a generic network scan.')
  $undeclaredBudget = @($plan.PlanRows | Where-Object { -not $_.BudgetDeclared })
  if ($undeclaredBudget.Count -gt 0) {
    [void]$handoff.Add('')
    [void]$handoff.Add('  BUDGET_NOT_DECLARED on the rows below. Blank does not mean unlimited.')
    [void]$handoff.Add('  Declare targeted_pass_budget for these CIDRs before probing them:')
    foreach ($row in $undeclaredBudget) {
      [void]$handoff.Add(("    {0} ({1})" -f $row.Cidr, $row.SubnetId))
    }
  }
}
[void]$handoff.Add('')
[void]$handoff.Add('BLOCKED ROWS AND THE EVIDENCE THAT WOULD UNBLOCK THEM')
if ($plan.ReviewRows.Count -eq 0) {
  [void]$handoff.Add('  None.')
}
else {
  foreach ($row in $plan.ReviewRows) {
    [void]$handoff.Add(("  {0} [{1}] -> {2}" -f $row.SubnetId, $row.Status, $row.NextEvidenceNeeded))
  }
}
[void]$handoff.Add('')
[void]$handoff.Add('FILES FROM THIS RUN')
[void]$handoff.Add("  Probe plan     : $planCsv")
[void]$handoff.Add("  Review queue   : $reviewCsv")
[void]$handoff.Add("  Run summary    : $summaryJson")
if ($bundlePathOut) {
  [void]$handoff.Add("  Share bundle   : $bundlePathOut")
}
[void]$handoff.Add('')
[void]$handoff.Add('HOW TO ADD MORE EVIDENCE BEFORE THE NEXT RUN')
[void]$handoff.Add("  Your own probe results : copy registry-shaped JSON into $($paths.IngestDir)")
[void]$handoff.Add("  A colleague's bundle   : copy their JSON into $($paths.InboxDir)")
[void]$handoff.Add('  Then run Run-CybernetTopologySurvey.cmd again. Both folders are absorbed automatically.')
[void]$handoff.Add('')
[void]$handoff.Add('HOW TO SHARE YOUR RESULTS')
if ($bundlePathOut) {
  [void]$handoff.Add("  Send the share bundle above. It carries site, CIDR, and evidence context.")
  [void]$handoff.Add('  Machine-local paths are replaced with operator-local-reference before export.')
}
else {
  [void]$handoff.Add('  Nothing to share yet. Add evidence first.')
}
[void]$handoff.Add('  Keep bundles in local ignored folders or approved internal channels. Never commit them.')
[void]$handoff.Add('')
[void]$handoff.Add('NEXT COMMAND')
[void]$handoff.Add('  Run-CybernetTopologySurvey.cmd')

Set-Content -LiteralPath $handoffTxt -Value ($handoff.ToArray() -join [Environment]::NewLine) -Encoding UTF8

$stateOut = [ordered]@{
  schema_version      = 'sas-cybernet-topology-session-state/v1'
  last_run_id         = $runId
  last_run_at         = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssZ')
  last_run_dir        = $runDir
  status_by_subnet_id = $plan.StatusById
}
Write-SasTopologyJsonFile -Path $paths.StatePath -InputObject $stateOut

Write-Host ''
Write-Host ($handoff.ToArray() -join [Environment]::NewLine)
Write-Host ''

if ($OpenResults) {
  try { Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$handoffTxt`"" | Out-Null } catch { Write-Verbose "Could not open handoff: $_" }
}

exit 0
