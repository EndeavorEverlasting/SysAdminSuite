#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$enginePath = Join-Path $repoRoot 'scripts\Invoke-SasNorthwellPrinterQueueProof.ps1'
if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Missing printer queue proof engine: $enginePath"
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $enginePath),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    throw ($errors | ForEach-Object { $_.Message } | Out-String)
}

$functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'ConvertTo-SasDnsARecordRows'
}, $true)
if (-not $functionAst) {
    throw 'ConvertTo-SasDnsARecordRows was not found in the proof engine.'
}

# Evaluate only the pure DNS-normalization helper so this contract does not
# execute the proof engine, touch a target, or require live DNS/network access.
Invoke-Expression $functionAst.Extent.Text

$records = @(
    [pscustomobject]@{
        Name = 'alias.example.invalid'
        Type = 'CNAME'
        NameHost = 'server.example.invalid'
    },
    [pscustomobject]@{
        Name = 'server.example.invalid'
        Type = 'A'
        IPAddress = '10.23.45.67'
    },
    [pscustomobject]@{
        Name = 'bad.example.invalid'
        Type = 'A'
        IPAddress = 'not-an-ip'
    },
    [pscustomobject]@{
        Name = 'v6.example.invalid'
        Type = 'AAAA'
        IPAddress = '2001:db8::1'
    },
    $null
)

$rows = @($records | ConvertTo-SasDnsARecordRows)
if ($rows.Count -ne 1) {
    throw "Expected exactly one normalized IPv4 row from heterogeneous DNS records; got $($rows.Count)."
}
if ($rows[0].name -ne 'server.example.invalid') {
    throw "Unexpected normalized DNS name: $($rows[0].name)"
}
if ($rows[0].ip_address -ne '10.23.45.67') {
    throw "Unexpected normalized IPv4 address: $($rows[0].ip_address)"
}

$engineText = Get-Content -LiteralPath $enginePath -Raw
if ($engineText -match 'Where-Object\s*\{\s*\$_\.IPAddress\s*\}') {
    throw 'StrictMode-unsafe direct .IPAddress filtering returned to the DNS path.'
}
if ($engineText -notmatch "PSObject\.Properties\['IPAddress'\]") {
    throw 'DNS normalization no longer checks the property bag before reading IPAddress.'
}

Write-Host 'PASS: heterogeneous Resolve-DnsName records normalize safely under StrictMode.'
