#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repairScript = Join-Path $repoRoot 'scripts\Repair-SasAutoLogonS4UPathBudgetRuntime.ps1'
if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) {
    throw "Repair script missing: $repairScript"
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Parse {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $errors | Format-List * | Out-Host
        throw "PowerShell parse failed: $Path"
    }
}

function New-RepairFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$NewLine
    )
    $scripts = Join-Path $Root 'scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null

    $transportLines = @(
        '#Requires -Version 5.1',
        'param([string]$OutputRoot)',
        '$repoRoot = Split-Path -Parent $PSScriptRoot',
        '$runContextModulePath = Join-Path $PSScriptRoot ''SasRunContext.psm1''',
        'function Assert-SasLocalOutputRoot { param([string]$OutputRoot,[string]$RepoRoot) }',
        'Import-Module $runContextModulePath -Force',
        '$context = [pscustomobject]@{ run_root = ''fixture''; artifact_registry_path = ''fixture-registry'' }',
        '$context | Add-Member -NotePropertyName directories -NotePropertyValue ([pscustomobject]@{})',
        '$resultPath = ''fixture-result''',
        '$networkActivity = $false',
        '$output = [pscustomobject]@{',
        '    run_root = $context.run_root',
        '    result_path = $resultPath',
        '    artifact_registry_path = $context.artifact_registry_path',
        '    result = $null',
        '}',
        '$output'
    )

    $statusLines = @(
        '#Requires -Version 5.1',
        '$repoRoot = Split-Path -Parent $PSScriptRoot',
        '$s4uRoot = $PSScriptRoot',
        'function Test-SasLocalArtifact { param([string]$RelativePath) return $false }',
        '$allFiles = @(Get-ChildItem -LiteralPath $s4uRoot -File -Recurse -ErrorAction SilentlyContinue)',
        '$preflightResult = $allFiles | Where-Object { $_.Name -eq ''software_deployment_transport_result.json'' } | Select-Object -First 1',
        '[pscustomobject]@{',
        '    preflight_result_present = ($null -ne $preflightResult)',
        '    network_activity_performed_by_observer = $false',
        '    target_contact_performed_by_observer = $false',
        '    target_mutation_performed_by_observer = $false',
        '}'
    )

    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        (Join-Path $scripts 'Test-SasSoftwareDeploymentTransport.ps1'),
        ($transportLines -join $NewLine) + $NewLine,
        $encoding
    )
    [IO.File]::WriteAllText(
        (Join-Path $scripts 'Get-SasAutoLogonS4URunStatus.ps1'),
        ($statusLines -join $NewLine) + $NewLine,
        $encoding
    )
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-s4u-path-repair-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    foreach ($case in @(
        [pscustomobject]@{ name='crlf'; newline="`r`n" },
        [pscustomobject]@{ name='lf'; newline="`n" }
    )) {
        $runtime = Join-Path $tempRoot $case.name
        New-RepairFixture -Root $runtime -NewLine $case.newline
        $evidence = Join-Path $runtime 'evidence'

        $result = & $repairScript -RuntimeRoot $runtime -EvidenceRoot $evidence -ConfirmRepair -PassThru
        Assert-True ([string]$result.classification -eq 'AUTOLOGON_S4U_PATH_BUDGET_RUNTIME_REPAIR_APPLIED') `
            "Unexpected first repair classification for $($case.name): $($result.classification)"
        Assert-True (-not [bool]$result.git_performed) 'Repair must not invoke Git.'
        Assert-True (-not [bool]$result.network_activity_performed) 'Repair must not perform network activity.'
        Assert-True (-not [bool]$result.target_contact_performed) 'Repair must not contact a target.'
        Assert-True (-not [bool]$result.target_mutation_performed) 'Repair must not mutate a target.'

        $transport = Join-Path $runtime 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
        $status = Join-Path $runtime 'scripts\Get-SasAutoLogonS4URunStatus.ps1'
        $transportText = [IO.File]::ReadAllText($transport)
        $statusText = [IO.File]::ReadAllText($status)

        foreach ($marker in @(
            '$transportWindowsPathBudget = 240',
            'TRANSPORT_OUTPUT_ROOT_COMPACTED',
            'transport_preflight_link.json',
            'sas-software-deployment-transport-link/v1'
        )) {
            Assert-True ($transportText.Contains($marker)) "Missing transport marker after $($case.name) repair: $marker"
        }
        foreach ($marker in @(
            'Test-SasStatusPathUnderRoot',
            '$preflightLinkFile =',
            'preflight_link_valid = $preflightLinkValid'
        )) {
            Assert-True ($statusText.Contains($marker)) "Missing status marker after $($case.name) repair: $marker"
        }

        Assert-Parse -Path $transport
        Assert-Parse -Path $status

        $second = & $repairScript -RuntimeRoot $runtime -EvidenceRoot (Join-Path $runtime 'evidence-second') -ConfirmRepair -PassThru
        Assert-True ([string]$second.classification -eq 'AUTOLOGON_S4U_PATH_BUDGET_RUNTIME_REPAIR_ALREADY_PRESENT') `
            "Repair is not idempotent for $($case.name): $($second.classification)"

        Write-Host "PASS: $($case.name) runtime repair and idempotence"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'PASS: AutoLogon S4U path-budget runtime repair contracts'
