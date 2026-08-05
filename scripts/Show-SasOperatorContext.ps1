#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NextOnly)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$sessionModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
$autoLogonStateModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasAutoLogonOperatorState.psm1'
Import-Module $sessionModule -Force
if (Test-Path -LiteralPath $autoLogonStateModule -PathType Leaf) {
    Import-Module $autoLogonStateModule -Force
}

$network = Get-SasOperatorNetworkClassification -RepoRoot $repoRoot
[void](Set-SasOperatorSessionValues -Values @{
    repo_root=$repoRoot
    repo_head=(Get-SasRepoHead -RepoRoot $repoRoot)
    current_network_classification=$network.classification
    current_network_label=$network.label
    current_terminal=(Get-SasTerminalLabel)
})
$session = Read-SasOperatorSession
$targetFilter = [string](Get-SasObjectPropertyValue $session 'resolved_target_fqdn' (
    Get-SasObjectPropertyValue $session 'target_fqdn' $null
))

if (Get-Command -Name Sync-SasAutoLogonOperatorState -ErrorAction SilentlyContinue) {
    $session = Sync-SasAutoLogonOperatorState -RepoRoot $repoRoot -Target $targetFilter
}
else {
    $session = Sync-SasOperatorSessionFromEvidence -RepoRoot $repoRoot -TargetFqdn $targetFilter
}

$nextNetwork = [string](Get-SasObjectPropertyValue $session 'next_required_network' 'UNKNOWN')
$nextCommand = [string](Get-SasObjectPropertyValue $session 'next_command' 'Run sas context and inspect local evidence.')
if ($NextOnly) {
    Write-Host "NEXT NETWORK: $nextNetwork" -ForegroundColor Cyan
    Write-Host "NEXT COMMAND: $nextCommand" -ForegroundColor Green
    exit 0
}

$targetLocked = [bool](Get-SasObjectPropertyValue $session 'target_locked' $false)
$profileProven = [bool](Get-SasObjectPropertyValue $session 'profile_eligibility_proven' $false)
$profileSource = [string](Get-SasObjectPropertyValue $session 'profile_eligibility_source' '')
$lastNetwork = [string](Get-SasObjectPropertyValue $session 'last_network_classification' 'UNKNOWN')
$lastNetworkLabel = [string](Get-SasObjectPropertyValue $session 'last_network_label' '')
$repoBranch = [string](Get-SasObjectPropertyValue $session 'repo_branch' 'unknown')
$requestedTarget = [string](Get-SasObjectPropertyValue $session 'requested_target' (
    Get-SasObjectPropertyValue $session 'target_input' ''
))
$requestedShort = [string](Get-SasObjectPropertyValue $session 'requested_target_short_name' '')
$resolvedTarget = [string](Get-SasObjectPropertyValue $session 'resolved_target_fqdn' (
    Get-SasObjectPropertyValue $session 'target_fqdn' ''
))
$resolvedAddresses = @((Get-SasObjectPropertyValue $session 'resolved_target_addresses' @()))
$historicalRecoveryStatus = [string](Get-SasObjectPropertyValue $session 'historical_recovery_status' 'UNKNOWN')
$historicalRecoveryClassification = [string](Get-SasObjectPropertyValue $session 'historical_recovery_classification' '')
$historicalRecoveryPath = [string](Get-SasObjectPropertyValue $session 'historical_recovery_result_path' '')
$deploymentStarted = [bool](Get-SasObjectPropertyValue $session 'autologon_deployment_started' $false)
$deploymentCompleted = [bool](Get-SasObjectPropertyValue $session 'autologon_deployment_completed' $false)
$cleanupOutstanding = [bool](Get-SasObjectPropertyValue $session 'cleanup_outstanding' $false)

Write-Host 'SYSADMINSUITE OPERATOR CONTEXT' -ForegroundColor Cyan
Write-Host "Repo: $($session.repo_root)"
Write-Host "Branch/ref: $repoBranch"
Write-Host "HEAD: $($session.repo_head)"
Write-Host "Network: $($session.current_network_classification) [$($session.current_network_label)]"
Write-Host "Previous network: $lastNetwork [$lastNetworkLabel]"
Write-Host "Terminal: $($session.current_terminal) (informational only)"
Write-Host "Target locked: $(if ($targetLocked) { 'YES' } else { 'NO/LEGACY' })"
Write-Host "Requested target: $requestedTarget"
if ($requestedShort) { Write-Host "Target short name: $requestedShort" }
Write-Host "Canonical target FQDN: $resolvedTarget"
if ($resolvedAddresses.Count -gt 0) { Write-Host "Resolved addresses: $($resolvedAddresses -join ', ')" }
Write-Host "Equipment profile: $($session.equipment_profile) | eligibility: $(if ($profileProven) { 'PROVEN' } else { 'LEGACY/UNKNOWN' })"
if ($profileSource) { Write-Host "Profile authority: $profileSource" }
Write-Host "Deployment lane: $($session.deployment_lane)"
Write-Host "Package set: $($session.package_set)"
Write-Host "AutoLogon expected: $($session.expected_autologon_state)"
Write-Host "Historical S4U recovery: $historicalRecoveryStatus $historicalRecoveryClassification"
if ($historicalRecoveryPath) { Write-Host "Historical recovery evidence: $historicalRecoveryPath" }
Write-Host "AutoLogon deployment started: $(if ($deploymentStarted) { 'YES' } else { 'NO' })"
Write-Host "AutoLogon deployment completed: $(if ($deploymentCompleted) { 'YES' } else { 'NO' })"
Write-Host "Latest run: $($session.latest_run_id)"
Write-Host "Latest status: $($session.latest_status)"
Write-Host "Latest phase: $($session.latest_phase)"
Write-Host "Latest checkpoint: $($session.latest_checkpoint)"
Write-Host "Target mutation performed: $(if ([bool](Get-SasObjectPropertyValue $session 'target_mutation_performed' $false)) { 'YES' } else { 'NO' })"
Write-Host "Cleanup outstanding: $(if ($cleanupOutstanding) { 'YES' } else { 'NO' })"
if (@($session.completed_package_ids).Count -gt 0) { Write-Host "Completed packages: $(@($session.completed_package_ids) -join ', ')" }
if ($session.evidence_path) { Write-Host "Evidence: $($session.evidence_path)" }
Write-Host ''
Write-Host "NEXT NETWORK: $nextNetwork" -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $nextCommand" -ForegroundColor Green
exit 0
