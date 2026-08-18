#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $ConfirmRepair) { throw 'Final-step gate path repair requires -ConfirmRepair.' }

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$targetPath = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonFinalStepGate.ps1'
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw "Final-step gate runtime surface missing: $targetPath" }

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Join-Path $RuntimeRoot 'runs\field-repair' } else { Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes' }
    $EvidenceRoot = Join-Path $base ('final-gate-path-repair-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$backupPath = Join-Path $EvidenceRoot 'Invoke-SasAutoLogonFinalStepGate.before.ps1'
$resultPath = Join-Path $EvidenceRoot 'final-gate-path-runtime-repair-result.json'

function Get-RepairHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
function Assert-Parse([string]$Text) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) { throw ('Repaired final-step gate does not parse: ' + (($errors | ForEach-Object { $_.Message }) -join '; ')) }
}
function Test-RepairPresent([string]$Text) {
    return ($Text.Contains('$finalGatePathBudgetChars = 240') -and
        $Text.Contains("`$finalGateFileName = 'autologon_final_step_gate.json'") -and
        $Text.Contains('FINAL_GATE_OUTPUT_PATH_COMPACTED') -and
        $Text.Contains("`$gateResult['output_path_compacted'] = `$compacted") -and
        $Text.Contains('Compacted final-step gate output collision'))
}

$source = [IO.File]::ReadAllText($targetPath)
$beforeSha = Get-RepairHash $targetPath
$changed = $false
$classification = 'AUTOLOGON_FINAL_GATE_PATH_RUNTIME_REPAIR_ALREADY_PRESENT'

if (-not (Test-RepairPresent $source)) {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force -ErrorAction Stop
    $newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $source.Replace("`r`n","`n").Replace("`r","`n")

    $gateAnchor = '$gateResult = [ordered]@{'
    $gateFirst = $text.IndexOf($gateAnchor, [StringComparison]::Ordinal)
    if ($gateFirst -lt 0 -or $text.IndexOf($gateAnchor, $gateFirst + 1, [StringComparison]::Ordinal) -ge 0) {
        throw 'Final-step gate repair gate-result anchor is missing or ambiguous.'
    }
    $constants = @'
$finalGatePathBudgetChars = 240
$finalGateFileName = 'autologon_final_step_gate.json'

$gateResult = [ordered]@{
'@
    $text = $text.Replace($gateAnchor, $constants)

    $startMarker = '# ── Write gate result'
    $endMarker = '[pscustomobject]$gateResult'
    $start = $text.IndexOf($startMarker, [StringComparison]::Ordinal)
    $end = $text.IndexOf($endMarker, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) { throw 'Final-step gate repair write/output section boundaries were not found.' }
    if ($text.IndexOf($startMarker, $start + 1, [StringComparison]::Ordinal) -ge 0 -or $text.IndexOf($endMarker, $end + 1, [StringComparison]::Ordinal) -ge 0) {
        throw 'Final-step gate repair write/output section boundaries are ambiguous.'
    }

    $replacement = @'
# ── Write gate result ──────────────────────────────────────────────────
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $resolvedOutputRoot = [IO.Path]::GetFullPath($OutputRoot)
    $requestedGatePath = Join-Path (Join-Path $resolvedOutputRoot $RunId) $finalGateFileName
    $flatGatePath = Join-Path $resolvedOutputRoot $finalGateFileName
    $gatePath = $requestedGatePath
    $compacted = $false
    if ($requestedGatePath.Length -gt $finalGatePathBudgetChars) {
        if ($flatGatePath.Length -gt $finalGatePathBudgetChars) { throw "AutoLogon final-step gate output path exceeds the $finalGatePathBudgetChars-character budget even after compaction: $flatGatePath" }
        if (Test-Path -LiteralPath $flatGatePath -PathType Leaf) {
            try { $existing = Get-Content -LiteralPath $flatGatePath -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { throw "Compacted final-step gate output already exists but is unreadable; refusing overwrite: $flatGatePath" }
            if ([string]$existing.run_id -ne $RunId) { throw "Compacted final-step gate output collision: existing run '$($existing.run_id)' does not match '$RunId'." }
        }
        $gatePath = $flatGatePath
        $compacted = $true
        Write-Warning "FINAL_GATE_OUTPUT_PATH_COMPACTED: using $gatePath"
    }
    $gateDir = Split-Path -Parent $gatePath
    if (-not (Test-Path -LiteralPath $gateDir -PathType Container)) { New-Item -ItemType Directory -Path $gateDir -Force | Out-Null }
    $gateResult['output_path_budget_chars'] = $finalGatePathBudgetChars
    $gateResult['output_path_requested'] = $requestedGatePath
    $gateResult['output_path'] = $gatePath
    $gateResult['output_path_compacted'] = $compacted
    $gateResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $gatePath -Encoding UTF8
}

# ── Output ─────────────────────────────────────────────────────────────
'@
    $candidate = $text.Substring(0,$start) + $replacement + "`n" + $text.Substring($end)
    if ($newline -eq "`r`n") { $candidate = $candidate.Replace("`n","`r`n") }

    try {
        Assert-Parse $candidate
        if (-not (Test-RepairPresent $candidate)) { throw 'Final-step gate repair semantic verification failed.' }
        [IO.File]::WriteAllText($targetPath, $candidate, (New-Object Text.UTF8Encoding($false)))
        $changed = $true
        $classification = 'AUTOLOGON_FINAL_GATE_PATH_RUNTIME_REPAIR_APPLIED'
    }
    catch {
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force -ErrorAction SilentlyContinue
        throw "FINAL-GATE PATH REPAIR FAILED; ORIGINAL RESTORED. $($_.Exception.Message)"
    }
}

$final = [IO.File]::ReadAllText($targetPath)
Assert-Parse $final
if (-not (Test-RepairPresent $final)) { throw 'Final-step gate path repair markers are absent after repair.' }
$afterSha = Get-RepairHash $targetPath
$result = [pscustomobject][ordered]@{
    schema_version='sas-autologon-final-gate-path-runtime-repair/v1'; classification=$classification; runtime_root=$RuntimeRoot; target_path=$targetPath; changed=$changed
    before_sha256=$beforeSha; after_sha256=$afterSha; path_budget_chars=240; flattened_filename='autologon_final_step_gate.json'
    powershell_parse_passed=$true; semantic_verification=$true; git_performed=$false; network_activity_performed=$false; target_contact_performed=$false; target_mutation_performed=$false
    evidence_path=$resultPath; completed_at_utc=(Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($PassThru) { return $result }
Write-Host $result.classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"
