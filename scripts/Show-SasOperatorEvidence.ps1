#Requires -Version 5.1
<#
.SYNOPSIS
Find the newest SysAdminSuite deployment/readiness/runtime evidence without contacting a target.

.DESCRIPTION
Searches only bounded SysAdminSuite output roots in the current checkout and common per-user
Desktop/OneDrive checkout layouts. It never contacts a Cybernet, network share, web endpoint,
or software source. The command writes a local pointer index under %LOCALAPPDATA% so a closed
or crashed terminal does not make the last evidence undiscoverable.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$cachePath = Join-Path $stateRoot 'repo-root.txt'
$indexPath = Join-Path $stateRoot 'last-evidence.json'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

$kind = 'Latest'
$openLatest = $false
$maxItems = 12
foreach ($argument in @($Arguments)) {
    if ([string]::IsNullOrWhiteSpace($argument)) { continue }
    switch ($argument.Trim().ToLowerInvariant()) {
        'latest' { $kind = 'Latest' }
        'all' { $kind = 'All' }
        'cybernet' { $kind = 'Cybernet' }
        'autologon' { $kind = 'AutoLogon' }
        'runtime' { $kind = 'Runtime' }
        'open' { $openLatest = $true }
        default {
            if ($argument -match '^\d+$') {
                $maxItems = [Math]::Max(1, [Math]::Min(50, [int]$argument))
            }
            else {
                throw "Unknown evidence argument: $argument. Use Latest, All, Cybernet, AutoLogon, Runtime, Open, or a result count 1-50."
            }
        }
    }
}

function Add-SasUniquePath {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$List,
        [AllowNull()][string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [IO.Path]::GetFullPath($Path.Trim()) } catch { return }
    if (-not $List.Contains($full)) { [void]$List.Add($full) }
}

function Test-SasEvidenceRepoRoot {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (
        (Test-Path -LiteralPath $Path -PathType Container) -and
        ((Test-Path -LiteralPath (Join-Path $Path 'survey\output') -PathType Container) -or
         (Test-Path -LiteralPath (Join-Path $Path 'bash\apps\output') -PathType Container) -or
         (Test-Path -LiteralPath (Join-Path $Path 'scripts\SasPortableLauncher.ps1') -PathType Leaf))
    )
}

$repoCandidates = New-Object 'System.Collections.Generic.List[string]'
Add-SasUniquePath -List $repoCandidates -Path $repoRoot
Add-SasUniquePath -List $repoCandidates -Path $env:SAS_REPO_ROOT
if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    try { Add-SasUniquePath -List $repoCandidates -Path ((Get-Content -LiteralPath $cachePath -Raw).Trim()) } catch {}
}

$profileRoots = @(
    $env:USERPROFILE,
    $env:OneDrive,
    $env:OneDriveCommercial,
    $env:OneDriveConsumer
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

$checkoutNames = @('SysAdminSuite','SysAdminSuite-portable-onsite','SysAdminSuite-Live')
foreach ($root in $profileRoots) {
    foreach ($name in $checkoutNames) {
        foreach ($relative in @(
            $name,
            "dev\$name",
            "Desktop\dev\$name",
            "OG Laptop Backup\Desktop\dev\$name"
        )) {
            Add-SasUniquePath -List $repoCandidates -Path (Join-Path $root $relative)
        }
    }
}

foreach ($pattern in @(
    (Join-Path $env:USERPROFILE '*\Desktop\dev\SysAdminSuite*'),
    (Join-Path $env:USERPROFILE '*\*\Desktop\dev\SysAdminSuite*'),
    (Join-Path $env:USERPROFILE '*\*\*\Desktop\dev\SysAdminSuite*')
)) {
    try {
        foreach ($match in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) {
            Add-SasUniquePath -List $repoCandidates -Path $match.FullName
        }
    } catch {}
}

$definitions = @(
    [pscustomobject]@{ category='Cybernet'; role='one-target deployment readiness'; relative_root='survey\output\runs\cybernet-deployment-readiness'; filter='cybernet_deployment_readiness_result.json' },
    [pscustomobject]@{ category='Cybernet'; role='full software deployment'; relative_root='survey\output\runs\cybernet-software-deployment'; filter='cybernet_software_deployment_result.json' },
    [pscustomobject]@{ category='AutoLogon'; role='restart-complete AutoLogon deployment'; relative_root='survey\output\runs\autologon-s4u-deployment'; filter='autologon_s4u_deployment_result.json' },
    [pscustomobject]@{ category='AutoLogon'; role='S4U pre-reboot apply'; relative_root='survey\output\runs\autologon-kerberos-s4u'; filter='autologon_kerberos_s4u_pilot_result.json' },
    [pscustomobject]@{ category='Cybernet'; role='clinical-core deployment stage'; relative_root='survey\output\runs\cybernet-clinical-core'; filter='cybernet_clinical_core_deployment_summary.json' },
    [pscustomobject]@{ category='Cybernet'; role='software controller result CSV'; relative_root='bash\apps\output'; filter='*.results.csv' }
)

$items = New-Object System.Collections.Generic.List[object]
$runtimeRoots = New-Object 'System.Collections.Generic.List[string]'

foreach ($candidate in @($repoCandidates)) {
    if (-not (Test-SasEvidenceRepoRoot -Path $candidate)) { continue }

    $runtimeConfig = Join-Path $candidate 'targets\local\autologon-runtime.json'
    if (Test-Path -LiteralPath $runtimeConfig -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $runtimeConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            $evidenceProperty = $config.PSObject.Properties['evidence_directory']
            if ($evidenceProperty -and -not [string]::IsNullOrWhiteSpace([string]$evidenceProperty.Value)) {
                Add-SasUniquePath -List $runtimeRoots -Path ([string]$evidenceProperty.Value)
            }
        } catch {}
    }

    foreach ($definition in $definitions) {
        if ($kind -notin @('Latest','All') -and $definition.category -ne $kind) { continue }
        $searchRoot = Join-Path $candidate $definition.relative_root
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $searchRoot -Filter $definition.filter -File -Recurse -ErrorAction SilentlyContinue)) {
            $items.Add([pscustomobject]@{
                category = $definition.category
                role = $definition.role
                path = $file.FullName
                checkout = $candidate
                last_write_utc = $file.LastWriteTimeUtc
            })
        }
    }
}

if ($kind -in @('Latest','All','Runtime')) {
    foreach ($runtimeRoot in @($runtimeRoots)) {
        if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $runtimeRoot -Filter 'runtime-proof-summary.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            $items.Add([pscustomobject]@{
                category = 'Runtime'
                role = 'actual-session runtime proof'
                path = $file.FullName
                checkout = '(runtime evidence directory from local config)'
                last_write_utc = $file.LastWriteTimeUtc
            })
        }
    }
}

$ordered = @($items | Sort-Object last_write_utc, path -Descending)
if ($kind -eq 'Latest' -and $ordered.Count -gt 1) { $ordered = @($ordered[0]) }
elseif ($ordered.Count -gt $maxItems) { $ordered = @($ordered | Select-Object -First $maxItems) }

function Get-SasEvidenceSummary {
    param([Parameter(Mandatory = $true)]$Item)
    $summary = [ordered]@{
        category = $Item.category
        role = $Item.role
        last_write_utc = $Item.last_write_utc.ToString('o')
        path = $Item.path
        checkout = $Item.checkout
        classification = $null
        status = $null
        proof_level = $null
        overall_success = $null
        reason = $null
        next_action = 'Review the artifact before retrying any failed or incomplete target operation.'
    }

    if ([IO.Path]::GetExtension($Item.path) -ieq '.json') {
        try {
            $value = Get-Content -LiteralPath $Item.path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($name in @('classification','status','proof_level','overall_success','reason','failure_reason')) {
                $property = $value.PSObject.Properties[$name]
                if ($property) {
                    if ($name -eq 'failure_reason' -and [string]::IsNullOrWhiteSpace([string]$summary.reason)) {
                        $summary.reason = $property.Value
                    }
                    elseif ($name -ne 'failure_reason') {
                        $summary[$name] = $property.Value
                    }
                }
            }
        } catch {
            $summary.reason = 'Artifact exists but could not be parsed as JSON.'
        }
    }

    $state = if (-not [string]::IsNullOrWhiteSpace([string]$summary.classification)) { [string]$summary.classification } else { [string]$summary.status }
    switch ($state) {
        'CYBERNET_DEPLOYMENT_READINESS_READY' {
            $summary.next_action = 'Read-only Kerberos SMB plus Task Scheduler readiness passed. This is not deployment completion. When deployment is explicitly authorized, use sas cybernet Deploy HOST; that command runs a fresh readiness gate in the same transaction before mutation.'
        }
        'CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY' {
            $summary.next_action = 'The sanitized fixture satisfies the readiness contract, but no target was contacted or authorized. Do not promote fixture evidence to live readiness or deployment.'
        }
        'CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED' {
            $summary.next_action = 'Deployment is complete. Do not redeploy this target merely to recreate console output. Runtime proof is optional only when separately requested.'
        }
        'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED' {
            $summary.next_action = 'AutoLogon deployment and restart are complete. Do not rerun the installer merely to recreate console output.'
        }
        'KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING' {
            $summary.next_action = 'Historical/internal pre-reboot AutoLogon apply proof exists, but restart-complete deployment is not proven by this artifact. Preserve it and use the current restart-complete AutoLogon lane when back on the authorized network; do not return to fixture/live-cert loops.'
        }
        'CLINICAL_CORE_DEPLOYMENT_COMPLETED' {
            $summary.next_action = 'The five clinical applications are complete. Preserve them; AutoLogon is the remaining software state when requested.'
        }
        'TECHNICIAN_OBSERVED_LIVE_RUNTIME' {
            $summary.next_action = 'Runtime proof is complete. Preserve this artifact and do not repeat the proof merely because the original terminal closed.'
        }
        default {
            if ([string]$summary.status -match '(?i)fail|blocked|action_required' -or [string]$summary.classification -match '(?i)fail|blocked|review|required') {
                $summary.next_action = 'Preserve this evidence and inspect the recorded failure boundary. Do not blindly rerun the target.'
            }
        }
    }
    return [pscustomobject]$summary
}

$summaries = @($ordered | ForEach-Object { Get-SasEvidenceSummary -Item $_ })
$searchedCheckoutCount = @($repoCandidates | Where-Object { Test-SasEvidenceRepoRoot -Path $_ }).Count
$index = [ordered]@{
    schema_version = 'sas-operator-evidence-recovery/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    network_activity_performed = $false
    target_contact_performed = $false
    search_kind = $kind
    result_count = $summaries.Count
    searched_checkout_count = $searchedCheckoutCount
    results = $summaries
}
$index | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $indexPath -Encoding UTF8

Write-Host 'SYSADMINSUITE OFFLINE EVIDENCE RECOVERY' -ForegroundColor Cyan
Write-Host 'Network activity: NONE | Target contact: NONE'
Write-Host "Stable local index: $indexPath"
Write-Host ''

if ($summaries.Count -eq 0) {
    Write-Host 'NO MATCHING EVIDENCE FOUND' -ForegroundColor Yellow
    Write-Host 'The bounded search checked the current repo plus common per-user Desktop/OneDrive SysAdminSuite checkout layouts.'
    Write-Host 'No deployment conclusion is supported by absence of local evidence.'
    exit 23
}

$position = 0
foreach ($summary in $summaries) {
    $position++
    Write-Host "[$position] $($summary.role)" -ForegroundColor Green
    Write-Host "    Modified UTC: $($summary.last_write_utc)"
    if (-not [string]::IsNullOrWhiteSpace([string]$summary.classification)) { Write-Host "    Classification: $($summary.classification)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$summary.status)) { Write-Host "    Status: $($summary.status)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$summary.proof_level)) { Write-Host "    Proof level: $($summary.proof_level)" }
    if ($null -ne $summary.overall_success) { Write-Host "    Overall success: $($summary.overall_success)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$summary.reason)) { Write-Host "    Reason: $($summary.reason)" }
    Write-Host "    File: $($summary.path)"
    Write-Host "    Next: $($summary.next_action)" -ForegroundColor Cyan
    Write-Host ''
}

if ($openLatest -and $summaries.Count -gt 0) {
    $folder = Split-Path -Parent ([string]$summaries[0].path)
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($folder) | Out-Null
}

exit 0
