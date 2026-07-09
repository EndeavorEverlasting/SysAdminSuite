<#
.SYNOPSIS
  Read-only Active Directory export of computer names matching a naming prefix.

.DESCRIPTION
  Enumerates AD computer objects whose Name matches Prefix* using the ActiveDirectory
  module when available, then dsquery as a limited fallback. Does not modify AD.

  Output CSV is suitable for --used-names evidence in sas-hostname-availability.py.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [string]$Server
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoGuess = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $repoGuess 'scripts/SasNetworkGuard.psm1'))) {
    $repoGuess = Split-Path -Parent $repoGuess
}
$networkGuardModule = Join-Path $repoGuess 'scripts/SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $networkGuardModule)) {
    throw "Missing shared network guard module: $networkGuardModule"
}
Import-Module $networkGuardModule -Force
$skipNetworkGuard = $false
if ((Get-Variable -Name AllowFixtures -Scope Local -ErrorAction SilentlyContinue) -and $AllowFixtures) { $skipNetworkGuard = $true }
if ((Get-Variable -Name DryRun -Scope Local -ErrorAction SilentlyContinue) -and $DryRun) { $skipNetworkGuard = $true }
if (-not $skipNetworkGuard) { Assert-SasNorthwellWifi }

function Normalize-Prefix {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw 'Prefix cannot be blank.'
    }
    return ($Value.Trim() -replace '\s+', '').ToUpperInvariant()
}

function New-ExportRow {
    param(
        [string]$ComputerName,
        [string]$DNSHostName = '',
        [string]$Enabled = '',
        [string]$DistinguishedName = '',
        [string]$ADStatus = '',
        [string]$ADProbeMethod = '',
        [string]$Notes = ''
    )
    [pscustomobject]@{
        ComputerName      = $ComputerName
        DNSHostName       = $DNSHostName
        Enabled           = $Enabled
        DistinguishedName = $DistinguishedName
        EvidenceSource    = 'active_directory'
        ADStatus          = $ADStatus
        ADProbeMethod     = $ADProbeMethod
        Notes             = $Notes
    }
}

$normalizedPrefix = Normalize-Prefix $Prefix
$likePattern = "$normalizedPrefix*"

$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$rows = @()
$hasADModule = $null -ne (Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1)
$hasDsquery = $null -ne (Get-Command dsquery.exe -ErrorAction SilentlyContinue)

if ($hasADModule) {
    Import-Module ActiveDirectory -ErrorAction Stop | Out-Null
    $params = @{
        Filter      = "Name -like '$likePattern'"
        Properties  = @('Name', 'DNSHostName', 'Enabled', 'DistinguishedName')
        ErrorAction = 'Stop'
    }
    if ($Server) { $params['Server'] = $Server }

    try {
        $computers = @(Get-ADComputer @params)
        foreach ($c in $computers) {
            $rows += New-ExportRow `
                -ComputerName ([string]$c.Name) `
                -DNSHostName ([string]$c.DNSHostName) `
                -Enabled ([string]$c.Enabled) `
                -DistinguishedName ([string]$c.DistinguishedName) `
                -ADStatus 'ad_object_found' `
                -ADProbeMethod 'active_directory_module_prefix' `
                -Notes ("Prefix filter: {0}" -f $likePattern)
        }
        if ($rows.Count -eq 0) {
            $rows += New-ExportRow `
                -ComputerName '' `
                -ADStatus 'ad_no_match' `
                -ADProbeMethod 'active_directory_module_prefix' `
                -Notes ("No AD computers matched prefix filter: {0}" -f $likePattern)
        }
    } catch {
        $rows += New-ExportRow `
            -ComputerName '' `
            -ADStatus 'ad_query_failed' `
            -ADProbeMethod 'active_directory_module_prefix' `
            -Notes $_.Exception.Message
    }
}
elseif ($hasDsquery) {
    try {
        $raw = & dsquery.exe computer -name $likePattern 2>&1
        if ($LASTEXITCODE -eq 0 -and $raw) {
            foreach ($line in @($raw | Where-Object { $_ -and $_.ToString().Trim() })) {
                $host = ''
                if ($line -match '^"CN=([^,"]+)') { $host = $matches[1] }
                elseif ($line -match '^CN=([^,]+)') { $host = $matches[1] }
                if ($host) {
                    $rows += New-ExportRow `
                        -ComputerName $host `
                        -DistinguishedName ([string]$line) `
                        -ADStatus 'ad_object_found' `
                        -ADProbeMethod 'dsquery_prefix' `
                        -Notes ("Prefix filter: {0}" -f $likePattern)
                }
            }
        }
        if ($rows.Count -eq 0) {
            $rows += New-ExportRow `
                -ComputerName '' `
                -ADStatus 'ad_no_match' `
                -ADProbeMethod 'dsquery_prefix' `
                -Notes (($raw | Out-String).Trim())
        }
    } catch {
        $rows += New-ExportRow `
            -ComputerName '' `
            -ADStatus 'ad_query_failed' `
            -ADProbeMethod 'dsquery_prefix' `
            -Notes $_.Exception.Message
    }
}
else {
    $rows += New-ExportRow `
        -ComputerName '' `
        -ADStatus 'ad_probe_unavailable' `
        -ADProbeMethod 'none' `
        -Notes 'Neither ActiveDirectory PowerShell module nor dsquery.exe is available.'
}

$rows | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
Write-Host ("AD prefix export written: {0} ({1} rows)" -f $Output, $rows.Count)
