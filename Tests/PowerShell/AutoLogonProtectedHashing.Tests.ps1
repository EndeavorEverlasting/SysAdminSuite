#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$bootstrapPath = Join-Path $repoRoot 'Bootstrap-SysAdminSuiteAutoLogon.ps1'
if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    throw "Missing protected AutoLogon bootstrap: $bootstrapPath"
}

$source = Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8
if ($source -match '(?i)\bGet-FileHash\b') {
    throw 'Protected AutoLogon bootstrap must not depend on Get-FileHash.'
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $bootstrapPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | Format-List * | Out-Host
    throw 'Protected AutoLogon bootstrap has PowerShell parse errors.'
}

$hashFunctions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-SasSha256Hex'
}, $true))
if ($hashFunctions.Count -ne 1) {
    throw "Expected exactly one Get-SasSha256Hex function, found $($hashFunctions.Count)."
}

# Reproduce the field boundary explicitly: even if Get-FileHash is unavailable/broken,
# the production helper must work because it uses .NET SHA256 directly.
function Get-FileHash { throw 'FIELD_FIXTURE_GET_FILE_HASH_MUST_NOT_BE_CALLED' }
Invoke-Expression $hashFunctions[0].Extent.Text

$tempPath = Join-Path $env:TEMP ('sas-protected-hash-' + [guid]::NewGuid().ToString('N') + '.bin')
try {
    [IO.File]::WriteAllBytes($tempPath, [Text.Encoding]::ASCII.GetBytes('abc'))
    $actual = Get-SasSha256Hex -LiteralPath $tempPath
    $expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    if ($actual -ne $expected) {
        throw "Protected SHA-256 helper mismatch. Expected=$expected Actual=$actual"
    }
}
finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: protected AutoLogon SHA-256 helper runs on Windows PowerShell 5.1 without Get-FileHash.'
