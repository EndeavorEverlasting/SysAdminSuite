#Requires -Version 5.1
<#
.SYNOPSIS
Find the newest SysAdminSuite evidence without contacting a target.
.DESCRIPTION
Searches bounded SysAdminSuite checkouts, including machine-local field-ready worktrees. It never contacts
a Cybernet, software share, web endpoint, or other remote resource. A stable machine-local index survives
terminal closure and checkout refreshes.
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$stateRoot=Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$cachePath=Join-Path $stateRoot 'repo-root.txt'
$indexPath=Join-Path $stateRoot 'last-evidence.json'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

$kind='Latest'; $openLatest=$false; $maxItems=12
foreach ($argument in @($Arguments)) {
    if ([string]::IsNullOrWhiteSpace($argument)) { continue }
    switch ($argument.Trim().ToLowerInvariant()) {
        'latest' { $kind='Latest' }
        'all' { $kind='All' }
        'cybernet' { $kind='Cybernet' }
        'autologon' { $kind='AutoLogon' }
        'runtime' { $kind='Runtime' }
        'open' { $openLatest=$true }
        default {
            if ($argument -match '^\d+$') { $maxItems=[Math]::Max(1,[Math]::Min(50,[int]$argument)) }
            else { throw "Unknown evidence argument: $argument. Use Latest, All, Cybernet, AutoLogon, Runtime, Open, or a result count 1-50." }
        }
    }
}

function Add-SasUniquePath {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List,[AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full=[IO.Path]::GetFullPath($Path.Trim()) } catch { return }
    if (-not $List.Contains($full)) { [void]$List.Add($full) }
}
function Test-SasEvidenceRepoRoot {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return ((Test-Path -LiteralPath $Path -PathType Container) -and ((Test-Path -LiteralPath (Join-Path $Path 'survey\output') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Path 'bash\apps\output') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Path 'scripts\SasPortableLauncher.ps1') -PathType Leaf)))
}
function Get-SasJsonProperty {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $property=$Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

$repoCandidates=New-Object 'System.Collections.Generic.List[string]'
Add-SasUniquePath -List $repoCandidates -Path $repoRoot
Add-SasUniquePath -List $repoCandidates -Path $env:SAS_REPO_ROOT
if (Test-Path -LiteralPath $cachePath -PathType Leaf) { try { Add-SasUniquePath -List $repoCandidates -Path ((Get-Content -LiteralPath $cachePath -Raw).Trim()) } catch {} }
foreach ($fieldReady in @(Get-ChildItem -LiteralPath $stateRoot -Directory -Filter 'field-ready*' -ErrorAction SilentlyContinue)) { Add-SasUniquePath -List $repoCandidates -Path $fieldReady.FullName }
$profileRoots=@($env:USERPROFILE,$env:OneDrive,$env:OneDriveCommercial,$env:OneDriveConsumer) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$checkoutNames=@('SysAdminSuite','SysAdminSuite-portable-onsite','SysAdminSuite-Live')
foreach ($root in $profileRoots) {
    foreach ($name in $checkoutNames) {
        foreach ($relative in @($name,"dev\$name","Desktop\dev\$name","OG Laptop Backup\Desktop\dev\$name")) { Add-SasUniquePath -List $repoCandidates -Path (Join-Path $root $relative) }
    }
}
foreach ($pattern in @((Join-Path $env:USERPROFILE '*\Desktop\dev\SysAdminSuite*'),(Join-Path $env:USERPROFILE '*\*\Desktop\dev\SysAdminSuite*'),(Join-Path $env:USERPROFILE '*\*\*\Desktop\dev\SysAdminSuite*'))) {
    try { foreach ($match in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) { Add-SasUniquePath -List $repoCandidates -Path $match.FullName } } catch {}
}

$definitions=@(
    [pscustomobject]@{ category='Cybernet'; role='profiled clinical-core deployment'; relative_root='survey\output\runs\cybernet-profiled-clinical-core'; filter='cybernet_profiled_clinical_core_result.json' },
    [pscustomobject]@{ category='Cybernet'; role='profiled clinical-core recovery'; relative_root='survey\output\runs\cybernet-profiled-clinical-core-recovery'; filter='recovery-*.json' },
    [pscustomobject]@{ category='Cybernet'; role='clinical-core source preflight'; relative_root='survey\output\runs\cybernet-clinical-core-source-preflight'; filter='cybernet_clinical_core_source_preflight.json' },
    [pscustomobject]@{ category='Cybernet'; role='one-target deployment readiness'; relative_root='survey\output\runs\cybernet-deployment-readiness'; filter='cybernet_deployment_readiness_result.json' },
    [pscustomobject]@{ category='Cybernet'; role='full software deployment'; relative_root='survey\output\runs\cybernet-software-deployment'; filter='cybernet_software_deployment_result.json' },
    [pscustomobject]@{ category='Cybernet'; role='clinical-core deployment stage'; relative_root='survey\output\runs\cybernet-clinical-core'; filter='cybernet_clinical_core_deployment_summary.json' },
    [pscustomobject]@{ category='AutoLogon'; role='restart-complete AutoLogon deployment'; relative_root='survey\output\runs\autologon-s4u-deployment'; filter='autologon_s4u_deployment_result.json' },
    [pscustomobject]@{ category='AutoLogon'; role='S4U pre-reboot apply'; relative_root='survey\output\runs\autologon-kerberos-s4u'; filter='autologon_kerberos_s4u_pilot_result.json' },
    [pscustomobject]@{ category='Cybernet'; role='software controller result CSV'; relative_root='bash\apps\output'; filter='*.results.csv' }
)
$items=New-Object System.Collections.Generic.List[object]
$runtimeRoots=New-Object 'System.Collections.Generic.List[string]'
foreach ($candidate in @($repoCandidates)) {
    if (-not (Test-SasEvidenceRepoRoot -Path $candidate)) { continue }
    $runtimeConfig=Join-Path $candidate 'targets\local\autologon-runtime.json'
    if (Test-Path -LiteralPath $runtimeConfig -PathType Leaf) {
        try { $config=Get-Content -LiteralPath $runtimeConfig -Raw -Encoding UTF8 | ConvertFrom-Json; $directory=Get-SasJsonProperty $config 'evidence_directory'; if ($directory) { Add-SasUniquePath -List $runtimeRoots -Path ([string]$directory) } } catch {}
    }
    foreach ($definition in $definitions) {
        if ($kind -notin @('Latest','All') -and $definition.category -ne $kind) { continue }
        $searchRoot=Join-Path $candidate $definition.relative_root
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $searchRoot -Filter $definition.filter -File -Recurse -ErrorAction SilentlyContinue)) {
            $items.Add([pscustomobject]@{ category=$definition.category; role=$definition.role; path=$file.FullName; checkout=$candidate; last_write_utc=$file.LastWriteTimeUtc })
        }
    }
}
if ($kind -in @('Latest','All','Runtime')) {
    foreach ($runtimeRoot in @($runtimeRoots)) {
        if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $runtimeRoot -Filter 'runtime-proof-summary.json' -File -Recurse -ErrorAction SilentlyContinue)) { $items.Add([pscustomobject]@{ category='Runtime'; role='actual-session runtime proof'; path=$file.FullName; checkout='(runtime evidence directory from local config)'; last_write_utc=$file.LastWriteTimeUtc }) }
    }
}

$ordered=@($items | Sort-Object last_write_utc,path -Descending)
if ($kind -eq 'Latest' -and $ordered.Count -gt 1) { $ordered=@($ordered[0]) }
elseif ($ordered.Count -gt $maxItems) { $ordered=@($ordered | Select-Object -First $maxItems) }

function Get-SasEvidenceSummary {
    param([Parameter(Mandatory=$true)]$Item)
    $summary=[ordered]@{
        category=$Item.category; role=$Item.role; last_write_utc=$Item.last_write_utc.ToString('o'); path=$Item.path; checkout=$Item.checkout
        classification=$null; status=$null; proof_level=$null; overall_success=$null; reason=$null
        run_id=$null; target=$null; phase=$null; checkpoint=$null; completed_packages=@(); failed_package=$null
        cleanup_succeeded=$null; target_mutated=$null; reboot_required_but_not_performed=$null
        next_network=$null; next_command=$null; next_action='Review the artifact before retrying any failed or incomplete target operation.'
    }
    if ([IO.Path]::GetExtension($Item.path) -ieq '.json') {
        try {
            $value=Get-Content -LiteralPath $Item.path -Raw -Encoding UTF8 | ConvertFrom-Json
            $summary.classification=Get-SasJsonProperty $value 'classification'
            $summary.status=Get-SasJsonProperty $value 'status'
            $summary.proof_level=Get-SasJsonProperty $value 'proof_level'
            $summary.overall_success=Get-SasJsonProperty $value 'overall_success'
            $summary.reason=Get-SasJsonProperty $value 'reason' (Get-SasJsonProperty $value 'failure_reason')
            $summary.run_id=Get-SasJsonProperty $value 'run_id' (Get-SasJsonProperty $value 'recovered_run_id')
            $summary.target=Get-SasJsonProperty $value 'target_fqdn' (Get-SasJsonProperty $value 'target')
            $summary.phase=Get-SasJsonProperty $value 'phase'
            $summary.checkpoint=Get-SasJsonProperty $value 'checkpoint'
            $summary.failed_package=Get-SasJsonProperty $value 'failed_package' (Get-SasJsonProperty $value 'failed_package_id')
            $cleanup=Get-SasJsonProperty $value 'cleanup_succeeded'
            if ($null -ne $cleanup) { $summary.cleanup_succeeded=[bool]$cleanup }
            $mutated=Get-SasJsonProperty $value 'target_mutation_performed' (Get-SasJsonProperty $value 'staging_started')
            if ($null -ne $mutated) { $summary.target_mutated=[bool]$mutated }
            $reboot=Get-SasJsonProperty $value 'reboot_required_but_not_performed'
            if ($null -ne $reboot) { $summary.reboot_required_but_not_performed=[bool]$reboot }
            $completed=@()
            foreach ($id in @((Get-SasJsonProperty $value 'completed_package_ids' @()))) { if ($id) { $completed += [string]$id } }
            foreach ($row in @((Get-SasJsonProperty $value 'package_results' @()))) { if ($row -and [bool](Get-SasJsonProperty $row 'success' $false) -and (Get-SasJsonProperty $row 'id')) { $completed += [string](Get-SasJsonProperty $row 'id') } }
            $summary.completed_packages=@($completed | Sort-Object -Unique)
        } catch { $summary.reason='Artifact exists but could not be parsed as JSON.' }
    }
    $state=if (-not [string]::IsNullOrWhiteSpace([string]$summary.classification)) { [string]$summary.classification } else { [string]$summary.status }
    switch ($state) {
        'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED' {
            $summary.next_network='NONE'; $summary.next_command='sas evidence Cybernet'
            $summary.next_action='Five clinical-core apps are complete. AutoLogon was preserved/untouched, Imprivata was observational only, and no reboot was performed. Do not redeploy merely to recreate output.'
        }
        'CYBERNET_PROFILED_CLINICAL_CORE_RECOVERY_VERIFIED' {
            $summary.next_network='PROTECTED NORTHWELL'; if ($summary.target) { $summary.next_command="sas cybernet Core $($summary.target.Split('.')[0])" }
            $summary.next_action='Exact SysAdminSuite-owned prior-run cleanup is verified. Resume through Core; preserved completed-package evidence prevents proven work from being repeated.'
        }
        'CYBERNET_CLINICAL_CORE_SOURCES_READY' { $summary.next_action='All five package sources are ready; this source-only artifact does not prove target deployment.' }
        'CYBERNET_CLINICAL_CORE_SOURCES_INCOMPLETE' { $summary.next_network='PROTECTED NORTHWELL'; $summary.next_action='Source preflight failed before target contact/mutation. Correct the approved source/catalog issue before deployment.' }
        'CYBERNET_DEPLOYMENT_READINESS_READY' { $summary.next_action='Read-only target readiness passed. This is not deployment completion.' }
        'CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED' { $summary.next_action='Full software deployment is complete. Do not redeploy merely to recreate output.' }
        'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED' { $summary.next_action='AutoLogon deployment and restart are complete. Do not rerun merely to recreate output.' }
        'TECHNICIAN_OBSERVED_LIVE_RUNTIME' { $summary.next_action='Runtime proof is complete. Preserve this artifact.' }
        default {
            if ([string]$summary.status -match '(?i)fail|blocked|action_required' -or [string]$summary.classification -match '(?i)fail|blocked|review|required') {
                $summary.next_network='PROTECTED NORTHWELL'
                if ($summary.target) {
                    $short=([string]$summary.target).Split('.')[0]
                    $summary.next_command=if ($summary.target_mutated -and $summary.cleanup_succeeded -eq $false) { "sas cybernet Recover $short" } else { "sas cybernet Core $short" }
                }
                $summary.next_action='ACTION_REQUIRED. Preserve the failure boundary and cleanup state. Do not blindly rerun or reconstruct implementation fragments.'
            }
        }
    }
    return [pscustomobject]$summary
}

$summaries=@($ordered | ForEach-Object { Get-SasEvidenceSummary -Item $_ })
$searchedCheckoutCount=@($repoCandidates | Where-Object { Test-SasEvidenceRepoRoot -Path $_ }).Count
$index=[ordered]@{ schema_version='sas-operator-evidence-recovery/v2'; generated_at_utc=(Get-Date).ToUniversalTime().ToString('o'); network_activity_performed=$false; target_contact_performed=$false; search_kind=$kind; result_count=$summaries.Count; searched_checkout_count=$searchedCheckoutCount; results=$summaries }
$index | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $indexPath -Encoding UTF8

Write-Host 'SYSADMINSUITE OFFLINE EVIDENCE RECOVERY' -ForegroundColor Cyan
Write-Host 'Network activity: NONE | Target contact: NONE'
Write-Host "Stable local index: $indexPath"
Write-Host ''
if ($summaries.Count -eq 0) {
    Write-Host 'NO MATCHING EVIDENCE FOUND' -ForegroundColor Yellow
    Write-Host 'The bounded search checked the active checkout, cached checkout, machine-local field-ready worktrees, and common Desktop/OneDrive layouts.'
    Write-Host 'No deployment conclusion is supported by absence of local evidence.'
    exit 23
}
$position=0
foreach ($summary in $summaries) {
    $position++
    Write-Host "[$position] $($summary.role)" -ForegroundColor Green
    Write-Host "    Modified UTC: $($summary.last_write_utc)"
    if ($summary.run_id) { Write-Host "    Run ID: $($summary.run_id)" }
    if ($summary.target) { Write-Host "    Target: $($summary.target)" }
    if ($summary.classification) { Write-Host "    Classification: $($summary.classification)" }
    if ($summary.status) { Write-Host "    Status: $($summary.status)" }
    if ($summary.phase) { Write-Host "    Phase: $($summary.phase)" }
    if ($summary.checkpoint) { Write-Host "    Checkpoint: $($summary.checkpoint)" }
    if (@($summary.completed_packages).Count -gt 0) { Write-Host "    Completed packages: $(@($summary.completed_packages) -join ', ')" }
    if ($summary.failed_package) { Write-Host "    Failed package: $($summary.failed_package)" }
    if ($null -ne $summary.target_mutated) { Write-Host "    Target mutated: $($summary.target_mutated)" }
    if ($null -ne $summary.cleanup_succeeded) { Write-Host "    Cleanup verified: $($summary.cleanup_succeeded)" }
    if ($null -ne $summary.reboot_required_but_not_performed) { Write-Host "    Reboot required / not performed: $($summary.reboot_required_but_not_performed)" }
    if ($summary.reason) { Write-Host "    Reason: $($summary.reason)" }
    Write-Host "    File: $($summary.path)"
    Write-Host "    Next: $($summary.next_action)" -ForegroundColor Cyan
    if ($summary.next_network) { Write-Host "    NEXT NETWORK: $($summary.next_network)" -ForegroundColor Cyan }
    if ($summary.next_command) { Write-Host "    NEXT COMMAND: $($summary.next_command)" -ForegroundColor Green }
    Write-Host ''
}
if ($openLatest -and $summaries.Count -gt 0) { Start-Process -FilePath 'explorer.exe' -ArgumentList @((Split-Path -Parent ([string]$summaries[0].path))) | Out-Null }
exit 0