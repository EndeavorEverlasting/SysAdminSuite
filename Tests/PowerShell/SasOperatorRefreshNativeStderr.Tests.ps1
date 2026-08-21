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

$script:SasGitExe = $env:ComSpec
if ([string]::IsNullOrWhiteSpace($script:SasGitExe) -or -not (Test-Path -LiteralPath $script:SasGitExe -PathType Leaf)) {
    throw "Windows command processor was not found: $script:SasGitExe"
}

# Reproduce the field primitive deterministically: a successful native command writes
# stdout while stderr is redirected to a real, zero-byte file. Windows PowerShell 5.1
# returns $null for Get-Content -Raw on that empty file, so production code must not
# call an instance method until the value has been normalized.
$result = @(Invoke-SasRefreshGit `
    -Arguments @('/d','/c','echo main') `
    -FailureMessage 'Synthetic successful native command failed.' `
    -Quiet)
if (@($result).Count -ne 1 -or ([string]$result[0]).Trim() -ne 'main') {
    throw "Unexpected successful native-command result: $($result -join '|')"
}

$failureObserved = $false
try {
    [void](Invoke-SasRefreshGit `
        -Arguments @('/d','/c','echo synthetic-stderr 1>&2 & exit /b 7') `
        -FailureMessage 'Synthetic native failure' `
        -Quiet)
}
catch {
    $failureObserved = $true
    $message = $_.Exception.Message
    if ($message -notmatch 'Synthetic native failure \(git exit 7\)') {
        throw "Native failure lost its exit-code diagnostic: $message"
    }
    if ($message -notmatch 'synthetic-stderr') {
        throw "Native failure lost its stderr diagnostic: $message"
    }
}
if (-not $failureObserved) {
    throw 'Expected the synthetic nonzero native command to fail.'
}

Write-Host 'PASS: sas refresh native stderr handling accepts zero-byte stderr and preserves nonzero diagnostics under Windows PowerShell 5.1.' -ForegroundColor Green
