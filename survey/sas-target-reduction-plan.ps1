#Requires -Version 5.1
<#
.SYNOPSIS
Builds reduced, retry, review, out-of-scope, and location candidate queues from prior local evidence.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PriorProbeResults,

    [Parameter(Mandatory = $false)]
    [string]$LocationSubnetMap,

    [Parameter(Mandatory = $false)]
    [string]$IdentityEvidence,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures,

    [Parameter(Mandatory = $false)]
    [switch]$AllowNonstandardInput
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoGuess = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $repoGuess 'scripts/SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule)) { throw "Missing shared target intake module: $targetIntakeModule" }
Import-Module $targetIntakeModule -Force

$lowNoiseModule = Join-Path $repoGuess 'scripts/SasLowNoisePolicy.psm1'
if (-not (Test-Path -LiteralPath $lowNoiseModule)) { throw "Missing shared low-noise policy module: $lowNoiseModule" }
Import-Module $lowNoiseModule -Force

$reductionColumns = @(
    'Target', 'Serial', 'Site', 'Location', 'SubnetCIDR', 'Status', 'StatusReason',
    'ReachabilityEvidence', 'IdentityEvidence', 'LowNoisePolicyVersion', 'LowNoiseDisposition',
    'ProbeAgainGuidance', 'FreshEvidenceGuidance', 'NetworkVisibilityNote', 'NetworkActivityPerformed', 'SourceEvidence'
)
$locationColumns = @(
    'Site', 'Location', 'Building', 'Floor', 'SubnetCIDR', 'Gateway', 'Target', 'Status',
    'StatusReason', 'SourceEvidence', 'LastVerified', 'SurveyAllowed', 'Confidence', 'Notes', 'NetworkActivityPerformed'
)
$targetFields = @('Target', 'ProbeTarget', 'HostName', 'Hostname', 'ComputerName', 'DeviceName', 'Name', 'DnsName', 'DNSName', 'FQDN', 'IPAddress', 'IP', 'IPv4')
$serialFields = @('Serial', 'SerialNumber', 'DeviceSerial', 'ComputerSerial', 'AssetSerial', 'SN')
$locationFields = @('Location', 'Room', 'Department', 'Area')

function New-SafeRunId {
    param([string]$Candidate)
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        $safe = ($Candidate.ToLowerInvariant() -replace '[^a-z0-9_-]', '-').Trim('-')
        if (-not [string]::IsNullOrWhiteSpace($safe)) { return $safe }
    }
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Get-RowValue {
    param($Row, [string[]]$Names)
    if ($null -eq $Row) { return '' }
    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return ([string]$prop.Value).Trim() }
    }
    return ''
}

function ConvertTo-NormalizedKey {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().ToLowerInvariant()
}

function Get-TargetFromRow { param($Row) return Get-RowValue -Row $Row -Names $targetFields }
function Get-SerialFromRow { param($Row) return Get-RowValue -Row $Row -Names $serialFields }
function Get-SiteFromRow { param($Row) return Get-RowValue -Row $Row -Names @('Site') }
function Get-LocationFromRow { param($Row) return Get-RowValue -Row $Row -Names $locationFields }
function Get-LocationKey { param([string]$Site, [string]$Location) return ('{0}|{1}' -f (ConvertTo-NormalizedKey $Site), (ConvertTo-NormalizedKey $Location)) }

function Test-IsTruthy {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value.Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'y', 'fresh', 'current', 'inscope', 'in_scope', 'in-scope')
}

function Test-IsReached {
    param($Row)
    $values = @(
        (Get-RowValue -Row $Row -Names @('ReachabilityStatus', 'Status', 'Result')),
        (Get-RowValue -Row $Row -Names @('PortStatus', 'TcpStatus', 'TCPStatus'))
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($value in $values) {
        $v = $value.Trim().ToLowerInvariant()
        if ($v -in @('reached', 'reachable', 'success', 'online', 'open', 'confirmedreached')) { return $true }
    }
    return $false
}

function Test-IsRetrySignal {
    param($Row)
    $values = @(
        (Get-RowValue -Row $Row -Names @('ReachabilityStatus', 'Status', 'Result')),
        (Get-RowValue -Row $Row -Names @('PortStatus', 'TcpStatus', 'TCPStatus')),
        (Get-RowValue -Row $Row -Names @('DnsStatus', 'DNSStatus'))
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($value in $values) {
        $v = $value.Trim().ToLowerInvariant()
        if ($v -in @('notreached', 'not_reached', 'not_reachable', 'closed', 'filtered', 'dnsfailed', 'dns_failed', 'unresolved')) { return $true }
    }
    return $false
}

function Test-IdentityReviewRequired {
    param($ProbeRow, $IdentityRow)
    foreach ($row in @($ProbeRow, $IdentityRow)) {
        if ($null -eq $row) { continue }
        foreach ($name in @('IdentityStatus', 'IdentityEvidenceStatus', 'BridgeStatus', 'SerialStatus', 'TargetBridgeStatus')) {
            $value = Get-RowValue -Row $row -Names @($name)
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $v = $value.Trim().ToLowerInvariant()
            if ($v -in @('missing', 'missingbridge', 'missing_bridge', 'nobridge', 'no_bridge', 'conflicting', 'conflict', 'stale', 'serialmismatch', 'serial_mismatch', 'reviewrequired', 'review_required')) { return $true }
        }
    }
    return $false
}

function Get-IdentityText {
    param($ProbeRow, $IdentityRow)
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($ProbeRow, $IdentityRow)) {
        if ($null -eq $row) { continue }
        foreach ($name in @('IdentityStatus', 'IdentityEvidenceStatus', 'BridgeStatus', 'SerialStatus', 'TargetBridgeStatus', 'SourceEvidence', 'EvidencePath', 'EvidenceSource')) {
            $value = Get-RowValue -Row $row -Names @($name)
            if (-not [string]::IsNullOrWhiteSpace($value)) { $values.Add($value) }
        }
    }
    if ($values.Count -eq 0) { return 'not_identity_proof' }
    return (($values | Select-Object -Unique) -join ';')
}

function Get-ReachabilityText {
    param($Row)
    return ((@(
        (Get-RowValue -Row $Row -Names @('ReachabilityStatus', 'Status', 'Result')),
        (Get-RowValue -Row $Row -Names @('PortStatus', 'TcpStatus', 'TCPStatus')),
        (Get-RowValue -Row $Row -Names @('DnsStatus', 'DNSStatus'))
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';')
}

function New-IdentityIndex {
    param([object[]]$Rows)
    $index = [pscustomobject]@{ ByTarget = @{}; BySerial = @{} }
    foreach ($row in $Rows) {
        $targetKey = ConvertTo-NormalizedKey (Get-TargetFromRow $row)
        $serialKey = ConvertTo-NormalizedKey (Get-SerialFromRow $row)
        if ($targetKey -and -not $index.ByTarget.ContainsKey($targetKey)) { $index.ByTarget[$targetKey] = $row }
        if ($serialKey -and -not $index.BySerial.ContainsKey($serialKey)) { $index.BySerial[$serialKey] = $row }
    }
    return $index
}

function Get-IdentityRow {
    param([string]$Target, [string]$Serial, $Index)
    $targetKey = ConvertTo-NormalizedKey $Target
    $serialKey = ConvertTo-NormalizedKey $Serial
    if ($targetKey -and $Index.ByTarget.ContainsKey($targetKey)) { return $Index.ByTarget[$targetKey] }
    if ($serialKey -and $Index.BySerial.ContainsKey($serialKey)) { return $Index.BySerial[$serialKey] }
    return $null
}

function New-LocationIndex {
    param([object[]]$Rows)
    $index = @{}
    foreach ($row in $Rows) {
        $key = Get-LocationKey -Site (Get-SiteFromRow $row) -Location (Get-LocationFromRow $row)
        if ($key -ne '|' -and -not $index.ContainsKey($key)) { $index[$key] = $row }
    }
    return $index
}

function Import-SasPlannerCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [string[]]$RequiredColumns = @(),
        [string[]]$RequiredAnyColumns = @()
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser -ArgumentList $Path
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true
    $parser.TrimWhiteSpace = $false

    try {
        if ($parser.EndOfData) { throw "$Label has no CSV header: $Path" }
        $headers = @($parser.ReadFields() | ForEach-Object { ([string]$_).Trim() })
        if ($headers.Count -eq 0 -or @($headers | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            throw "$Label has a blank CSV header: $Path"
        }

        $headerIndex = @{}
        foreach ($header in $headers) {
            if ($headerIndex.ContainsKey($header)) { throw "$Label has duplicate case-insensitive CSV headers: $Path" }
            $headerIndex[$header] = $true
        }
        foreach ($required in $RequiredColumns) {
            if (-not $headerIndex.ContainsKey($required)) { throw "$Label is missing required CSV column '$required': $Path" }
        }
        if ($RequiredAnyColumns.Count -gt 0) {
            $matched = @($RequiredAnyColumns | Where-Object { $headerIndex.ContainsKey($_) })
            if ($matched.Count -eq 0) { throw "$Label is missing a required CSV column ($($RequiredAnyColumns -join ', ')): $Path" }
        }

        while (-not $parser.EndOfData) {
            try {
                $fields = @($parser.ReadFields())
            }
            catch [Microsoft.VisualBasic.FileIO.MalformedLineException] {
                throw "$Label has malformed CSV quoting near line $($parser.ErrorLineNumber): $Path"
            }
            if ($fields.Count -ne $headers.Count) {
                throw "$Label row $($parser.LineNumber) does not match the CSV header width: $Path"
            }
            if (@($fields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) { continue }

            $record = [ordered]@{}
            for ($i = 0; $i -lt $headers.Count; $i++) { $record[$headers[$i]] = ([string]$fields[$i]).Trim() }
            [pscustomobject]$record
        }
    }
    finally {
        $parser.Close()
        $parser.Dispose()
    }
}

function Test-OutOfScope {
    param($ProbeRow, $IdentityRow, $LocationRow)
    foreach ($row in @($ProbeRow, $IdentityRow)) {
        $scope = Get-RowValue -Row $row -Names @('Scope', 'SurveyScope', 'Disposition')
        if ($scope.Trim().ToLowerInvariant() -in @('outofscope', 'out_of_scope', 'out-of-scope')) { return $true }
    }
    $allowed = Get-RowValue -Row $LocationRow -Names @('SurveyAllowed', 'Allowed')
    if ($allowed -and -not (Test-IsTruthy $allowed)) { return $true }
    return $false
}

function New-ReductionRow {
    param($ProbeRow, [string]$Status, [string]$StatusReason, $Policy, $IdentityRow, $LocationRow)
    $source = Get-RowValue -Row $ProbeRow -Names @('SourceEvidence', 'EvidencePath', 'EvidenceSource', 'SourceFile')
    if (-not $source) { $source = 'prior_probe_results_csv' }
    $subnet = if ($null -ne $LocationRow) { Get-RowValue -Row $LocationRow -Names @('SubnetCIDR', 'Subnet', 'CIDR') } else { '' }
    if (-not $subnet) { $subnet = Get-RowValue -Row $ProbeRow -Names @('SubnetCIDR', 'Subnet', 'CIDR') }
    return [pscustomobject]@{
        Target = Get-TargetFromRow $ProbeRow
        Serial = Get-SerialFromRow $ProbeRow
        Site = Get-SiteFromRow $ProbeRow
        Location = Get-LocationFromRow $ProbeRow
        SubnetCIDR = $subnet
        Status = $Status
        StatusReason = $StatusReason
        ReachabilityEvidence = Get-ReachabilityText $ProbeRow
        IdentityEvidence = Get-IdentityText -ProbeRow $ProbeRow -IdentityRow $IdentityRow
        LowNoisePolicyVersion = $Policy.PolicyVersion
        LowNoiseDisposition = $Status
        ProbeAgainGuidance = $Policy.ProbeAgainGuidance
        FreshEvidenceGuidance = $Policy.FreshEvidenceGuidance
        NetworkVisibilityNote = $Policy.NetworkVisibilityNote
        NetworkActivityPerformed = 'false'
        SourceEvidence = $source
    }
}

function New-LocationCandidateRow {
    param($ProbeRow, $LocationRow)
    return [pscustomobject]@{
        Site = Get-SiteFromRow $LocationRow
        Location = Get-LocationFromRow $LocationRow
        Building = Get-RowValue -Row $LocationRow -Names @('Building')
        Floor = Get-RowValue -Row $LocationRow -Names @('Floor')
        SubnetCIDR = Get-RowValue -Row $LocationRow -Names @('SubnetCIDR', 'Subnet', 'CIDR')
        Gateway = Get-RowValue -Row $LocationRow -Names @('Gateway')
        Target = Get-TargetFromRow $ProbeRow
        Status = 'DeferredSubnetCandidate'
        StatusReason = 'local location map suggests a bounded candidate; this is not identity proof'
        SourceEvidence = Get-RowValue -Row $LocationRow -Names @('SourceEvidence', 'EvidencePath', 'EvidenceSource')
        LastVerified = Get-RowValue -Row $LocationRow -Names @('LastVerified')
        SurveyAllowed = Get-RowValue -Row $LocationRow -Names @('SurveyAllowed', 'Allowed')
        Confidence = Get-RowValue -Row $LocationRow -Names @('Confidence')
        Notes = Get-RowValue -Row $LocationRow -Names @('Notes')
        NetworkActivityPerformed = 'false'
    }
}

function Export-SasCsvAlways {
    param($Rows, [string]$Path, [string[]]$Columns)
    $rowArray = @($Rows | ForEach-Object { $_ })
    if ($rowArray.Count -gt 0) { $rowArray | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8; return }
    Set-Content -LiteralPath $Path -Value (($Columns | ForEach-Object { '"{0}"' -f $_ }) -join ',') -Encoding UTF8
}

$repoRoot = Get-SasRepoRoot -StartPath $PSScriptRoot
$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot
$resolvedRunId = New-SafeRunId -Candidate $RunId

Assert-SasApprovedInputPath -Path $PriorProbeResults -RepoRoot $repoRoot -Role 'prior evidence CSV' -AllowStaging -AllowGenerated -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput
if ($LocationSubnetMap) { Assert-SasApprovedInputPath -Path $LocationSubnetMap -RepoRoot $repoRoot -Role 'location map CSV' -AllowStaging -AllowGenerated -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput }
if ($IdentityEvidence) { Assert-SasApprovedInputPath -Path $IdentityEvidence -RepoRoot $repoRoot -Role 'identity evidence CSV' -AllowStaging -AllowGenerated -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput }

if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Join-Path $roots.OutputRoots[0] 'target_reduction') $resolvedRunId }
Assert-SasApprovedOutputPath -Path $OutputDirectory -RepoRoot $repoRoot -Role 'target reduction output directory'

$priorPath = (Resolve-Path -LiteralPath $PriorProbeResults).Path
$priorRows = @(Import-SasPlannerCsv -Path $priorPath -Label 'prior evidence CSV' -RequiredAnyColumns $targetFields)
if ($priorRows.Count -eq 0) { throw 'Prior evidence CSV had no rows.' }

$identityRows = if ($IdentityEvidence) { @(Import-SasPlannerCsv -Path (Resolve-Path -LiteralPath $IdentityEvidence).Path -Label 'identity evidence CSV' -RequiredAnyColumns @($targetFields + $serialFields)) } else { @() }
$identityIndex = New-IdentityIndex -Rows $identityRows
$locationRows = if ($LocationSubnetMap) { @(Import-SasPlannerCsv -Path (Resolve-Path -LiteralPath $LocationSubnetMap).Path -Label 'location map CSV' -RequiredColumns @('Site') -RequiredAnyColumns $locationFields) } else { @() }
$locationIndex = New-LocationIndex -Rows $locationRows
$policy = Get-SasLowNoisePolicy
$targetCounts = @{}
foreach ($row in $priorRows) {
    $targetKey = ConvertTo-NormalizedKey (Get-TargetFromRow $row)
    if (-not $targetKey) { continue }
    if (-not $targetCounts.ContainsKey($targetKey)) { $targetCounts[$targetKey] = 0 }
    $targetCounts[$targetKey]++
}

$reduced = New-Object System.Collections.Generic.List[object]
$retry = New-Object System.Collections.Generic.List[object]
$review = New-Object System.Collections.Generic.List[object]
$locationCandidates = New-Object System.Collections.Generic.List[object]
$outOfScope = New-Object System.Collections.Generic.List[object]

foreach ($row in $priorRows) {
    $target = Get-TargetFromRow $row
    $serial = Get-SerialFromRow $row
    $locKey = Get-LocationKey -Site (Get-SiteFromRow $row) -Location (Get-LocationFromRow $row)
    $locationRow = if ($locationIndex.ContainsKey($locKey)) { $locationIndex[$locKey] } else { $null }
    $identityRow = Get-IdentityRow -Target $target -Serial $serial -Index $identityIndex

    if (Test-OutOfScope -ProbeRow $row -IdentityRow $identityRow -LocationRow $locationRow) {
        $outRow = New-ReductionRow -ProbeRow $row -Status 'OutOfScope' -StatusReason 'outside approved survey scope' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow
        $outOfScope.Add($outRow)
        continue
    }
    if (-not $target) {
        $surveyAllowed = Get-RowValue -Row $locationRow -Names @('SurveyAllowed', 'Allowed')
        if ($null -ne $locationRow -and (Test-IsTruthy $surveyAllowed)) { $locationCandidates.Add((New-LocationCandidateRow -ProbeRow $row -LocationRow $locationRow)) }
        $review.Add((New-ReductionRow -ProbeRow $row -Status 'ReviewRequired' -StatusReason 'missing or conflicting identity evidence' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow))
        continue
    }
    $targetKey = ConvertTo-NormalizedKey $target
    if ($targetCounts[$targetKey] -gt 1) {
        $review.Add((New-ReductionRow -ProbeRow $row -Status 'ReviewRequired' -StatusReason 'duplicate or case-variant target rows require review' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow))
        continue
    }
    if (Test-IdentityReviewRequired -ProbeRow $row -IdentityRow $identityRow) {
        $review.Add((New-ReductionRow -ProbeRow $row -Status 'ReviewRequired' -StatusReason 'missing or conflicting identity evidence' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow))
        continue
    }
    if (Test-IsReached $row) {
        $reduced.Add((New-ReductionRow -ProbeRow $row -Status 'ConfirmedReached' -StatusReason 'prior local reachability evidence exists; this is not identity proof' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow))
        continue
    }
    if (Test-IsRetrySignal $row) {
        $retry.Add((New-ReductionRow -ProbeRow $row -Status 'RetryCandidate' -StatusReason 'negative local evidence is not proof the device is gone' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow))
    } else {
        $review.Add((New-ReductionRow -ProbeRow $row -Status 'ReviewRequired' -StatusReason 'ambiguous local evidence requires review' -Policy $policy -IdentityRow $identityRow -LocationRow $locationRow))
    }
}

$classifiedRowCount = $reduced.Count + $retry.Count + $review.Count + $outOfScope.Count
if ($classifiedRowCount -ne $priorRows.Count) {
    throw "target reduction classification count mismatch: input=$($priorRows.Count) classified=$classifiedRowCount"
}

$reducedPath = Join-Path $OutputDirectory 'reduced_targets.csv'
$retryPath = Join-Path $OutputDirectory 'retry_candidates.csv'
$reviewPath = Join-Path $OutputDirectory 'review_required.csv'
$outOfScopePath = Join-Path $OutputDirectory 'out_of_scope.csv'
$locationPath = Join-Path $OutputDirectory 'location_subnet_candidates.csv'
$summaryPath = Join-Path $OutputDirectory 'target_reduction_summary.json'
$handoffPath = Join-Path $OutputDirectory 'operator_handoff.txt'

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Export-SasCsvAlways -Rows $reduced -Path $reducedPath -Columns $reductionColumns
Export-SasCsvAlways -Rows $retry -Path $retryPath -Columns $reductionColumns
Export-SasCsvAlways -Rows $review -Path $reviewPath -Columns $reductionColumns
Export-SasCsvAlways -Rows $outOfScope -Path $outOfScopePath -Columns $reductionColumns
Export-SasCsvAlways -Rows $locationCandidates -Path $locationPath -Columns $locationColumns

$summary = New-SasLowNoiseSummaryObject -Properties @{
    workflow_id = 'target_reduction'
    operation_id = 'target_reduction.plan'
    run_id = $resolvedRunId
    generated_at = (Get-Date).ToString('o')
    prior_probe_results_csv = $priorPath
    input_row_count = $priorRows.Count
    classified_row_count = $classifiedRowCount
    classification_reconciled = $true
    confirmed_reached_count = $reduced.Count
    retry_candidate_count = $retry.Count
    review_required_count = $review.Count
    deferred_subnet_candidate_count = $locationCandidates.Count
    out_of_scope_count = $outOfScope.Count
    required_statuses = @('ConfirmedReached', 'RetryCandidate', 'ReviewRequired', 'DeferredSubnetCandidate', 'OutOfScope')
    reduced_targets_csv = $reducedPath
    retry_candidates_csv = $retryPath
    review_required_csv = $reviewPath
    out_of_scope_csv = $outOfScopePath
    location_subnet_candidates_csv = $locationPath
    target_reduction_summary_json = $summaryPath
    operator_handoff_path = $handoffPath
    network_activity_performed = $false
    target_mutation_performed = $false
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

@(
    'SysAdminSuite target reduction handoff',
    "RunId: $resolvedRunId",
    'Operation: target_reduction.plan',
    "Rows consumed: $($priorRows.Count)",
    "Confirmed reached: $($reduced.Count)",
    "Retry candidates: $($retry.Count)",
    "Review required: $($review.Count)",
    "Deferred subnet candidates: $($locationCandidates.Count)",
    "Out of scope: $($outOfScope.Count)",
    '',
    'Artifacts:',
    "- $reducedPath",
    "- $retryPath",
    "- $reviewPath",
    "- $outOfScopePath",
    "- $locationPath",
    "- $summaryPath",
    "- $handoffPath",
    '',
    'Planner network activity performed: false',
    'Target mutation performed: false',
    'Next action: review retry, review, and out-of-scope queues before any follow-up action.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Target reduction plan complete: $resolvedRunId"
Write-Host "Confirmed reached: $($reduced.Count)"
Write-Host "Retry candidates: $($retry.Count)"
Write-Host "Review required: $($review.Count)"
Write-Host "Deferred subnet candidates: $($locationCandidates.Count)"
Write-Host "Out of scope: $($outOfScope.Count)"
Write-Host "Summary: $summaryPath"
