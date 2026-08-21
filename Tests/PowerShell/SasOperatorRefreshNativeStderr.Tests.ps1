#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$refreshPath = Join-Path $repoRoot 'scripts\Refresh-SasOperatorCommand.ps1'
if (-not (Test-Path -LiteralPath $refreshPath -PathType Leaf)) {
    throw "Refresh script not found: $refreshPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $refreshPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | Format-List * | Out-Host
    throw 'Refresh script failed Windows PowerShell 5.1 parsing.'
}

$functionAst = $ast.Find(
    {
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Invoke-SasRefreshGit'
    },
    $true
)
if ($null -eq $functionAst) {
    throw 'Invoke-SasRefreshGit production function was not found.'
}

. ([scriptblock]::Create($functionAst.Extent.Text))

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gitCommand) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $gitCommand -or [string]::IsNullOrWhiteSpace([string]$gitCommand.Source)) {
    throw 'Git executable was not found for the refresh regression fixture.'
}
$script:SasGitExe = [IO.Path]::GetFullPath([string]$gitCommand.Source)

# Reproduce the exact field primitive: `git check-ref-format --branch main` succeeds,
# writes stdout, and leaves the redirected stderr file at zero bytes. Windows PowerShell
# 5.1 returns $null for Get-Content -Raw on that empty file, so production code must not
# call an instance method until the value has been normalized.
$result = @(Invoke-SasRefreshGit `
    -Arguments @('check-ref-format','--branch','main') `
    -FailureMessage 'Synthetic successful Git ref check failed.' `
    -Quiet)
if (@($result).Count -ne 1 -or ([string]$result[0]).Trim() -ne 'main') {
    throw "Unexpected successful Git result: $($result -join '|')"
}

# Preserve the other half of the helper contract: first prove the fixture itself really
# produces a nonzero native Git result in this Windows PowerShell process, then run the
# exact same arguments through the production helper and require the structured failure.
$missingRef = 'refs/heads/sas-refresh-native-stderr-fixture-missing-7d2c610b'
$rawStderrPath = Join-Path $env:TEMP ('sas-refresh-raw-git-' + [guid]::NewGuid().ToString('N') + '.err')
try {
    $LASTEXITCODE = 0
    & $script:SasGitExe -C $repoRoot 'rev-parse' '--verify' $missingRef 2> $rawStderrPath | Out-Null
    $rawExit = [int]$LASTEXITCODE
    $rawStderr = if (Test-Path -LiteralPath $rawStderrPath) {
        [string](Get-Content -LiteralPath $rawStderrPath -Raw -ErrorAction SilentlyContinue)
    } else { '' }
}
finally {
    Remove-Item -LiteralPath $rawStderrPath -Force -ErrorAction SilentlyContinue
}
if ($rawExit -eq 0) {
    throw "Negative-control Git command unexpectedly returned zero for missing ref $missingRef."
}
Write-Host ("RAW GIT NEGATIVE CONTROL: exit={0}; stderr={1}" -f $rawExit,$rawStderr.Trim()) -ForegroundColor DarkGray

$failureObserved = $false
try {
    [void](Invoke-SasRefreshGit `
        -Root $repoRoot `
        -Arguments @('rev-parse','--verify',$missingRef) `
        -FailureMessage 'Synthetic Git missing-ref failure' `
        -Quiet)
}
catch {
    $failureObserved = $true
    $message = $_.Exception.Message
    if ($message -notmatch 'Synthetic Git missing-ref failure \(git exit [1-9][0-9]*\)') {
        throw "Git failure lost its exit-code diagnostic: $message"
    }
}
if (-not $failureObserved) {
    throw 'Production helper did not surface the proven nonzero Git failure.'
}

Write-Host 'PASS: sas refresh Git stderr handling accepts zero-byte stderr and preserves nonzero exit handling under Windows PowerShell 5.1.' -ForegroundColor Green
