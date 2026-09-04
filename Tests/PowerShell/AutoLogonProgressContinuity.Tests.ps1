#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'scripts\SasAutoLogonProgress.psm1'
Import-Module $modulePath -Force

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition,[Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-VisibleStageNumbers {
    param([Parameter(Mandatory = $true)][object[]]$Lines)
    $numbers = New-Object 'System.Collections.Generic.List[int]'
    foreach ($line in $Lines) {
        $match = [regex]::Match([string]$line, '^\[(?<stage>\d{1,2})/22\]\s+')
        if ($match.Success) { [void]$numbers.Add([int]$match.Groups['stage'].Value) }
    }
    return @($numbers)
}

function Assert-NoForwardGap {
    param([Parameter(Mandatory = $true)][object[]]$Lines)
    $numbers = @(Get-VisibleStageNumbers -Lines $Lines)
    $last = 0
    foreach ($number in $numbers) {
        if ($number -gt $last) {
            Assert-True -Condition (($number - $last) -le 1) -Message "Forward progress gap remained visible: $last -> $number"
            $last = $number
        }
    }
}

$createFailureShape = @(
    '[8/22] staging/hash verification: PASS',
    '[9/22] Probe task create: START',
    '[9/22] Probe task: FAIL - synthetic create timeout',
    '[11/22] Probe result: FAIL - synthetic legacy failure attribution',
    '[12/22] Probe cleanup: START'
)
$normalizedCreateFailure = @($createFailureShape | ConvertTo-SasAutoLogonContiguousProgress)
Assert-NoForwardGap -Lines $normalizedCreateFailure
Assert-True -Condition (@($normalizedCreateFailure | Where-Object { [string]$_ -match '^\[10/22\] Probe task run: SKIP ' }).Count -eq 1) -Message 'The missing Probe task-run stage was not rendered exactly once.'

$outerFailureShape = @(
    '[7/22] source hash: PASS',
    '[8/22] staging/hash verification: START',
    '[18/22] staging cleanup: START'
)
$normalizedOuterFailure = @($outerFailureShape | ConvertTo-SasAutoLogonContiguousProgress)
Assert-NoForwardGap -Lines $normalizedOuterFailure
foreach ($expected in 9..17) {
    Assert-True -Condition (@(Get-VisibleStageNumbers -Lines $normalizedOuterFailure) -contains $expected) -Message "Missing synthesized stage $expected before staging cleanup."
}

$healthyShape = @(
    '[8/22] staging/hash verification: PASS',
    '[9/22] Probe task create: START',
    '[9/22] Probe task create: PASS',
    '[10/22] Probe task run: START',
    '[10/22] Probe task run: PASS',
    '[11/22] Probe result: START',
    '[11/22] Probe result: PASS'
)
$normalizedHealthy = @($healthyShape | ConvertTo-SasAutoLogonContiguousProgress)
Assert-NoForwardGap -Lines $normalizedHealthy
Assert-True -Condition ($normalizedHealthy.Count -eq $healthyShape.Count) -Message 'Healthy contiguous output was unexpectedly expanded.'
for ($i = 0; $i -lt $healthyShape.Count; $i++) {
    Assert-True -Condition ([string]$normalizedHealthy[$i] -eq [string]$healthyShape[$i]) -Message "Healthy output changed at index $i."
}

Write-Host 'PASS: AutoLogon operator-facing progress cannot jump forward across an unrendered numbered stage.' -ForegroundColor Green
