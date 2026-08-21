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

$refreshText = Get-Content -LiteralPath $refreshPath -Raw
if ($refreshText -match '(?m)^\s*\$LASTEXITCODE\s*=') {
    throw 'Refresh script must not create an unscoped LASTEXITCODE shadow before native execution.'
}
if ($refreshText -notmatch '\$global:LASTEXITCODE') {
    throw 'Refresh script must capture native exit codes from the global automatic variable.'
}
if ($refreshText -match '\-join\s+\[Environment\]::NewLine\)\.Trim\(') {
    throw 'Refresh script must not call Trim directly on a possibly-null join result.'
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gitCommand) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $gitCommand -or [string]::IsNullOrWhiteSpace([string]$gitCommand.Source)) {
    throw 'Git executable was not found for the refresh regression fixture.'
}
$script:SasGitExe = [IO.Path]::GetFullPath([string]$gitCommand.Source)

# Reproduce the original field primitive: `git check-ref-format --branch main` succeeds.
# Some Git/PowerShell combinations return stdout for this form and some do not, so production
# must accept either shape without dereferencing a null join result.
$result = @(Invoke-SasRefreshGit `
    -Arguments @('check-ref-format','--branch','main') `
    -FailureMessage 'Synthetic successful Git ref check failed.' `
    -Quiet)
if (@($result).Count -gt 1 -or (@($result).Count -eq 1 -and ([string]$result[0]).Trim() -ne 'main')) {
    throw "Unexpected successful Git result: $($result -join '|')"
}

# Prove the exact missing case from field evidence: a successful native Git command may produce
# neither stdout nor stderr. The helper must return an empty collection and must not call Trim()
# on a null value under Windows PowerShell 5.1.
$silentResult = @(Invoke-SasRefreshGit `
    -Arguments @('check-ref-format','refs/heads/main') `
    -FailureMessage 'Synthetic silent successful Git ref check failed.' `
    -Quiet)
if (@($silentResult).Count -ne 0) {
    throw "Expected silent Git success to return no output; got: $($silentResult -join '|')"
}

# Preserve the other half of the helper contract: first prove the fixture itself really
# produces a nonzero native Git result in this Windows PowerShell process under the same
# ErrorActionPreference policy used by production, then run the exact same arguments
# through the production helper and require the structured failure.
$missingRef = 'refs/heads/sas-refresh-native-stderr-fixture-missing-7d2c610b'
$rawStderrPath = Join-Path $env:TEMP ('sas-refresh-raw-git-' + [guid]::NewGuid().ToString('N') + '.err')
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & $script:SasGitExe -C $repoRoot 'rev-parse' '--verify' $missingRef 2> $rawStderrPath | Out-Null
    $rawExit = [int]$global:LASTEXITCODE
    $rawStderr = if (Test-Path -LiteralPath $rawStderrPath) {
        [string](Get-Content -LiteralPath $rawStderrPath -Raw -ErrorAction SilentlyContinue)
    } else { '' }
}
finally {
    $ErrorActionPreference = $previousPreference
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

Write-Host 'PASS: sas refresh Git output handling accepts silent success/zero-byte stderr and preserves nonzero exit handling under Windows PowerShell 5.1.' -ForegroundColor Green
exit 0
