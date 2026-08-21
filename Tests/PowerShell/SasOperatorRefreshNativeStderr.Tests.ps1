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

# Preserve the other half of the helper contract: a real Git failure must still carry
# its nonzero exit code and stderr diagnostics after the empty-stderr repair.
$failureObserved = $false
try {
    [void](Invoke-SasRefreshGit `
        -Arguments @('check-ref-format','--branch','bad ref') `
        -FailureMessage 'Synthetic Git ref failure' `
        -Quiet)
}
catch {
    $failureObserved = $true
    $message = $_.Exception.Message
    if ($message -notmatch 'Synthetic Git ref failure \(git exit [1-9][0-9]*\)') {
        throw "Git failure lost its exit-code diagnostic: $message"
    }
    if ($message -notmatch '(?i)valid branch name|valid ref') {
        throw "Git failure lost its stderr diagnostic: $message"
    }
}
if (-not $failureObserved) {
    throw 'Expected the invalid Git branch check to fail.'
}

Write-Host 'PASS: sas refresh Git stderr handling accepts zero-byte stderr and preserves nonzero diagnostics under Windows PowerShell 5.1.' -ForegroundColor Green
