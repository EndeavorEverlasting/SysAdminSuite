#Requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$preparer = Join-Path $repoRoot 'Prepare-SysAdminSuiteAutoLogonCloseout.ps1'
$generator = Join-Path $repoRoot 'scripts\New-SasAutoLogonDeploymentHandoff.ps1'
if (-not (Test-Path -LiteralPath $preparer -PathType Leaf)) { throw "Missing preparer: $preparer" }
if (-not (Test-Path -LiteralPath $generator -PathType Leaf)) { throw "Missing generator: $generator" }

$tempRoot = Join-Path $env:TEMP ('SAS AutoLogon Closeout Fixture ' + [guid]::NewGuid().ToString('N'))
$runtime = Join-Path $tempRoot 'Runtime With Spaces'
$output = Join-Path $tempRoot 'Output With Spaces'
$bootstrap = Join-Path $runtime 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
$verification = Join-Path $tempRoot 'runtime-verification.json'
$observed = Join-Path $tempRoot 'observed.txt'
$target = 'fixture-host.example'
$commit = '0123456789abcdef0123456789abcdef01234567'

New-Item -ItemType Directory -Path $runtime -Force | Out-Null

try {
    # Extract only the production native-Git helper from the preparer. This proves the
    # exact Windows PowerShell 5.1 empty-output boundary without running network prep.
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $preparer,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if (@($parseErrors).Count -gt 0) { throw 'Preparer parse failed before Git-helper fixture.' }
    $helperAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Invoke-SasCloseoutGit'
    }, $true)
    if ($null -eq $helperAst) { throw 'Invoke-SasCloseoutGit function was not found.' }
    Invoke-Expression $helperAst.Extent.Text

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) { $gitCommand = Get-Command git -ErrorAction Stop | Select-Object -First 1 }
    $script:SasGitExe = [string]$gitCommand.Source
    $gitFixture = Join-Path $tempRoot 'git-silent-success'
    New-Item -ItemType Directory -Path $gitFixture -Force | Out-Null
    & $script:SasGitExe -C $gitFixture init *> $null
    if ([int]$global:LASTEXITCODE -ne 0) { throw 'Could not initialize Git fixture.' }
    $silent = @(Invoke-SasCloseoutGit -Root $gitFixture -Arguments @('check-ref-format','refs/heads/main') -FailureMessage 'Silent Git success unexpectedly failed.' -Quiet)
    if ($silent.Count -ne 0) { throw 'Silent Git success unexpectedly returned output.' }

    $bootstrapText = @'
@echo off
> "%SAS_CLOSEOUT_FIXTURE_OBSERVED%" echo target=%~1
>> "%SAS_CLOSEOUT_FIXTURE_OBSERVED%" echo commit=%~2
exit /b 0
'@
    [IO.File]::WriteAllText($bootstrap,$bootstrapText,[Text.Encoding]::ASCII)

    $verificationObject = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-runtime-verification/v1'
        status = 'PASS'
        classification = 'AUTOLOGON_RUNTIME_SEAL_VERIFIED'
        prepared_commit = $commit
        runtime_root = $runtime
        network_activity_performed = $false
        target_contact_performed = $false
        target_mutation_performed = $false
        crash_safe_run_started = $false
    }
    $verificationObject | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $verification -Encoding UTF8

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $generator `
        -ComputerName $target -PreparedCommit $commit -RuntimeRoot $runtime `
        -OutputRoot $output -RuntimeVerificationReceipt $verification
    if ([int]$global:LASTEXITCODE -ne 0) { throw "Generator failed with exit $global:LASTEXITCODE" }

    $handoff = Join-Path $output 'Run-Prepared-AutoLogon.cmd'
    $receipt = Join-Path $output 'autologon-closeout-readiness.json'
    if (-not (Test-Path -LiteralPath $handoff -PathType Leaf)) { throw 'Handoff was not generated.' }
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { throw 'Readiness receipt was not generated.' }

    $parsed = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$parsed.status -ne 'READY_FOR_PROTECTED_DEPLOYMENT') { throw 'Unexpected readiness status.' }
    if ([string]$parsed.requested_target -ne $target) { throw 'Readiness target mismatch.' }
    if ([string]$parsed.prepared_commit -ne $commit) { throw 'Readiness commit mismatch.' }
    if (-not [bool]$parsed.runtime_seal_verified) { throw 'Runtime seal flag was not preserved.' }
    if ([bool]$parsed.target_contact_performed -or [bool]$parsed.target_mutation_performed -or [bool]$parsed.crash_safe_run_started) { throw 'Preparation receipt claimed target or transaction activity.' }

    $previousObserved = $env:SAS_CLOSEOUT_FIXTURE_OBSERVED
    try {
        $env:SAS_CLOSEOUT_FIXTURE_OBSERVED = $observed
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('call "' + $handoff + '"')) -Wait -PassThru -NoNewWindow
        if ([int]$process.ExitCode -ne 0) { throw "Generated handoff failed with exit $($process.ExitCode)." }
    }
    finally {
        if ($null -eq $previousObserved) { Remove-Item Env:SAS_CLOSEOUT_FIXTURE_OBSERVED -ErrorAction SilentlyContinue }
        else { $env:SAS_CLOSEOUT_FIXTURE_OBSERVED = $previousObserved }
    }

    # cmd.exe writes CRLF. Normalize line boundaries before exact equality so this fixture
    # validates argument binding rather than host newline convention.
    $observedLines = @(Get-Content -LiteralPath $observed | ForEach-Object { ([string]$_).TrimEnd("`r") })
    if ($observedLines -notcontains ('target=' + $target)) { throw 'Generated handoff changed target binding.' }
    if ($observedLines -notcontains ('commit=' + $commit)) { throw 'Generated handoff changed commit binding.' }

    $invalidOutput = Join-Path $tempRoot 'invalid-output'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $generator `
        -ComputerName 'bad&target' -PreparedCommit $commit -RuntimeRoot $runtime `
        -OutputRoot $invalidOutput -RuntimeVerificationReceipt $verification *> $null
    if ([int]$global:LASTEXITCODE -eq 0) { throw 'Generator accepted a command-injection target shape.' }
    if (Test-Path -LiteralPath (Join-Path $invalidOutput 'Run-Prepared-AutoLogon.cmd')) { throw 'Invalid target generated a handoff.' }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: AutoLogon closeout preparation is PS5.1 empty-Git-safe; handoff preserves exact target/commit, requires verified runtime evidence, and rejects unsafe target shapes.' -ForegroundColor Green
