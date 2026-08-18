#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$repairScript = Join-Path $repoRoot 'scripts\Repair-SasAutoLogonFinalStepGatePathRuntime.ps1'
if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) {
    throw "Missing final-gate runtime repair script: $repairScript"
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-OldFinalGateFixture {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)][ValidateSet('crlf','lf')][string]$LineEnding)

    $text = @'
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$gateResult = [ordered]@{
    gate_id = 'autologon-final-step'
    gate_version = '1.0.0'
    run_id = $RunId
    overall_pass = $true
}

# ── Write gate result ──────────────────────────────────────────────────
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $gateDir = Join-Path $OutputRoot $RunId
    if (-not (Test-Path -LiteralPath $gateDir)) {
        New-Item -ItemType Directory -Path $gateDir -Force | Out-Null
    }
    $gatePath = Join-Path $gateDir 'autologon_final_step_gate.json'
    $gateResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $gatePath -Encoding UTF8
}

[pscustomobject]$gateResult
'@
    $text = $text.Replace("`r`n","`n").Replace("`r","`n")
    if ($LineEnding -eq 'crlf') { $text = $text.Replace("`n","`r`n") }
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function New-LongOutputRoot {
    param([Parameter(Mandatory = $true)][string]$BaseRoot)
    $root = Join-Path $BaseRoot 'fg'
    while ((Join-Path $root 'autologon_final_step_gate.json').Length -lt 220) {
        $root = Join-Path $root ('seg-' + ('y' * 14))
    }
    $flat = Join-Path $root 'autologon_final_step_gate.json'
    if ($flat.Length -gt 240) { throw "Repair fixture flat path exceeded budget: $($flat.Length)" }
    return $root
}

function New-TooDeepOutputRoot {
    param([Parameter(Mandatory = $true)][string]$BaseRoot)
    $root = Join-Path $BaseRoot 'deep'
    while ((Join-Path $root 'autologon_final_step_gate.json').Length -le 250) {
        $root = Join-Path $root ('deep-' + ('q' * 14))
    }
    return $root
}

foreach ($ending in @('crlf','lf')) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('sas-final-gate-repair-' + $ending + '-' + [guid]::NewGuid().ToString('N'))
    $scripts = Join-Path $root 'scripts'
    $evidenceOne = Join-Path $root 'evidence-one'
    $evidenceTwo = Join-Path $root 'evidence-two'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null

    try {
        $fixture = Join-Path $scripts 'Invoke-SasAutoLogonFinalStepGate.ps1'
        New-OldFinalGateFixture -Path $fixture -LineEnding $ending

        $first = & $repairScript -RuntimeRoot $root -EvidenceRoot $evidenceOne -ConfirmRepair -PassThru
        Assert-True ([string]$first.classification -eq 'AUTOLOGON_FINAL_GATE_PATH_RUNTIME_REPAIR_APPLIED') `
            "$ending first repair classification was $($first.classification)"
        Assert-True ([bool]$first.changed) "$ending first repair did not report a change."
        Assert-True ([bool]$first.powershell_parse_passed) "$ending repaired script did not parse."
        Assert-True ([bool]$first.semantic_verification) "$ending repair did not record semantic verification."
        Assert-True (-not [bool]$first.git_performed) "$ending repair performed Git activity."
        Assert-True (-not [bool]$first.network_activity_performed) "$ending repair performed network activity."
        Assert-True (-not [bool]$first.target_contact_performed) "$ending repair contacted a target."
        Assert-True (-not [bool]$first.target_mutation_performed) "$ending repair mutated a target."
        Assert-True ([string]$first.schema_version -eq 'sas-autologon-final-gate-path-runtime-repair/v2') "$ending repair evidence schema did not advance to v2."

        $repaired = [IO.File]::ReadAllText($fixture)
        foreach ($marker in @(
            '$finalGatePathBudgetChars = 240',
            "`$finalGateFileName = 'autologon_final_step_gate.json'",
            '$finalGateFallbackRoot = Join-Path',
            'FINAL_GATE_OUTPUT_PATH_COMPACTED',
            "`$gateResult['output_path_compaction_mode'] = `$compactionMode",
            'Compacted final-step gate output collision'
        )) {
            Assert-True ($repaired.Contains($marker)) "$ending repaired fixture missing marker: $marker"
        }

        $runId = 'autologon-delta-20260714-143000-1a2b3c4d'
        $longRoot = New-LongOutputRoot -BaseRoot (Join-Path $root 'long-output')
        $requested = Join-Path (Join-Path $longRoot $runId) 'autologon_final_step_gate.json'
        $flat = Join-Path $longRoot 'autologon_final_step_gate.json'
        Assert-True ($requested.Length -gt 240) "$ending repair fixture did not reproduce over-budget nested output."
        Assert-True ($requested.Length -ge 260 -and $requested.Length -le 280) `
            "$ending repair fixture did not reproduce the field path class: $($requested.Length)"

        $runOutput = @(& $fixture -RunId $runId -OutputRoot $longRoot)
        $gateRun = @($runOutput | Where-Object { $_.PSObject.Properties.Name -contains 'overall_pass' }) | Select-Object -Last 1
        Assert-True ($null -ne $gateRun -and [bool]$gateRun.overall_pass) "$ending repaired fixture did not return its gate success object."
        Assert-True (Test-Path -LiteralPath $flat -PathType Leaf) "$ending compacted gate evidence was not written."
        Assert-True (-not (Test-Path -LiteralPath $requested -PathType Leaf)) "$ending over-budget nested evidence unexpectedly exists."

        $written = Get-Content -LiteralPath $flat -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ([bool]$written.output_path_compacted) "$ending compacted artifact did not record compaction."
        Assert-True ([string]$written.output_path_compaction_mode -eq 'requested_root') "$ending field-class artifact did not record requested-root compaction."
        Assert-True ([string]$written.output_path -eq ([IO.Path]::GetFullPath($flat))) "$ending compacted artifact recorded the wrong actual path."
        Assert-True ([string]$written.output_path_requested -eq ([IO.Path]::GetFullPath($requested))) "$ending compacted artifact lost the requested path."
        Assert-True ([int]$written.output_path_budget_chars -eq 240) "$ending compacted artifact lost the 240-character budget."
        Assert-True ([string]$written.run_id -eq $runId) "$ending compacted artifact lost run identity."

        $deepRoot = New-TooDeepOutputRoot -BaseRoot (Join-Path $root 'too-deep-output')
        $deepFlat = Join-Path $deepRoot 'autologon_final_step_gate.json'
        Assert-True ($deepFlat.Length -gt 240) "$ending deep fixture did not exceed the flat path budget."
        $fallbackExpected = Join-Path (Join-Path (Join-Path (Join-Path $root 'runs') 'final-gate') $runId) 'autologon_final_step_gate.json'
        Assert-True ($fallbackExpected.Length -le 240) "$ending repaired fallback path unexpectedly exceeds budget."

        $deepOutput = @(& $fixture -RunId $runId -OutputRoot $deepRoot)
        $deepGateRun = @($deepOutput | Where-Object { $_.PSObject.Properties.Name -contains 'overall_pass' }) | Select-Object -Last 1
        Assert-True ($null -ne $deepGateRun -and [bool]$deepGateRun.overall_pass) "$ending deep-root repaired gate did not return success."
        Assert-True (Test-Path -LiteralPath $fallbackExpected -PathType Leaf) "$ending repaired gate did not write repository fallback evidence."
        $deepWritten = Get-Content -LiteralPath $fallbackExpected -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ([string]$deepWritten.output_path_compaction_mode -eq 'repository_runs') "$ending deep-root artifact did not record repository-runs mode."
        Assert-True ([string]$deepWritten.output_path -eq ([IO.Path]::GetFullPath($fallbackExpected))) "$ending deep-root artifact recorded the wrong fallback path."
        Assert-True ([string]$deepWritten.run_id -eq $runId) "$ending deep-root artifact lost run identity."

        $second = & $repairScript -RuntimeRoot $root -EvidenceRoot $evidenceTwo -ConfirmRepair -PassThru
        Assert-True ([string]$second.classification -eq 'AUTOLOGON_FINAL_GATE_PATH_RUNTIME_REPAIR_ALREADY_PRESENT') `
            "$ending second repair was not idempotent: $($second.classification)"
        Assert-True (-not [bool]$second.changed) "$ending second repair reported an unexpected change."
        Assert-True ([bool]$second.semantic_verification) "$ending second repair lost semantic verification."

        Write-Host "PASS: $ending final-step gate runtime repair, field-class compaction, deep-root fallback, and idempotence"
    }
    finally {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
