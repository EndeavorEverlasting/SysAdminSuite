#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NextOnly)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sessionModule = Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
Import-Module $sessionModule -Force

$network = Get-SasOperatorNetworkClassification -RepoRoot $repoRoot
[void](Set-SasOperatorSessionValues -Values @{
    repo_root=$repoRoot
    repo_head=(Get-SasRepoHead -RepoRoot $repoRoot)
    current_network_classification=$network.classification
    current_network_label=$network.label
})
$session = Read-SasOperatorSession
if ($session.target_fqdn) {
    $session = Sync-SasOperatorSessionFromEvidence -RepoRoot $repoRoot -TargetFqdn ([string]$session.target_fqdn)
}

if ($NextOnly) {
    Write-Host "NEXT NETWORK: $($session.next_required_network)" -ForegroundColor Cyan
    Write-Host "NEXT COMMAND: $($session.next_command)" -ForegroundColor Green
    exit 0
}

Write-Host 'SYSADMINSUITE OPERATOR CONTEXT' -ForegroundColor Cyan
Write-Host "Repo: $($session.repo_root)"
Write-Host "HEAD: $($session.repo_head)"
Write-Host "Network: $($session.current_network_classification) [$($session.current_network_label)]"
Write-Host "Target: $($session.target_input) -> $($session.target_fqdn)"
Write-Host "Equipment profile: $($session.equipment_profile)"
Write-Host "Deployment lane: $($session.deployment_lane)"
Write-Host "Package set: $($session.package_set)"
Write-Host "AutoLogon expected: $($session.expected_autologon_state)"
Write-Host "Imprivata: $($session.imprivata_disposition)"
Write-Host "Latest run: $($session.latest_run_id)"
Write-Host "Latest status: $($session.latest_status)"
Write-Host "Latest phase: $($session.latest_phase)"
Write-Host "Latest checkpoint: $($session.latest_checkpoint)"
Write-Host "Cleanup outstanding: $(if ([bool]$session.cleanup_outstanding) { 'YES' } else { 'NO' })"
if (@($session.completed_package_ids).Count -gt 0) { Write-Host "Completed packages: $(@($session.completed_package_ids) -join ', ')" }
if ($session.evidence_path) { Write-Host "Evidence: $($session.evidence_path)" }
Write-Host ''
Write-Host "NEXT NETWORK: $($session.next_required_network)" -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $($session.next_command)" -ForegroundColor Green
exit 0