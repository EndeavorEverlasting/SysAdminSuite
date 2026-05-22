<# 
.SYNOPSIS
  Exports read-only Active Directory identity evidence for SysAdminSuite identity resolution.

.DESCRIPTION
  Reads a manifest CSV and attempts to resolve each target/identifier against AD using the
  ActiveDirectory PowerShell module when available, then dsquery as a limited fallback.

  This script is read-only. It does not modify AD, workstation state, registry, DNS, or tracker data.

.NOTES
  Serial/MAC reverse lookup depends on whether AD actually contains those identifiers in
  searchable attributes such as Description or site-specific extension attributes. The script
  reports weak/no-match evidence instead of pretending AD has data it does not expose.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Manifest,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [switch]$SearchDescription
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FirstValue {
    param(
        [hashtable]$Row,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        foreach ($key in $Row.Keys) {
            if ($key -and $key.Trim().ToLowerInvariant() -eq $name.Trim().ToLowerInvariant()) {
                $value = [string]$Row[$key]
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value.Trim()
                }
            }
        }
    }
    return ''
}

function ConvertTo-Hashtable {
    param($Object)
    $h = @{}
    foreach ($p in $Object.PSObject.Properties) {
        $h[$p.Name] = $p.Value
    }
    return $h
}

function Normalize-Identifier {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ($Value.Trim() -replace '\s+', '').ToUpperInvariant()
}

function Get-IdentifierType {
    param([string]$Value)
    $v = Normalize-Identifier $Value
    if (-not $v) { return 'missing' }
    if ($v -match '^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$') { return 'mac' }
    if ($v -match 'HOST|OPR|PC|WKST|WKS') { return 'hostname' }
    if ($v -match '[A-Z]' -and $v -match '\d') { return 'serial_or_asset' }
    return 'identifier'
}

function Escape-LdapValue {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace '\\','\5c' -replace '\*','\2a' -replace '\(','\28' -replace '\)','\29' -replace "`0",'\00')
}

function New-EvidenceRow {
    param(
        [string]$Target,
        [string]$IdentifierType,
        [string]$ADHostname = '',
        [string]$DNSHostName = '',
        [string]$ADSerial = '',
        [string]$ADMAC = '',
        [string]$ADEnabled = '',
        [string]$DirectoryPath = '',
        [string]$ADStatus = '',
        [string]$ADProbeMethod = '',
        [string]$Notes = ''
    )
    [pscustomobject]@{
        Target = $Target
        IdentifierType = $IdentifierType
        ADHostname = $ADHostname
        DNSHostName = $DNSHostName
        ADSerial = $ADSerial
        ADMAC = $ADMAC
        ADEnabled = $ADEnabled
        DirectoryPath = $DirectoryPath
        ADStatus = $ADStatus
        ADProbeMethod = $ADProbeMethod
        Notes = $Notes
    }
}

function Get-ManifestIdentifier {
    param([hashtable]$Row)
    $target = Get-FirstValue $Row @(
        'target', 'Target', 'Identifier', 'SurveyTargetHint',
        'HostName', 'Hostname', 'Cybernet Hostname', 'Neuron Hostname',
        'Cybernet Serial', 'Cybernet S/N', 'Neuron S/N', 'Neuron Serial',
        'MACAddress', 'MAC'
    )
    return $target
}

function Find-WithADModule {
    param(
        [string]$Identifier,
        [string]$IdentifierType,
        [switch]$AllowDescriptionSearch
    )

    $props = @('Enabled', 'DistinguishedName', 'DNSHostName', 'Description', 'Name', 'whenChanged')

    if ($IdentifierType -eq 'hostname') {
        try {
            $direct = Get-ADComputer -Identity $Identifier -Properties $props -ErrorAction Stop
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADHostname ([string]$direct.Name) `
                -DNSHostName ([string]$direct.DNSHostName) `
                -ADEnabled ([string]$direct.Enabled) `
                -DirectoryPath ([string]$direct.DistinguishedName) `
                -ADStatus 'ad_object_found' `
                -ADProbeMethod 'active_directory_module_identity' `
                -Notes ("whenChanged={0}" -f $direct.whenChanged)
        } catch {
            # Continue into broad lookup.
        }
    }

    $safe = Escape-LdapValue $Identifier
    $filter = "(|(name=*$safe*)(dNSHostName=*$safe*)"
    if ($AllowDescriptionSearch) {
        $filter += "(description=*$safe*)"
    }
    $filter += ")"

    try {
        $matches = @(Get-ADComputer -LDAPFilter $filter -Properties $props -ResultSetSize 5 -ErrorAction Stop)
        if ($matches.Count -eq 1) {
            $m = $matches[0]
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADHostname ([string]$m.Name) `
                -DNSHostName ([string]$m.DNSHostName) `
                -ADEnabled ([string]$m.Enabled) `
                -DirectoryPath ([string]$m.DistinguishedName) `
                -ADStatus 'ad_object_found' `
                -ADProbeMethod 'active_directory_module_attribute_search' `
                -Notes ("Matched one AD computer object. whenChanged={0}" -f $m.whenChanged)
        }
        if ($matches.Count -gt 1) {
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADStatus 'ad_multiple_matches' `
                -ADProbeMethod 'active_directory_module_attribute_search' `
                -Notes ("Multiple candidate AD computer objects found: {0}" -f (($matches | Select-Object -ExpandProperty Name) -join ';'))
        }
    } catch {
        return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
            -ADStatus 'ad_query_failed' `
            -ADProbeMethod 'active_directory_module' `
            -Notes $_.Exception.Message
    }

    return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
        -ADStatus 'ad_no_match' `
        -ADProbeMethod 'active_directory_module' `
        -Notes 'No matching AD computer object found.'
}

function Find-WithDsquery {
    param(
        [string]$Identifier,
        [string]$IdentifierType
    )

    if ($IdentifierType -ne 'hostname') {
        return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
            -ADStatus 'ad_probe_limited' `
            -ADProbeMethod 'dsquery_hostname_only' `
            -Notes 'dsquery fallback only supports hostname/name lookup in this script.'
    }

    try {
        $raw = & dsquery.exe computer -name $Identifier 2>&1
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $line = @($raw | Where-Object { $_ -and $_.ToString().Trim() } | Select-Object -First 1)[0]
            $host = ''
            if ($line -match '^"CN=([^,"]+)') { $host = $matches[1] }
            elseif ($line -match '^CN=([^,]+)') { $host = $matches[1] }
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADHostname $host `
                -DirectoryPath ([string]$line) `
                -ADStatus 'ad_object_found' `
                -ADProbeMethod 'dsquery_computer_name' `
                -Notes 'Resolved through dsquery fallback.'
        }
        return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
            -ADStatus 'ad_no_match' `
            -ADProbeMethod 'dsquery_computer_name' `
            -Notes (($raw | Out-String).Trim())
    } catch {
        return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
            -ADStatus 'ad_query_failed' `
            -ADProbeMethod 'dsquery_computer_name' `
            -Notes $_.Exception.Message
    }
}

if (-not (Test-Path -LiteralPath $Manifest)) {
    throw "Manifest not found: $Manifest"
}

$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$manifestRows = Import-Csv -LiteralPath $Manifest
$hasADModule = $null -ne (Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1)
$hasDsquery = $null -ne (Get-Command dsquery.exe -ErrorAction SilentlyContinue)

$results = foreach ($raw in $manifestRows) {
    $row = ConvertTo-Hashtable $raw
    $identifier = Get-ManifestIdentifier $row
    $identifierType = Get-IdentifierType $identifier

    if ([string]::IsNullOrWhiteSpace($identifier)) {
        New-EvidenceRow -Target '' -IdentifierType 'missing' -ADStatus 'ad_input_missing' -ADProbeMethod 'none' -Notes 'Manifest row did not contain an identifier.'
        continue
    }

    if ($hasADModule) {
        Find-WithADModule -Identifier $identifier -IdentifierType $identifierType -AllowDescriptionSearch:$SearchDescription
        continue
    }

    if ($hasDsquery) {
        Find-WithDsquery -Identifier $identifier -IdentifierType $identifierType
        continue
    }

    New-EvidenceRow -Target $identifier -IdentifierType $identifierType `
        -ADStatus 'ad_probe_unavailable' `
        -ADProbeMethod 'none' `
        -Notes 'Neither ActiveDirectory PowerShell module nor dsquery.exe is available in this runtime.'
}

$results | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
Write-Host ("AD identity evidence written: {0}" -f $Output)
