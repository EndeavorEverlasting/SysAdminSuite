#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string[]]$AdditionalRequiredPath = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'survey/output/harness-validator' }
elseif (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repoRoot $OutputRoot }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$checks = [Collections.Generic.List[object]]::new()
$dependencies = [ordered]@{}
$context = $null
$runId = 'harness-proof-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))

function Add-Check {
    param([ValidateSet('PASS','SKIP','FAIL')][string]$Status, [string]$Name, [string]$Detail = '', [bool]$Required = $true)
    $script:checks.Add([pscustomobject]@{ status=$Status; name=$Name; detail=$Detail; required=$Required })
}

function Find-Command {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

function Invoke-Offline {
    param([string]$FilePath, [string[]]$Arguments)
    $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    [pscustomobject]@{
        exit_code = $LASTEXITCODE
        detail = $(if ($output.Count) { $output[-1] } else { 'completed without console output' })
    }
}

function Find-Bash {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return Find-Command @('bash') }
    $candidates = [Collections.Generic.List[string]]::new()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        $candidates.Add((Join-Path $gitRoot 'bin/bash.exe'))
        $candidates.Add((Join-Path $gitRoot 'usr/bin/bash.exe'))
    }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Git/bin/bash.exe')) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash -and $bash.Source -notmatch '\\Windows\\(System32|SystemApps)|\\Microsoft\\WindowsApps\\') { return $bash.Source }
    return $null
}

function Test-Hooks {
    $failures = @()
    $preCommitPath = Join-Path $repoRoot '.githooks/pre-commit'
    $prePushPath = Join-Path $repoRoot '.githooks/pre-push'
    if (-not (Test-Path $preCommitPath) -or -not (Test-Path $prePushPath)) { return @('required hook missing') }
    $preCommit = Get-Content $preCommitPath -Raw
    $prePush = Get-Content $prePushPath -Raw
    foreach ($fragment in @('git diff --cached --name-only','survey/output/*','survey/artifacts/*','*.pcap','*.evtx')) {
        if (-not $preCommit.Contains($fragment)) { $failures += "pre-commit missing $fragment" }
    }
    foreach ($fragment in @('run_offline_survey_tests.sh','test_local_harness_contracts.py')) {
        if (-not $prePush.Contains($fragment)) { $failures += "pre-push missing $fragment" }
    }
    return $failures
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
Push-Location $repoRoot
try {
    $git = Find-Command @('git')
    $branchValue = if ($git) { & $git -C $repoRoot branch --show-current | Select-Object -First 1 } else { $null }
    $commitValue = if ($git) { & $git -C $repoRoot rev-parse HEAD | Select-Object -First 1 } else { $null }
    $branch = if ([string]::IsNullOrWhiteSpace([string]$branchValue)) { 'detached' } else { ([string]$branchValue).Trim() }
    $commit = if ([string]::IsNullOrWhiteSpace([string]$commitValue)) { 'unknown' } else { ([string]$commitValue).Trim() }
    $dependencies.git = $git

    $required = @(
        'AGENTS.md','CLAUDE.md','CODEBASE_MAP.md','scripts/validate-sysadmin-harness.ps1',
        'scripts/Invoke-SasHarnessContracts.ps1','scripts/SasRunContext.psm1','scripts/Render-SasEnglishReport.ps1',
        'schemas/harness/artifact-registry.schema.json','survey/fixtures/english-log/serial_preflight_summary.sample.json',
        'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json','survey/workflows/serial-to-preflight.yaml',
        'survey/workflows/network-preflight.yaml','survey/workflows/serial-iteration.yaml','harness/api/sas-harness-api.json',
        'mcp/local/servers.json','.githooks/pre-commit','.githooks/pre-push'
    ) + @($AdditionalRequiredPath)
    $missing = @($required | Where-Object { -not (Test-Path (Join-Path $repoRoot $_)) })
    if ($missing.Count) { Add-Check FAIL 'required files' ('missing_required_path: ' + ($missing -join ', ')) }
    else { Add-Check PASS 'required files' "$($required.Count) required paths present" }

    try {
        Import-Module (Join-Path $repoRoot 'scripts/SasRunContext.psm1') -Force
        $context = New-SasRunContext -WorkflowId 'harness-proof' -RunId $runId -RepoRoot $repoRoot -OutputRoot $OutputRoot -RequestSummary 'Synthetic offline one-command harness proof.' -SourceArtifact 'scripts/validate-sysadmin-harness.ps1' -CreatedBy 'validate-sysadmin-harness'
        $needed = @('request.json','context.json','plan.json','plan.md','artifact_registry.json','summary.json','operator_handoff.txt','actions','artifacts','evidence','reports','review')
        $missingRun = @($needed | Where-Object { -not (Test-Path (Join-Path $context.run_root $_)) })
        if ($missingRun.Count) { Add-Check FAIL 'run context' ('missing run paths: ' + ($missingRun -join ', ')) }
        else { Add-Check PASS 'run context' $context.run_root }
    } catch { Add-Check FAIL 'run context' $_.Exception.Message }

    if ($context) {
        try {
            [void](Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'source_fixture' -Path 'survey/fixtures/english-log/serial_preflight_summary.sample.json' -Tracked $true -LiveData $false -Generated $false -Description 'Synthetic summary fixture.' -CreatedBy 'validate-sysadmin-harness')
            $registry = Get-Content $context.artifact_registry_path -Raw | ConvertFrom-Json
            $entry = @($registry.artifacts)[0]
            $fields = @('role','path','tracked','contains_live_data','generated','description')
            $missingFields = @($fields | Where-Object { @($entry.PSObject.Properties.Name) -notcontains $_ })
            if ($missingFields.Count) { Add-Check FAIL 'artifact registry' ('missing fields: ' + ($missingFields -join ', ')) }
            else { Add-Check PASS 'artifact registry' 'canonical entry matches registry schema fields' }
        } catch { Add-Check FAIL 'artifact registry' $_.Exception.Message }
    } else { Add-Check FAIL 'artifact registry' 'run_context_unavailable' }

    try {
        $reportRoot = if ($context) { $context.directories.reports } else { $OutputRoot }
        $reportPath = Join-Path $reportRoot 'serial_preflight_report.md'
        & (Join-Path $repoRoot 'scripts/Render-SasEnglishReport.ps1') -SummaryJson (Join-Path $repoRoot 'survey/fixtures/english-log/serial_preflight_summary.sample.json') -ArtifactRegistry (Join-Path $repoRoot 'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json') -Template serial-preflight -OutputPath $reportPath | Out-Null
        $report = Get-Content $reportPath -Raw
        if ($report.Contains('Run identity') -and $report.Contains('Next action') -and $report.Contains('planner did not perform network activity')) {
            Add-Check PASS 'report renderer' $reportPath
            if ($context) {
                [void](Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role operator_report -Path $reportPath -Tracked $false -LiveData $false -Generated $true -Description 'Synthetic English report renderer proof.' -CreatedBy 'validate-sysadmin-harness')
            }
        }
        else { Add-Check FAIL 'report renderer' 'required synthetic sections missing' }
    } catch { Add-Check FAIL 'report renderer' $_.Exception.Message }

    try {
        $api = Get-Content (Join-Path $repoRoot 'harness/api/sas-harness-api.json') -Raw | ConvertFrom-Json
        $ids = @($api.operations | ForEach-Object id)
        $requiredIds = @('target_reduction.plan','standard_probe.render_cmd','standard_probe.render_powershell','report.generate_from_artifacts','mcp.catalog.list')
        $problems = @($requiredIds | Where-Object { $ids -notcontains $_ })
        $problems += @($ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
        $reduction = @($api.operations | Where-Object id -eq 'target_reduction.plan')[0]
        $problems += @('reduced_targets.csv','retry_candidates.csv','review_required.csv','out_of_scope.csv','location_subnet_candidates.csv','target_reduction_summary.json','operator_handoff.txt' | Where-Object { @($reduction.outputs) -notcontains $_ })
        $runner = Get-Content (Join-Path $repoRoot 'tests/survey/run_offline_survey_tests.sh') -Raw
        $problems += @('test_local_harness_contracts.py','test_run_context_contracts.py','test_target_reduction_plan_contracts.sh' | Where-Object { -not $runner.Contains($_) })
        foreach ($workflow in @('serial-to-preflight.yaml','network-preflight.yaml','serial-iteration.yaml')) {
            $text = Get-Content (Join-Path $repoRoot "survey/workflows/$workflow") -Raw
            if (-not $text.Contains('network_activity_policy:') -or -not $text.Contains('target_mutation_policy:')) { $problems += $workflow }
        }
        if ($problems.Count) { Add-Check FAIL 'cross-lane merge integrity' ('missing_or_duplicate_contract: ' + ($problems -join ', ')) }
        else { Add-Check PASS 'cross-lane merge integrity' 'workflow, API, target-reduction, and offline-runner contracts coexist' }
    } catch { Add-Check FAIL 'cross-lane merge integrity' $_.Exception.Message }

    $powershell = Find-Command @('pwsh','powershell.exe','powershell')
    $dependencies.powershell = $powershell
    if ($powershell) {
        $ai = Invoke-Offline $powershell @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $repoRoot 'tools/validate-ai-layer.ps1'))
        if ($ai.exit_code -eq 0) { Add-Check PASS 'AI layer validator' $ai.detail }
        else { Add-Check FAIL 'AI layer validator' "exit_$($ai.exit_code): $($ai.detail)" }
    } else { Add-Check FAIL 'AI layer validator' 'powershell_runtime_not_available' }

    $python = Find-Command @('python','python3')
    $dependencies.python = $python
    if ($python) {
        $version = Invoke-Offline $python @('--version')
        $dependencies.python_version = $version.detail
        $pythonFailures = @()
        foreach ($test in @('Tests/survey/test_local_harness_contracts.py','Tests/survey/test_run_context_contracts.py')) {
            $testResult = Invoke-Offline $python @((Join-Path $repoRoot $test))
            if ($testResult.exit_code -ne 0) { $pythonFailures += "$test exit_$($testResult.exit_code): $($testResult.detail)" }
        }
        if ($pythonFailures.Count) { Add-Check FAIL 'Python harness contracts' ($pythonFailures -join '; ') }
        else { Add-Check PASS 'Python harness contracts' $version.detail }
    } else { Add-Check FAIL 'Python harness contracts' 'python_runtime_not_available' }

    $compatTest = Join-Path $repoRoot 'Tests/survey/test_windows_log_classifier_code.py'
    if (Test-Path $compatTest) {
        if ($python) {
            $compat = Invoke-Offline $python @($compatTest)
            if ($compat.exit_code -eq 0) { Add-Check PASS 'optional Python module compatibility' $dependencies.python_version $false }
            else { Add-Check FAIL 'optional Python module compatibility' "exit_$($compat.exit_code): $($compat.detail)" $false }
        } else { Add-Check SKIP 'optional Python module compatibility' 'python_runtime_not_available' $false }
    } else { Add-Check SKIP 'optional Python module compatibility' 'windows_log_lane_not_present' $false }

    $bash = Find-Bash
    $dependencies.bash = $bash
    if ($bash) {
        $smoke = Invoke-Offline $bash @('-n',(Join-Path $repoRoot 'scripts/run-harness-validation.sh'),(Join-Path $repoRoot 'Tests/bash/test_sysadmin_harness_validator_contracts.sh'))
        if ($smoke.exit_code -eq 0) { Add-Check PASS 'optional Bash syntax smoke' $bash $false }
        else { Add-Check FAIL 'optional Bash syntax smoke' "exit_$($smoke.exit_code): $($smoke.detail)" $false }
    } else { Add-Check SKIP 'optional Bash syntax smoke' 'git_bash_not_available' $false }

    try {
        $catalog = Get-Content (Join-Path $repoRoot 'mcp/local/servers.json') -Raw | ConvertFrom-Json
        $safe = $catalog.posture.network_probe_execution_default -eq $false -and $catalog.posture.target_mutation_default -eq $false -and $catalog.posture.credential_collection_allowed -eq $false
        if ($safe) { Add-Check PASS 'MCP catalog posture' "$(@($catalog.servers).Count) local-only server definitions" }
        else { Add-Check FAIL 'MCP catalog posture' 'catalog safety posture incomplete' }
        Add-Check SKIP 'optional MCP symbol smoke' 'lsp_project_not_loaded' $false
    } catch {
        Add-Check FAIL 'MCP catalog posture' $_.Exception.Message
        Add-Check SKIP 'optional MCP symbol smoke' 'mcp_catalog_unavailable' $false
    }

    $hookProblems = @(Test-Hooks)
    if ($hookProblems.Count) { Add-Check FAIL 'hook hygiene' ($hookProblems -join '; ') }
    else { Add-Check PASS 'hook hygiene' 'artifact blocklist and offline pre-push checks present' }

    $passed = @($checks | Where-Object status -eq PASS).Count
    $skipped = @($checks | Where-Object status -eq SKIP).Count
    $failed = @($checks | Where-Object status -eq FAIL).Count
    $artifactRoot = if ($context) { $context.directories.reports } else { $OutputRoot }
    $matrixPath = Join-Path $artifactRoot 'harness_validation_matrix.txt'
    $jsonPath = Join-Path $artifactRoot 'harness_validation_result.json'
    $matrix = [Collections.Generic.List[string]]::new()
    $matrix.Add('APP HARNESS VALIDATION')
    $matrix.Add("Repo: $repoRoot")
    $matrix.Add("Branch: $branch")
    $matrix.Add("Commit: $commit")
    $matrix.Add('Proof: synthetic_offline (no runtime proof, network activity, launcher execution, or target mutation)')
    $matrix.Add('')
    foreach ($check in $checks) {
        $suffix = if ($check.detail) { " - $($check.detail)" } else { '' }
        $matrix.Add("[$($check.status)] $($check.name)$suffix")
    }
    $matrix.Add('')
    $matrix.Add("Result: $passed passed / $skipped skipped / $failed failed")
    $matrix.Add("JSON: $jsonPath")
    $result = [ordered]@{
        schema_version='sas-harness-proof/v1'; generated_at=(Get-Date).ToUniversalTime().ToString('o')
        repo_root=$repoRoot; branch=$branch; commit=$commit; proof_level='synthetic_offline'
        runtime_proof=$false; network_activity_performed=$false; launcher_execution_performed=$false
        target_mutation_performed=$false; data_mutation_performed=$false
        counts=[ordered]@{passed=$passed; skipped=$skipped; failed=$failed}
        dependencies=$dependencies; checks=@($checks)
        artifacts=[ordered]@{
            matrix=$matrixPath; json=$jsonPath
            run_root=$(if ($context) {$context.run_root} else {$null})
            artifact_registry=$(if ($context) {$context.artifact_registry_path} else {$null})
        }
    }
    Set-Content $matrixPath -Value $matrix -Encoding UTF8
    $result | ConvertTo-Json -Depth 10 | Set-Content $jsonPath -Encoding UTF8
    if ($context) {
        [void](Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role validation_matrix -Path $matrixPath -Tracked $false -LiveData $false -Generated $true -Description 'English PASS/SKIP/FAIL matrix.' -CreatedBy 'validate-sysadmin-harness')
        [void](Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role validation_result -Path $jsonPath -Tracked $false -LiveData $false -Generated $true -Description 'Machine-readable synthetic harness proof.' -CreatedBy 'validate-sysadmin-harness')
    }
    foreach ($line in $matrix) { Write-Host $line }
    if ($failed) { exit 1 }
}
finally { Pop-Location }
