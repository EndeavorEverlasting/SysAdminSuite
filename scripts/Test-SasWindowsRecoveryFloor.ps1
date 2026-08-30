[CmdletBinding()]
param(
    [ValidateSet('All', 'Contracts', 'Behavior')]
    [string]$Phase = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$commonModule = Join-Path $repoRoot 'recovery/windows/SasWindowsRecovery.Common.psm1'
Import-Module $commonModule -Force

function Write-CapturedOutput {
    param([Parameter(Mandatory)]$Capture)
    foreach ($line in @($Capture.output)) { Write-Host $line }
}

function Assert-ExitCode {
    param(
        [Parameter(Mandatory)][int]$Expected,
        [Parameter(Mandatory)][int]$Actual,
        [Parameter(Mandatory)][string]$Label
    )
    if ($Expected -ne $Actual) {
        throw "$Label returned exit code $Actual; expected $Expected."
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { throw 'git is required to identify the exact tested candidate.' }
$shaResult = Invoke-SasNativeCapture -FilePath $git.Source -ArgumentList @('-C', $repoRoot, 'rev-parse', 'HEAD')
Assert-ExitCode -Expected 0 -Actual $shaResult.exit_code -Label 'git rev-parse HEAD'
$candidateSha = (@($shaResult.output) | Select-Object -Last 1).Trim()
if ($candidateSha -notmatch '^[0-9a-fA-F]{40}$') { throw "Invalid candidate SHA: '$candidateSha'" }
Write-Host "CANDIDATE_SHA=$candidateSha"
Write-Host "TEST_PHASE=$Phase"

if ($Phase -in @('All', 'Contracts')) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) { $pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $pythonCommand) { throw 'Python is required for the Windows recovery contract floor.' }

    $contractPaths = @(
        (Join-Path $repoRoot 'Tests/recovery/test_windows_workstation_recovery_contracts.py'),
        (Join-Path $repoRoot 'Tests/recovery/test_winre_qrfy_transition_contracts.py')
    )
    $pytestArguments = @('-m', 'pytest', '-q') + $contractPaths
    $pytest = Invoke-SasNativeCapture -FilePath $pythonCommand.Source -ArgumentList $pytestArguments
    Write-CapturedOutput -Capture $pytest
    Assert-ExitCode -Expected 0 -Actual $pytest.exit_code -Label 'pytest recovery contracts'
}

if ($Phase -in @('All', 'Behavior')) {
    $parsePaths = @(
        'recovery/windows/SasWindowsRecovery.Common.psm1',
        'recovery/windows/Get-SasWindowsRecoveryEvidence.ps1',
        'recovery/windows/Test-SasDismActivity.ps1',
        'recovery/windows/Repair-SasWindowsIntegrity.ps1',
        'Tests/recovery/Test-WindowsRecoveryBehavior.ps1',
        'scripts/Test-SasWindowsRecoveryFloor.ps1'
    )
    foreach ($relativePath in $parsePaths) {
        $path = Join-Path $repoRoot $relativePath
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        if (@($errors).Count -ne 0) {
            $message = ($errors | ForEach-Object { $_.Message }) -join '; '
            throw "PowerShell parse failed for ${relativePath}: $message"
        }
    }

    & (Join-Path $repoRoot 'Tests/recovery/Test-WindowsRecoveryBehavior.ps1')

    $engine = (Get-Process -Id $PID).Path
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Unable to resolve the active PowerShell executable.' }

    $collector = Join-Path $repoRoot 'recovery/windows/Get-SasWindowsRecoveryEvidence.ps1'
    $fixture = Join-Path $repoRoot 'Tests/Fixtures/windows-recovery/healthy.json'
    $fixtureRun = Invoke-SasNativeCapture -FilePath $engine -ArgumentList @('-NoProfile', '-File', $collector, '-FixturePath', $fixture)
    Write-CapturedOutput -Capture $fixtureRun
    Assert-ExitCode -Expected 0 -Actual $fixtureRun.exit_code -Label 'sanitized collector fixture'
    $fixtureJson = (@($fixtureRun.output) -join [Environment]::NewLine) | ConvertFrom-Json
    if ($fixtureJson.schema_version -ne '1.0') { throw 'Collector fixture returned an unexpected schema version.' }
    if ($fixtureJson.proof.destructive_actions_performed -ne $false) { throw 'Collector fixture must remain read-only evidence.' }

    $repair = Join-Path $repoRoot 'recovery/windows/Repair-SasWindowsIntegrity.ps1'
    $planRun = Invoke-SasNativeCapture -FilePath $engine -ArgumentList @('-NoProfile', '-File', $repair)
    Write-CapturedOutput -Capture $planRun
    Assert-ExitCode -Expected 0 -Actual $planRun.exit_code -Label 'repair plan-only gate'
    $planJson = (@($planRun.output) -join [Environment]::NewLine) | ConvertFrom-Json
    if ($planJson.status -ne 'plan_only') { throw 'Repair script must default to plan_only.' }
    if ($planJson.mutation_performed -ne $false -or $planJson.network_access_attempted -ne $false) {
        throw 'Plan-only repair path must not mutate or access the network.'
    }

    $blockedReport = Join-Path ([IO.Path]::GetTempPath()) ("sas-windows-repair-blocked-{0}.json" -f [guid]::NewGuid().ToString('N'))
    try {
        $blockedRun = Invoke-SasNativeCapture -FilePath $engine -ArgumentList @('-NoProfile', '-File', $repair, '-Apply', '-ReportPath', $blockedReport)
        Write-CapturedOutput -Capture $blockedRun
        Assert-ExitCode -Expected 3 -Actual $blockedRun.exit_code -Label 'profile-gated repair apply'
        if (-not (Test-Path -LiteralPath $blockedReport -PathType Leaf)) { throw 'Blocked repair path did not persist its requested JSON report.' }
        $blockedJson = Get-Content -LiteralPath $blockedReport -Raw | ConvertFrom-Json
        if ($blockedJson.status -ne 'blocked_profile_authority_unavailable') { throw 'Repair apply did not fail closed on missing profile authority.' }
        if ($blockedJson.mutation_performed -ne $false -or $blockedJson.network_access_attempted -ne $false) {
            throw 'Blocked repair path must not mutate or access the network.'
        }
    }
    finally {
        Remove-Item -LiteralPath $blockedReport -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "WINDOWS_RECOVERY_TEST_FLOOR=PASS"
exit 0