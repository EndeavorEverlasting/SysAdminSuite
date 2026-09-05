#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'scripts\SasAutoLogonProgress.psm1'
$wrapperPath = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonWithContiguousProgress.ps1'
$cmdPath = Join-Path $repoRoot 'Run-AutoLogon-ContiguousProgress.cmd'
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
    $last = $null
    foreach ($number in $numbers) {
        if ($null -ne $last -and $number -gt $last) {
            Assert-True -Condition (($number - $last) -le 1) -Message "Forward progress gap remained visible: $last -> $number"
        }
        if ($null -eq $last -or $number -gt $last) {
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

# The double-click launcher must preserve the handoff instead of immediately disappearing. The
# explicit --no-pause switch remains available for automation while the saved exit code is returned.
$cmdText = Get-Content -LiteralPath $cmdPath -Raw -Encoding UTF8
foreach ($requiredMarker in @('pause','--no-pause','SAS_RC','AutoLogon command exit code')) {
    Assert-True -Condition ($cmdText -match [regex]::Escape($requiredMarker)) -Message "Operator CMD is missing required handoff marker: $requiredMarker"
}

# Execute the real wrapper against a fake launcher placed only at the canonical current-user install
# location. Never PATH-inject a launcher. If a real machine-wide launcher exists, skip this fixture
# rather than risk dispatching an actual field command from a developer workstation.
$machineLauncher = 'C:\ProgramData\SysAdminSuite\bin\sas.cmd'
if (-not (Test-Path -LiteralPath $machineLauncher -PathType Leaf)) {
    $fixtureRoot = Join-Path $env:TEMP ('sas-autologon-progress-' + [guid]::NewGuid().ToString('N'))
    $fixtureLocalAppData = Join-Path $fixtureRoot 'LocalAppData'
    $fixtureBin = Join-Path $fixtureLocalAppData 'SysAdminSuite\bin'
    New-Item -ItemType Directory -Path $fixtureBin -Force | Out-Null
    $fakeSas = Join-Path $fixtureBin 'sas.cmd'
    @'
@echo off
echo [8/22] staging/hash verification: PASS
echo [9/22] Probe task create: START
echo synthetic canonical stderr 1>&2
echo [9/22] Probe task: FAIL - synthetic create timeout
echo [11/22] Probe result: FAIL - synthetic legacy failure attribution
echo [12/22] Probe cleanup: START
exit /b 37
'@ | Set-Content -LiteralPath $fakeSas -Encoding ASCII

    $originalLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $fixtureLocalAppData
        $powershellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $wrapperOutput = @(& $powershellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wrapperPath -ComputerName 'fixture.example.invalid' 2>&1)
        $wrapperExit = [int]$LASTEXITCODE
        Assert-True -Condition ($wrapperExit -eq 37) -Message "Wrapper failed to preserve canonical sas.cmd exit code 37; got $wrapperExit."
        Assert-NoForwardGap -Lines $wrapperOutput
        Assert-True -Condition (@($wrapperOutput | Where-Object { [string]$_ -match 'synthetic canonical stderr' }).Count -ge 1) -Message 'Canonical stderr disappeared instead of remaining visible presentation data.'
        $skipIndex = -1
        $laterIndex = -1
        for ($i = 0; $i -lt $wrapperOutput.Count; $i++) {
            if ([string]$wrapperOutput[$i] -match '^\[10/22\] Probe task run: SKIP ') { $skipIndex = $i }
            if ([string]$wrapperOutput[$i] -match '^\[11/22\] Probe result: FAIL ') { $laterIndex = $i }
        }
        Assert-True -Condition ($skipIndex -ge 0) -Message 'Operator wrapper did not emit the missing middle stage.'
        Assert-True -Condition ($laterIndex -gt $skipIndex) -Message 'Operator wrapper did not emit the missing stage before the later stage.'
    }
    finally {
        $env:LOCALAPPDATA = $originalLocalAppData
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'SKIP: wrapper fake-launcher fixture not executed because a real machine-wide sas.cmd is installed.' -ForegroundColor Yellow
}

# The fixture intentionally exercised a nonzero native child. Clear only the synthetic test process
# state after every assertion above has passed so the parent test runner sees this test itself as green.
$global:LASTEXITCODE = 0
Write-Host 'PASS: AutoLogon operator-facing progress cannot jump forward across an unrendered numbered stage, stderr/exit semantics are preserved, and the double-click handoff remains visible.' -ForegroundColor Green
