[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Location).Path
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $script:checks.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
}

function Test-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
}

Write-Host 'SYSADMIN HARNESS VALIDATION'

$required = @(
    'Run-HarnessContracts.cmd',
    'Run-HarnessValidation.cmd',
    'Run-EnglishReportFixture.cmd',
    'Run-ExportHarnessEvidence.cmd',
    'scripts/run-harness-validation.sh',
    'scripts/render-english-report-fixtures.sh',
    'scripts/show-harness-evidence-paths.sh',
    'scripts/Render-SasEnglishReport.ps1',
    'Tests/bash/run_harness_contracts.sh',
    'Tests/bash/test_harness_command_surface.sh',
    'schemas/harness/run-event.schema.json',
    'schemas/harness/artifact-registry.schema.json',
    'schemas/harness/operator-report.schema.json',
    'survey/fixtures/english-log/serial_preflight_summary.sample.json',
    'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json',
    'survey/fixtures/english-log/network_preflight_summary.sample.json',
    'survey/fixtures/english-log/network_preflight_artifact_registry.sample.json',
    'survey/workflows/serial-to-preflight.yaml',
    'survey/workflows/network-preflight.yaml',
    'survey/workflows/serial-iteration.yaml'
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
Add-Check -Name 'required harness files' -Passed ($missing.Count -eq 0) -Detail (($missing -join ', '))

try {
    foreach ($schema in @('schemas/harness/run-event.schema.json', 'schemas/harness/artifact-registry.schema.json', 'schemas/harness/operator-report.schema.json')) {
        Test-JsonFile -Path $schema
    }
    Add-Check -Name 'schema parse' -Passed $true -Detail 'schemas parsed'
}
catch {
    Add-Check -Name 'schema parse' -Passed $false -Detail $_.Exception.Message
}

try {
    $serial = Get-Content -LiteralPath 'survey/fixtures/english-log/serial_preflight_summary.sample.json' -Raw | ConvertFrom-Json
    $network = Get-Content -LiteralPath 'survey/fixtures/english-log/network_preflight_summary.sample.json' -Raw | ConvertFrom-Json
    $needed = @('workflow_id', 'run_id', 'request_summary', 'network_activity_performed', 'low_noise_policy_version', 'next_action')
    $missingVars = @()
    foreach ($item in @($serial, $network)) {
        foreach ($name in $needed) {
            if (@($item.PSObject.Properties.Name) -notcontains $name) { $missingVars += $name }
        }
    }
    Add-Check -Name 'fixture required variables' -Passed ($missingVars.Count -eq 0) -Detail (($missingVars | Select-Object -Unique) -join ', ')
}
catch {
    Add-Check -Name 'fixture required variables' -Passed $false -Detail $_.Exception.Message
}

$outRoot = 'survey/output/harness-validator'
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$serialReport = Join-Path $outRoot 'serial_preflight_report.md'
$networkReport = Join-Path $outRoot 'network_preflight_report.md'

try {
    & 'scripts/Render-SasEnglishReport.ps1' -SummaryJson 'survey/fixtures/english-log/serial_preflight_summary.sample.json' -ArtifactRegistry 'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json' -Template 'serial-preflight' -OutputPath $serialReport | Out-Null
    Add-Check -Name 'serial report render' -Passed (Test-Path -LiteralPath $serialReport) -Detail $serialReport
}
catch {
    Add-Check -Name 'serial report render' -Passed $false -Detail $_.Exception.Message
}

try {
    & 'scripts/Render-SasEnglishReport.ps1' -SummaryJson 'survey/fixtures/english-log/network_preflight_summary.sample.json' -ArtifactRegistry 'survey/fixtures/english-log/network_preflight_artifact_registry.sample.json' -Template 'network-preflight' -OutputPath $networkReport | Out-Null
    Add-Check -Name 'network report render' -Passed (Test-Path -LiteralPath $networkReport) -Detail $networkReport
}
catch {
    Add-Check -Name 'network report render' -Passed $false -Detail $_.Exception.Message
}

try {
    $serialText = Get-Content -LiteralPath $serialReport -Raw
    $networkText = Get-Content -LiteralPath $networkReport -Raw
    $ok = $serialText -match 'planner did not perform network activity' -and $networkText -match 'network activity occurred'
    Add-Check -Name 'network activity classification' -Passed $ok -Detail 'serial false, network true'
}
catch {
    Add-Check -Name 'network activity classification' -Passed $false -Detail $_.Exception.Message
}

try {
    $combined = ((Get-Content -LiteralPath $serialReport -Raw), (Get-Content -LiteralPath $networkReport -Raw)) -join "`n"
    $ok = $combined -match 'Low-noise context' -and $combined -match 'Next action'
    Add-Check -Name 'low-noise guidance' -Passed $ok -Detail 'reports include required sections'
}
catch {
    Add-Check -Name 'low-noise guidance' -Passed $false -Detail $_.Exception.Message
}

try {
    $fixtureText = Get-ChildItem -LiteralPath 'survey/fixtures/english-log' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
    $joined = $fixtureText -join "`n"
    $bad = $joined -match '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' -or $joined -match '\b(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)' -or $joined -match '\b(WMH|WNH|CYB)[A-Za-z0-9-]+'
    Add-Check -Name 'live-data fixture guard' -Passed (-not $bad) -Detail 'synthetic fixture scan'
}
catch {
    Add-Check -Name 'live-data fixture guard' -Passed $false -Detail $_.Exception.Message
}

try {
    $wrapperRoutes = @{
        'Run-HarnessContracts.cmd' = 'Tests/bash/run_harness_contracts.sh'
        'Run-HarnessValidation.cmd' = 'scripts/run-harness-validation.sh'
        'Run-EnglishReportFixture.cmd' = 'scripts/render-english-report-fixtures.sh'
        'Run-ExportHarnessEvidence.cmd' = 'scripts/show-harness-evidence-paths.sh'
    }
    $wrapperFailures = @()
    foreach ($wrapper in $wrapperRoutes.Keys) {
        if (-not (Test-Path -LiteralPath $wrapper)) {
            $wrapperFailures += "$wrapper missing"
            continue
        }
        $text = Get-Content -LiteralPath $wrapper -Raw
        if ($text -notmatch [regex]::Escape($wrapperRoutes[$wrapper])) {
            $wrapperFailures += "$wrapper missing route to $($wrapperRoutes[$wrapper])"
        }
        if ($text -notmatch 'exit /b %SAS_EXIT%') {
            $wrapperFailures += "$wrapper does not preserve exit code"
        }
    }
    Add-Check -Name 'command surface wrappers' -Passed ($wrapperFailures.Count -eq 0) -Detail (($wrapperFailures -join '; '))
}
catch {
    Add-Check -Name 'command surface wrappers' -Passed $false -Detail $_.Exception.Message
}

try {
    $scriptRoutes = @{
        'scripts/run-harness-validation.sh' = 'scripts/validate-sysadmin-harness.ps1'
        'scripts/render-english-report-fixtures.sh' = 'scripts/Render-SasEnglishReport.ps1'
        'scripts/show-harness-evidence-paths.sh' = 'docs/evidence/latest/README.md'
    }
    $scriptFailures = @()
    foreach ($script in $scriptRoutes.Keys) {
        if (-not (Test-Path -LiteralPath $script)) {
            $scriptFailures += "$script missing"
            continue
        }
        $text = Get-Content -LiteralPath $script -Raw
        if ($text -notmatch [regex]::Escape($scriptRoutes[$script])) {
            $scriptFailures += "$script missing route to $($scriptRoutes[$script])"
        }
    }
    Add-Check -Name 'command surface scripts' -Passed ($scriptFailures.Count -eq 0) -Detail (($scriptFailures -join '; '))
}
catch {
    Add-Check -Name 'command surface scripts' -Passed $false -Detail $_.Exception.Message
}

$passed = 0
foreach ($check in $checks) {
    if ($check.Passed) {
        $passed++
        Write-Host "[PASS] $($check.Name)"
    }
    else {
        Write-Host "[FAIL] $($check.Name) - $($check.Detail)"
    }
}

Write-Host ""
Write-Host "Result: $passed/$($checks.Count) passed"

if ($passed -ne $checks.Count) {
    exit 1
}
