#Requires -Version 5.1
<#
.SYNOPSIS
Builds the SysAdminSuite dummy software-install fixture executable.

.DESCRIPTION
Compiles the tracked C# fixture source with the Windows .NET Framework compiler. The generated
binary and its build manifest are written to a caller-selected output path and are never committed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$SourcePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $repoRoot 'Tests/fixtures/software-install/DummyInstaller.cs'
}
elseif (-not [IO.Path]::IsPathRooted($SourcePath)) {
    $SourcePath = Join-Path $repoRoot $SourcePath
}
if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$SourcePath = [IO.Path]::GetFullPath($SourcePath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (-not [IO.File]::Exists($SourcePath)) {
    throw "Dummy installer source not found: $SourcePath"
}
if (-not $OutputPath.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must end in .exe: $OutputPath"
}

$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates |
    Where-Object { [IO.File]::Exists($_) } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace([string]$compiler)) {
    throw 'Windows .NET Framework C# compiler csc.exe was not found.'
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$compilerArguments = @(
    '/nologo',
    '/target:exe',
    '/optimize+',
    '/platform:anycpu',
    "/out:$OutputPath",
    $SourcePath
)
& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "csc.exe failed with exit code $LASTEXITCODE"
}
if (-not [IO.File]::Exists($OutputPath)) {
    throw "Compiler reported success but the executable is missing: $OutputPath"
}

$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$buildManifestPath = "$OutputPath.build.json"
$manifest = [ordered]@{
    schema_version = 'sas-software-install-fixture-build/v1'
    built_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_path = $SourcePath
    source_sha256 = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    executable_path = $OutputPath
    executable_sha256 = $hash
    executable_bytes = (Get-Item -LiteralPath $OutputPath).Length
    compiler = $compiler
    target = 'windows-dotnet-framework-anycpu'
}
$manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $buildManifestPath -Encoding UTF8

[pscustomobject]@{
    executable_path = $OutputPath
    executable_sha256 = $hash
    executable_bytes = $manifest.executable_bytes
    build_manifest_path = $buildManifestPath
    compiler = $compiler
}
