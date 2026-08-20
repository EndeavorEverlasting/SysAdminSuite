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

foreach ($name in @(
    'ConvertTo-SasComputerKey',
    'Get-SasLatestMappingEvidenceRoot',
    'Get-SasLatestMappedTargetForPrinter',
    'Get-SasRemoteMachineWideProof',
    'Get-SasOperationalOutcome'
)) {
    $functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $name
    }, $true)
    if (-not $functionAst) { throw "$name was not found in the operational engine." }
    Invoke-Expression $functionAst.Extent.Text
}

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

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-printer-target-proof-' + [guid]::NewGuid().ToString('N'))
try {
    $logsRoot = Join-Path $fixtureRoot 'mapping\Logs'
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

    $queue = '\\PRINTSRV01\QUEUE01'
    $oldRoot = Join-Path $logsRoot 'NorthwellPrinterMap-old'
    $oldHost = Join-Path $oldRoot 'lpw003asi163.nslijhs.net'
    New-Item -ItemType Directory -Path $oldHost -Force | Out-Null
    [ordered]@{ CompletedTargets=1; TotalTargets=1; Success=$true } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $oldRoot 'Summary.json') -Encoding UTF8
    [ordered]@{
        ComputerName = 'LPW003ASI163'
        Identity = 'NT AUTHORITY\SYSTEM'
        Success = $true
        Requested = @($queue)
        MachineWideUNC = @($queue)
        Missing = @()
        Finished = '2026-08-20T00:55:00-04:00'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $oldHost 'Status.json') -Encoding UTF8

    $latestRoot = Join-Path $logsRoot 'NorthwellPrinterMap-latest'
    $latestHost = Join-Path $latestRoot 'lpw003asi163.nslijhs.net'
    New-Item -ItemType Directory -Path $latestHost -Force | Out-Null
    [ordered]@{ CompletedTargets=1; TotalTargets=1; Success=$true } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $latestRoot 'Summary.json') -Encoding UTF8
    $latestStatusPath = Join-Path $latestHost 'Status.json'
    [ordered]@{
        ComputerName = 'LPW003ASI163'
        Identity = 'NT AUTHORITY\SYSTEM'
        Success = $true
        Requested = @($queue)
        MachineWideUNC = @($queue)
        Missing = @()
        Finished = '2026-08-20T01:00:00-04:00'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $latestStatusPath -Encoding UTF8
    $latestRoot | Set-Content -LiteralPath (Join-Path $logsRoot 'LATEST-PATH.txt') -Encoding UTF8

    $resolvedRoot = Get-SasLatestMappingEvidenceRoot -RepoRoot $fixtureRoot -RetryCount 1 -RetryDelayMilliseconds 0
    if ($resolvedRoot -ne $latestRoot) {
        throw "Latest complete mapping root was not resolved; got '$resolvedRoot'."
    }

    $recoveredTarget = Get-SasLatestMappedTargetForPrinter -RepoRoot $fixtureRoot -Printer $queue
    if ($recoveredTarget -ne 'LPW003ASI163') {
        throw "Latest mapping evidence did not recover the remote target; got '$recoveredTarget'."
    }

    $remoteProof = Get-SasRemoteMachineWideProof -RepoRoot $fixtureRoot -ComputerName 'lpw003asi163.nslijhs.net' -Printer $queue
    if (-not $remoteProof.found -or -not $remoteProof.proven) {
        throw 'Matching SYSTEM + HKLM evidence for the latest complete remote target run must be recognized as proven.'
    }
    if ($remoteProof.evidence_root -ne $latestRoot) {
        throw 'Remote proof must be scoped to the current LATEST-PATH evidence root.'
    }

    [ordered]@{
        ComputerName = 'LPW003ASI163'
        Identity = 'NT AUTHORITY\SYSTEM'
        Success = $false
        Requested = $queue
        MachineWideUNC = $queue
        Missing = '\\PRINTSRV01\QUEUE01'
        Finished = '2026-08-20T01:01:00-04:00'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $latestStatusPath -Encoding UTF8

    $singletonMissing = Get-SasRemoteMachineWideProof -RepoRoot $fixtureRoot -ComputerName 'lpw003asi163.nslijhs.net' -Printer $queue
    if (-not $singletonMissing.found -or $singletonMissing.proven) {
        throw 'A singleton Missing value in the latest run must remain a bounded negative proof rather than throwing or becoming proven.'
    }
    if (@($singletonMissing.missing).Count -ne 1) {
        throw "Singleton Missing evidence was not preserved as one item; count=$(@($singletonMissing.missing).Count)."
    }
    if ($singletonMissing.evidence_root -ne $latestRoot) {
        throw 'An older successful run must not supersede the latest complete negative target proof.'
    }

    $wrongQueue = Get-SasRemoteMachineWideProof -RepoRoot $fixtureRoot -ComputerName 'lpw003asi163.nslijhs.net' -Printer '\\PRINTSRV01\OTHERQUEUE'
    if ($wrongQueue.found -or $wrongQueue.proven) {
        throw 'Evidence for a different queue must not be reused as remote target proof.'
    }

    $partialRoot = Join-Path $logsRoot 'NorthwellPrinterMap-partial'
    New-Item -ItemType Directory -Path $partialRoot -Force | Out-Null
    [ordered]@{ CompletedTargets=0; TotalTargets=1; Success=$false } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $partialRoot 'Summary.json') -Encoding UTF8
    $partialRoot | Set-Content -LiteralPath (Join-Path $logsRoot 'LATEST-PATH.txt') -Encoding UTF8
    $partialResolved = Get-SasLatestMappingEvidenceRoot -RepoRoot $fixtureRoot -RetryCount 1 -RetryDelayMilliseconds 0
    if ($null -ne $partialResolved) {
        throw 'An incompletely published latest mapping run must not be accepted as current proof context.'
    }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$engineText = Get-Content -LiteralPath $enginePath -Raw
if ($engineText -match 'PrintTestPage') {
    throw 'Default operational engine regressed to containing PrintTestPage.'
}
if ($engineText -notmatch 'latest\.json' -or $engineText -notmatch 'latest\.txt') {
    throw 'Operational engine lost stable latest evidence aliases.'
}
if ($engineText -notmatch 'REMOTE_TARGET_MACHINE_WIDE_REGISTRATION_PROVEN') {
    throw 'Operational engine lost the remote target SYSTEM + HKLM proof classification.'
}
if ($engineText -notmatch 'LATEST_MAPPING_EVIDENCE') {
    throw 'Operational engine lost automatic target recovery from latest canonical mapping evidence.'
}
if ($engineText -notmatch 'REMOTE_TARGET_RUNTIME_QUEUE_STATE_NOT_OBSERVED') {
    throw 'Remote target proof must not overstate runtime queue-state observation.'
}
if ($engineText -notmatch 'TARGET_CONTEXT_UNRESOLVED' -or $engineText -match "targetResolution = 'LOCAL_DEFAULT'") {
    throw 'Unresolved target context must fail closed instead of defaulting to the controller workstation.'
}
if ($engineText -notmatch 'diagnosticOutputRoot' -or $engineText -notmatch "Get-ChildItem -LiteralPath \$diagnosticOutputRoot") {
    throw 'Local bounded diagnostics must use an isolated run-scoped artifact root.'
}

Write-Host 'PASS: printer operational outcome preserves physical proof without reprinting.'
Write-Host 'PASS: remote status timeout is telemetry degradation, not a print failure.'
Write-Host 'PASS: current hard transport failures still fail.'
Write-Host 'PASS: remote target mapping proof is restricted to the latest complete mapping run.'
Write-Host 'PASS: older successful proof cannot hide a latest negative target result.'
Write-Host 'PASS: incomplete mapping publication fails closed.'
Write-Host 'PASS: singleton remote Missing evidence remains strict-mode safe.'
Write-Host 'PASS: local diagnostic artifacts are run-isolated.'
