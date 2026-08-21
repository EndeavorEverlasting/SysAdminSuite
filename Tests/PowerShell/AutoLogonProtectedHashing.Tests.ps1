#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$surfacePaths = @(
    (Join-Path $repoRoot 'Bootstrap-SysAdminSuiteAutoLogon.ps1'),
    (Join-Path $repoRoot 'scripts\Show-SasAutoLogonResult.ps1')
)

# Reproduce the field boundary explicitly: even if Get-FileHash is unavailable/broken,
# every protected AutoLogon hashing surface must work because it uses .NET SHA256 directly.
function Get-FileHash { throw 'FIELD_FIXTURE_GET_FILE_HASH_MUST_NOT_BE_CALLED' }

foreach ($surfacePath in $surfacePaths) {
    if (-not (Test-Path -LiteralPath $surfacePath -PathType Leaf)) {
        throw "Missing protected AutoLogon hashing surface: $surfacePath"
    }

    $source = Get-Content -LiteralPath $surfacePath -Raw -Encoding UTF8
    if ($source -match '(?i)\bGet-FileHash\b') {
        throw "Protected AutoLogon hashing surface must not depend on Get-FileHash: $surfacePath"
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $surfacePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if (@($parseErrors).Count -gt 0) {
        $parseErrors | Format-List * | Out-Host
        throw "Protected AutoLogon hashing surface has PowerShell parse errors: $surfacePath"
    }

    $hashFunctions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-SasSha256Hex'
    }, $true))
    if ($hashFunctions.Count -ne 1) {
        throw "Expected exactly one Get-SasSha256Hex function in $surfacePath, found $($hashFunctions.Count)."
    }

    Invoke-Expression $hashFunctions[0].Extent.Text

    $tempPath = Join-Path $env:TEMP ('sas-protected-hash-' + [guid]::NewGuid().ToString('N') + '.bin')
    try {
        [IO.File]::WriteAllBytes($tempPath, [Text.Encoding]::ASCII.GetBytes('abc'))
        $actual = Get-SasSha256Hex -LiteralPath $tempPath
        $expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        if ($actual -ne $expected) {
            throw "Protected SHA-256 helper mismatch for $surfacePath. Expected=$expected Actual=$actual"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'PASS: protected AutoLogon bootstrap and result presenter SHA-256 helpers run on Windows PowerShell 5.1 without Get-FileHash.'
