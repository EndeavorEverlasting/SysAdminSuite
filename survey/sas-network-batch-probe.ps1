#Requires -Version 5.1
<#
.SYNOPSIS
Run a bounded low-noise network preflight for explicit host/IP targets without requiring a caller-created manifest.

.DESCRIPTION
Resolves SysAdminSuite from this script's own location, materializes a temporary approved targets/local
file, invokes the canonical sas-network-preflight.ps1, and removes the temporary target file by default.
This keeps operator current-directory state out of the probe contract while preserving the existing target
intake, protected-network, low-noise, and evidence-output controls.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Target,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [int[]]$Ports = @(135, 445),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyProfile = 'network_preflight',

    [Parameter(Mandatory = $false)]
    [switch]$KeepTargetFile
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$preflight = Join-Path $repoRoot 'survey\sas-network-preflight.ps1'
$targetRoot = Join-Path $repoRoot 'targets\local'

if (-not (Test-Path -LiteralPath $preflight -PathType Leaf)) {
    throw "Canonical network preflight is missing: $preflight"
}

function Test-SasBatchProbeTarget {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim()

    $ip = $null
    if ([System.Net.IPAddress]::TryParse($candidate, [ref]$ip)) { return $true }
    if ($candidate -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') { return $true }
    if ($candidate -match '^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$') { return $true }
    if ($candidate -match '^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$') { return $true }

    return $false
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$targets = New-Object 'System.Collections.Generic.List[string]'
foreach ($rawTarget in @($Target)) {
    $candidate = ([string]$rawTarget).Trim()
    if (-not (Test-SasBatchProbeTarget -Value $candidate)) {
        throw "Invalid network probe target: '$rawTarget'. Use an explicit hostname/FQDN/IP accepted by the canonical network preflight (for example HOST01, HOST-NAME, or 10.0.0.10)."
    }
    if ($seen.Add($candidate)) { [void]$targets.Add($candidate) }
}

if ($targets.Count -eq 0) {
    throw 'No probe-ready network targets were supplied.'
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
$runId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$targetFile = Join-Path $targetRoot "network_probe_${runId}_${nonce}.txt"

try {
    $targets | Set-Content -LiteralPath $targetFile -Encoding UTF8

    Write-Host 'SysAdminSuite bounded network probe' -ForegroundColor Cyan
    Write-Host "Targets: $($targets.Count)"
    Write-Host "Ports: $($Ports -join ',')"
    Write-Host "Temporary approved target file: $targetFile"
    Write-Host 'Target file lifecycle: temporary; removed after the preflight unless -KeepTargetFile is set.' -ForegroundColor DarkGray

    & $preflight -TargetFile $targetFile -Ports $Ports -PolicyProfile $PolicyProfile
}
finally {
    if (-not $KeepTargetFile -and (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
        Remove-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
    }
}
