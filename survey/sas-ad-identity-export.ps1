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

    [switch]$SearchDescription,

    [switch]$IncludeComputerOU,

    [switch]$LookupHostnameAsUser
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

function ConvertTo-NormalizedIdentifier {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ($Value.Trim() -replace '\s+', '').ToUpperInvariant()
}

function Get-IdentifierType {
    param([string]$Value)
    $v = ConvertTo-NormalizedIdentifier $Value
    if (-not $v) { return 'missing' }
    if ($v -match '^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$') { return 'mac' }
    if ($v -match 'HOST|OPR|PC|WKST|WKS') { return 'hostname' }
    if ($v -match '[A-Z]' -and $v -match '\d') { return 'serial_or_asset' }
    return 'identifier'
}

function ConvertTo-LdapEscapedValue {
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
        [string]$ComputerOU = '',
        [string]$LegacyOUWarning = '',
        [string]$ADUserFound = '',
        [string]$ADUserSamAccountName = '',
        [string]$ADUserStatus = '',
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
        ComputerOU = $ComputerOU
        LegacyOUWarning = $LegacyOUWarning
        ADUserFound = $ADUserFound
        ADUserSamAccountName = $ADUserSamAccountName
        ADUserStatus = $ADUserStatus
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

function Get-ShortHostname {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $short = ($Value.Trim() -split '\.')[0]
    return $short.ToUpperInvariant()
}

function Get-ComputerOUPath {
    param([string]$DistinguishedName)
    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }
    $parts = $DistinguishedName -split '(?<!\\),', 2
    if ($parts.Count -lt 2) { return '' }
    return $parts[1]
}

function Get-LegacyOUWarning {
    param([string]$OUPath)
    if ([string]::IsNullOrWhiteSpace($OUPath)) { return '' }
    $forbidden = @(
        '\_Workstations\Legacy',
        '\_Workstations\Old',
        'FORBIDDEN',
        'LEGACY'
    )
    foreach ($pattern in $forbidden) {
        if ($OUPath -match [regex]::Escape($pattern)) {
            return 'LEGACY OU -- must be moved to \_Workstations\Managed\ or \_Workstations\Managed_Shared\ per Security policy'
        }
    }
    if ($OUPath -notmatch 'Managed_Shared' -and $OUPath -match 'Workstations') {
        return 'Computer OU is not under Managed_Shared'
    }
    return ''
}

function Find-ADUserByShortHostname {
    param([string]$Hostname)
    $short = Get-ShortHostname $Hostname
    if (-not $short) {
        return @{
            Found = 'no'
            SamAccountName = ''
            Status = 'ad_user_missing'
            Notes = 'Hostname empty; cannot lookup AD user.'
        }
    }
    try {
        $user = Get-ADUser -Identity $short -Properties SamAccountName, Enabled, DistinguishedName -ErrorAction Stop
        return @{
            Found = 'yes'
            SamAccountName = [string]$user.SamAccountName
            Status = 'ad_user_found'
            Notes = ("Enabled={0}; DN={1}" -f $user.Enabled, $user.DistinguishedName)
        }
    } catch {
        return @{
            Found = 'no'
            SamAccountName = ''
            Status = 'ad_user_missing'
            Notes = $_.Exception.Message
        }
    }
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

    $safe = ConvertTo-LdapEscapedValue $Identifier
    $filter = "(|(name=*$safe*)(dNSHostName=*$safe*)"
    if ($AllowDescriptionSearch) {
        $filter += "(description=*$safe*)"
    }
    $filter += ")"

    try {
        $adMatches = @(Get-ADComputer -LDAPFilter $filter -Properties $props -ResultSetSize 5 -ErrorAction Stop)
        if ($adMatches.Count -eq 1) {
            $m = $adMatches[0]
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADHostname ([string]$m.Name) `
                -DNSHostName ([string]$m.DNSHostName) `
                -ADEnabled ([string]$m.Enabled) `
                -DirectoryPath ([string]$m.DistinguishedName) `
                -ADStatus 'ad_object_found' `
                -ADProbeMethod 'active_directory_module_attribute_search' `
                -Notes ("Matched one AD computer object. whenChanged={0}" -f $m.whenChanged)
        }
        if ($adMatches.Count -gt 1) {
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADStatus 'ad_multiple_matches' `
                -ADProbeMethod 'active_directory_module_attribute_search' `
                -Notes ("Multiple candidate AD computer objects found: {0}" -f (($adMatches | Select-Object -ExpandProperty Name) -join ';'))
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
            $resolvedHost = ''
            if ($line -match '^"CN=([^,"]+)') { $resolvedHost = $matches[1] }
            elseif ($line -match '^CN=([^,]+)') { $resolvedHost = $matches[1] }
            return New-EvidenceRow -Target $Identifier -IdentifierType $IdentifierType `
                -ADHostname $resolvedHost `
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

function Expand-EvidenceRow {
    param(
        [pscustomobject]$Row,
        [string]$Identifier,
        [switch]$WantComputerOU,
        [switch]$WantUserLookup
    )

    $computerOU = ''
    $legacyWarning = ''
    if ($WantComputerOU -and $Row.DirectoryPath) {
        $computerOU = Get-ComputerOUPath $Row.DirectoryPath
        $legacyWarning = Get-LegacyOUWarning $computerOU
    }

    $userFound = ''
    $userSam = ''
    $userStatus = ''
    $userNotes = $Row.Notes
    if ($WantUserLookup) {
        $userLookup = Find-ADUserByShortHostname -Hostname $Identifier
        $userFound = $userLookup.Found
        $userSam = $userLookup.SamAccountName
        $userStatus = $userLookup.Status
        if ($userLookup.Notes) {
            $userNotes = if ($userNotes) { "$userNotes | $($userLookup.Notes)" } else { $userLookup.Notes }
        }
    }

    return New-EvidenceRow -Target $Row.Target -IdentifierType $Row.IdentifierType `
        -ADHostname $Row.ADHostname -DNSHostName $Row.DNSHostName `
        -ADSerial $Row.ADSerial -ADMAC $Row.ADMAC -ADEnabled $Row.ADEnabled `
        -DirectoryPath $Row.DirectoryPath -ComputerOU $computerOU -LegacyOUWarning $legacyWarning `
        -ADUserFound $userFound -ADUserSamAccountName $userSam -ADUserStatus $userStatus `
        -ADStatus $Row.ADStatus -ADProbeMethod $Row.ADProbeMethod -Notes $userNotes
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

    $evidence = $null
    if ($hasADModule) {
        $evidence = Find-WithADModule -Identifier $identifier -IdentifierType $identifierType -AllowDescriptionSearch:$SearchDescription
    } elseif ($hasDsquery) {
        $evidence = Find-WithDsquery -Identifier $identifier -IdentifierType $identifierType
    } else {
        $evidence = New-EvidenceRow -Target $identifier -IdentifierType $identifierType `
            -ADStatus 'ad_probe_unavailable' `
            -ADProbeMethod 'none' `
            -Notes 'Neither ActiveDirectory PowerShell module nor dsquery.exe is available in this runtime.'
    }

    if ($IncludeComputerOU -or $LookupHostnameAsUser) {
        Expand-EvidenceRow -Row $evidence -Identifier $identifier `
            -WantComputerOU:$IncludeComputerOU -WantUserLookup:$LookupHostnameAsUser
    } else {
        $evidence
    }
}

$results | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
Write-Host ("AD identity evidence written: {0}" -f $Output)
