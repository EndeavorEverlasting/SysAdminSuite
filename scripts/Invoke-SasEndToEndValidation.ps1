#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Profile = 'default',
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$profilePath = Join-Path $repoRoot 'harness/e2e/e2e-profiles.json'
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/e2e-validation'
} elseif (-not [IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot $OutputRoot
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$runId = 'e2e-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

function Resolve-Runtime {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

function Expand-Argument {
    param([string]$Value, [string]$JourneyOutput)
    return $Value.Replace('{repo_root}', $repoRoot).Replace('{run_root}', $runRoot).Replace('{journey_output}', $JourneyOutput)
}

function Tail-Text {
    param([string[]]$Lines, [int]$Maximum = 12)
    if (-not $Lines -or $Lines.Count -eq 0) { return @() }
    $start = [Math]::Max(0, $Lines.Count - $Maximum)
    return ,@($Lines[$start..($Lines.Count - 1)])
}

function Test-AllUnittestCasesSkipped {
    param([string[]]$Lines)
    $joined = @($Lines) -join "`n"
    $ranMatch = [regex]::Match($joined, '(?im)^Ran\s+(\d+)\s+tests?\s+in\s+')
    $skippedMatch = [regex]::Match($joined, '(?im)^OK\s+\(skipped=(\d+)\)\s*$')
    if (-not $ranMatch.Success -or -not $skippedMatch.Success) { return $false }
    $ran = [int]$ranMatch.Groups[1].Value
    $skipped = [int]$skippedMatch.Groups[1].Value
    return $ran -gt 0 -and $ran -eq $skipped
}

$catalog = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$allProfiles = @($catalog.profiles)
$profileRecord = @($allProfiles | Where-Object { $_.id -eq $Profile })
if ($profileRecord.Count -ne 1) {
    throw "Unknown or ambiguous E2E profile '$Profile'."
}
$journeysById = @{}
foreach ($journey in @($catalog.journeys)) {
    if ($journeysById.ContainsKey($journey.id)) { throw "Duplicate journey ID '$($journey.id)'." }
    $journeysById[$journey.id] = $journey
}

$results = [Collections.Generic.List[object]]::new()
$externalNetwork = $false
$loopbackNetwork = $false
$targetMutation = $false

Push-Location $repoRoot
try {
    foreach ($journeyId in @($profileRecord[0].journey_ids)) {
        if (-not $journeysById.ContainsKey($journeyId)) {
            $results.Add([pscustomobject]@{
                id=$journeyId; status='FAIL'; required=$true; exit_code=$null; duration_ms=0
                network_scope='unknown'; target_mutation=$false
                runtime=$null; script=$null; log=$null
                detail='profile references missing journey'
            })
            continue
        }

        $journey = $journeysById[$journeyId]
        $runtime = Resolve-Runtime @($journey.runtime_candidates)
        $journeyOutput = Join-Path $runRoot $journey.id
        New-Item -ItemType Directory -Force -Path $journeyOutput | Out-Null
        $logPath = Join-Path $runRoot ($journey.id + '.log')
        $scriptPath = Join-Path $repoRoot $journey.script

        if ($journey.network_scope -eq 'loopback-only') { $loopbackNetwork = $true }
        elseif ($journey.network_scope -ne 'none') { $externalNetwork = $true }
        if ($journey.target_mutation) { $targetMutation = $true }

        if (-not $runtime) {
            $detail = 'missing runtime: ' + (@($journey.runtime_candidates) -join ', ')
            Set-Content -LiteralPath $logPath -Value $detail -Encoding UTF8
            $results.Add([pscustomobject]@{
                id=$journey.id; status=$(if ($journey.required) {'FAIL'} else {'SKIP'})
                required=[bool]$journey.required; exit_code=$null; duration_ms=0
                network_scope=$journey.network_scope; target_mutation=[bool]$journey.target_mutation
                runtime=$null; script=$journey.script; log=$logPath; detail=$detail
            })
            continue
        }
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $detail = "missing script: $($journey.script)"
            Set-Content -LiteralPath $logPath -Value $detail -Encoding UTF8
            $results.Add([pscustomobject]@{
                id=$journey.id; status='FAIL'; required=[bool]$journey.required
                exit_code=$null; duration_ms=0; network_scope=$journey.network_scope
                target_mutation=[bool]$journey.target_mutation; runtime=$runtime
                script=$journey.script; log=$logPath; detail=$detail
            })
            continue
        }

        $arguments = @()
        if ([IO.Path]::GetExtension($scriptPath) -ieq '.ps1') {
            $arguments += @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath)
        } else {
            $arguments += $scriptPath
        }
        foreach ($argument in @($journey.arguments)) {
            $arguments += Expand-Argument ([string]$argument) $journeyOutput
        }

        $watch = [Diagnostics.Stopwatch]::StartNew()
        $output = @(& $runtime @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        $watch.Stop()

        if ([bool]$journey.required -and $exitCode -eq 0 -and (Test-AllUnittestCasesSkipped $output)) {
            $exitCode = 3
            $output += 'Required E2E journey skipped all tests; required journeys must execute at least one assertion.'
        }

        Set-Content -LiteralPath $logPath -Value $output -Encoding UTF8
        $status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        $tail = Tail-Text $output
        $results.Add([pscustomobject]@{
            id=$journey.id; status=$status; required=[bool]$journey.required
            exit_code=$exitCode; duration_ms=$watch.ElapsedMilliseconds
            network_scope=$journey.network_scope; target_mutation=[bool]$journey.target_mutation
            runtime=$runtime; script=$journey.script; log=$logPath
            detail=$(if ($tail.Count) {$tail -join "`n"} else {'completed without console output'})
        })
    }
} finally {
    Pop-Location
}

$failedRequired = @($results | Where-Object { $_.required -and $_.status -ne 'PASS' })
$passed = @(@($results) | Where-Object status -eq 'PASS').Count
$skipped = @(@($results) | Where-Object status -eq 'SKIP').Count
$failed = @(@($results) | Where-Object status -eq 'FAIL').Count
$matrixPath = Join-Path $runRoot 'e2e_validation_matrix.txt'
$jsonPath = Join-Path $runRoot 'e2e_validation_result.json'
$matrix = [Collections.Generic.List[string]]::new()
$matrix.Add('SYSADMINSUITE END-TO-END VALIDATION')
$matrix.Add("Repo: $repoRoot")
$matrix.Add("Profile: $Profile")
$matrix.Add("Proof class: $($profileRecord[0].proof_class)")
$matrix.Add('Live target proof: false')
$matrix.Add('')
foreach ($result in $results) {
    $matrix.Add("[$($result.status)] $($result.id) - $($result.script)")
}
$matrix.Add('')
$matrix.Add("Result: $passed passed / $skipped skipped / $failed failed")
$matrix.Add("JSON: $jsonPath")

$resultObject = [ordered]@{
    schema_version='sas-e2e-validation/v1'
    generated_at=(Get-Date).ToUniversalTime().ToString('o')
    repo_root=$repoRoot
    profile=$Profile
    proof_class=$profileRecord[0].proof_class
    end_to_end_executed=$true
    fixture_or_loopback_e2e=$true
    live_target_e2e=$false
    loopback_network_activity_performed=$loopbackNetwork
    external_network_activity_performed=$externalNetwork
    target_mutation_performed=$targetMutation
    counts=[ordered]@{passed=$passed; skipped=$skipped; failed=$failed}
    journeys=@($results)
    artifacts=[ordered]@{run_root=$runRoot; matrix=$matrixPath; json=$jsonPath}
}
Set-Content -LiteralPath $matrixPath -Value $matrix -Encoding UTF8
$resultObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
foreach ($line in $matrix) { Write-Host $line }
if ($failedRequired.Count -gt 0) { exit 1 }
