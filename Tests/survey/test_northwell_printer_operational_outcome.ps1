#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$enginePath = Join-Path $repoRoot 'scripts\Invoke-SasNorthwellPrinterQueueOperationalCheck.ps1'
if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Missing operational engine: $enginePath"
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $enginePath),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    throw ($errors | ForEach-Object { $_.Message } | Out-String)
}

$functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-SasOperationalOutcome'
}, $true)
if (-not $functionAst) {
    throw 'Get-SasOperationalOutcome was not found in the operational engine.'
}

Invoke-Expression $functionAst.Extent.Text

$raw = [pscustomobject]@{
    spooler = [pscustomobject]@{ status='Running'; running=$true }
    tcp = @(
        [pscustomobject]@{ port=445; status='OPEN' },
        [pscustomobject]@{ port=135; status='OPEN' }
    )
    local_queue = [pscustomobject]@{ found=$true; printer_status='Normal' }
    cim_queue = [pscustomobject]@{ found=$true; work_offline=$false }
    printer_ip_probe_9100 = [pscustomobject]@{ status='OPEN' }
    remote_query = [pscustomobject]@{ status='TIMEOUT' }
    observed_rpc_connections = @(
        [pscustomobject]@{ remote_port=56161; state='SynSent' },
        [pscustomobject]@{ remote_port=56161; state='Established' }
    )
}

$prior = [pscustomobject]@{
    found = $true
    physical_output_observed = $true
    evidence_path = 'C:\evidence\prior.json'
}

$outcome = Get-SasOperationalOutcome -Raw $raw -PriorPhysicalProof $prior
if ($outcome.status -ne 'PASS') {
    throw "Prior physical print plus current healthy queue must PASS; got $($outcome.status)."
}
if ($outcome.classification -ne 'QUEUE_OPERATIONAL_PHYSICAL_PROOF_PRESERVED') {
    throw "Unexpected preserved-physical-proof classification: $($outcome.classification)"
}
if ($outcome.warnings -notcontains 'REMOTE_STATUS_QUERY_TIMEOUT') {
    throw 'Remote status timeout must remain a warning instead of becoming a print failure.'
}
if ($outcome.warnings -notcontains 'TRANSIENT_RPC_SYN_SENT_WITH_ESTABLISHED_DYNAMIC_RPC') {
    throw 'Transient SynSent must not outrank an established dynamic RPC connection.'
}

$noPrior = [pscustomobject]@{ found=$false; physical_output_observed=$false; evidence_path=$null }
$outcomeNoPrior = Get-SasOperationalOutcome -Raw $raw -PriorPhysicalProof $noPrior
if ($outcomeNoPrior.status -ne 'PASS') {
    throw "Current healthy local queue plus established RPC must PASS despite remote status timeout; got $($outcomeNoPrior.status)."
}
if ($outcomeNoPrior.classification -ne 'QUEUE_OPERATIONAL_STATUS_TELEMETRY_DEGRADED') {
    throw "Unexpected degraded-telemetry classification: $($outcomeNoPrior.classification)"
}

$raw.tcp = @(
    [pscustomobject]@{ port=445; status='TIMEOUT' },
    [pscustomobject]@{ port=135; status='OPEN' }
)
$hardFailure = Get-SasOperationalOutcome -Raw $raw -PriorPhysicalProof $prior
if ($hardFailure.status -ne 'FAIL' -or $hardFailure.classification -ne 'PRINT_SERVER_SMB_UNREACHABLE') {
    throw 'Current hard SMB failure must outrank prior physical proof.'
}

$engineText = Get-Content -LiteralPath $enginePath -Raw
if ($engineText -match 'PrintTestPage') {
    throw 'Default operational engine regressed to containing PrintTestPage.'
}
if ($engineText -notmatch 'latest\.json' -or $engineText -notmatch 'latest\.txt') {
    throw 'Operational engine lost stable latest evidence aliases.'
}

Write-Host 'PASS: printer operational outcome preserves physical proof without reprinting.'
Write-Host 'PASS: remote status timeout is telemetry degradation, not a print failure.'
Write-Host 'PASS: current hard transport failures still fail.'
