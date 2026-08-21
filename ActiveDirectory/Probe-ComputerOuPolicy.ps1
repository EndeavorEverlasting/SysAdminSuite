#Requires -Version 5.1
<#
.SYNOPSIS
Read-only Active Directory OU and Group Policy evidence for explicit workstation targets.

.DESCRIPTION
Collects each explicit computer object's current parent OU/container and searches Group Policy for a
policy keyword (default: Imprivata). Matching GPO reports are inspected for link scopes and each
computer OU is checked for direct/inherited matching policy links. The probe writes local JSON/CSV
and ticket-note evidence only. It never moves an AD object, edits a GPO, changes group membership,
or selects/authorizes an OU move.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateCount(1,25)]
    [string[]]$ComputerName,

    [ValidateNotNullOrEmpty()]
    [string]$PolicyKeyword = 'Imprivata',

    [string]$Server,
    [string]$OutputRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasParentDistinguishedName {
    param([Parameter(Mandatory = $true)][string]$DistinguishedName)
    $parts = $DistinguishedName -split '(?<!\\),', 2
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Could not determine parent DN for '$DistinguishedName'."
    }
    return $parts[1]
}

function Test-SasApprovedManagedTargetOU {
    param([AllowNull()][string]$DistinguishedName)
    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return $false }
    $forbiddenPattern = '(?i)(?:^|,)OU=(?:Workstations|Shared_Workstations),OU=_Workstations(?:,|$)'
    if ($DistinguishedName -match $forbiddenPattern) { return $false }
    $managedPattern = '(?i)(?:^|,)OU=(?:Managed|Managed_Shared),OU=_Workstations(?:,|$)'
    return [bool]($DistinguishedName -match $managedPattern)
}

function Get-SasAdComputer {
    param([Parameter(Mandatory = $true)][string]$Identity)
    $params = @{
        Identity = $Identity
        Properties = @('DistinguishedName','CanonicalName','ObjectGUID','DNSHostName','Enabled','OperatingSystem','Description')
        ErrorAction = 'Stop'
    }
    if ($Server) { $params.Server = $Server }
    return Get-ADComputer @params
}

function Get-SasAdOu {
    param([Parameter(Mandatory = $true)][string]$Identity)
    $params = @{
        Identity = $Identity
        Properties = @('DistinguishedName','CanonicalName','Description','ManagedBy')
        ErrorAction = 'Stop'
    }
    if ($Server) { $params.Server = $Server }
    return Get-ADOrganizationalUnit @params
}

function Get-SasAllOus {
    $params = @{
        Filter = '*'
        Properties = @('DistinguishedName','CanonicalName','Description')
        ErrorAction = 'Stop'
    }
    if ($Server) { $params.Server = $Server }
    return @(Get-ADOrganizationalUnit @params)
}

function Get-SasMatchingGpos {
    param([Parameter(Mandatory = $true)][string]$Keyword)
    $escaped = [regex]::Escape($Keyword)
    return @(Get-GPO -All -ErrorAction Stop | Where-Object {
        ([string]$_.DisplayName -match $escaped) -or ([string]$_.Description -match $escaped)
    })
}

function Get-SasPolicyLinksFromReport {
    param([Parameter(Mandatory = $true)]$Gpo)
    [xml]$xml = Get-GPOReport -Guid $Gpo.Id -ReportType Xml -ErrorAction Stop
    $nodes = @($xml.SelectNodes("//*[local-name()='LinksTo']"))
    $links = New-Object System.Collections.Generic.List[object]
    foreach ($node in $nodes) {
        $somPath = [string]$node.SOMPath
        if ([string]::IsNullOrWhiteSpace($somPath)) { continue }
        $links.Add([pscustomobject][ordered]@{
            som_path = $somPath
            enabled = [string]$node.Enabled
            no_override = [string]$node.NoOverride
        })
    }
    return @($links | ForEach-Object { $_ })
}

function Get-SasInheritanceMatches {
    param(
        [Parameter(Mandatory = $true)][string]$OuDn,
        [Parameter(Mandatory = $true)][hashtable]$MatchingGpoIds
    )
    $matches = New-Object System.Collections.Generic.List[object]
    try {
        $inheritance = Get-GPInheritance -Target $OuDn -ErrorAction Stop
        foreach ($kind in @('GpoLinks','InheritedGpoLinks')) {
            foreach ($link in @($inheritance.$kind)) {
                $id = ([string]$link.GpoId).Trim('{}').ToLowerInvariant()
                if (-not $MatchingGpoIds.ContainsKey($id)) { continue }
                $matches.Add([pscustomobject][ordered]@{
                    relation = if ($kind -eq 'GpoLinks') { 'DIRECT' } else { 'INHERITED' }
                    display_name = [string]$link.DisplayName
                    gpo_id = [string]$link.GpoId
                    enabled = [bool]$link.Enabled
                    enforced = [bool]$link.Enforced
                    target = [string]$link.Target
                })
            }
        }
    }
    catch {
        return @([pscustomobject][ordered]@{
            relation = 'INHERITANCE_QUERY_FAILED'
            display_name = $null
            gpo_id = $null
            enabled = $false
            enforced = $false
            target = $null
            error = ($_.Exception.Message -split "`r?`n")[0]
        })
    }
    return @($matches | ForEach-Object { $_ })
}

try { Import-Module ActiveDirectory -ErrorAction Stop }
catch { throw "ActiveDirectory module is required (install RSAT). $($_.Exception.Message)" }
try { Import-Module GroupPolicy -ErrorAction Stop }
catch { throw "GroupPolicy module is required (install GPMC/RSAT Group Policy tools). $($_.Exception.Message)" }

$targets = @($ComputerName | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
if ($targets.Count -lt 1 -or $targets.Count -gt 25) { throw 'Provide between 1 and 25 explicit computer names.' }
foreach ($target in $targets) {
    if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$') { throw "Invalid computer name: $target" }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
    $OutputRoot = Join-Path $base 'SysAdminSuite\Evidence\ActiveDirectory\OuPolicyProbe'
}
$runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runDir = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$gpos = @(Get-SasMatchingGpos -Keyword $PolicyKeyword)
$gpoIdSet = @{}
foreach ($gpo in $gpos) { $gpoIdSet[([string]$gpo.Id).Trim('{}').ToLowerInvariant()] = $true }

$allOus = @(Get-SasAllOus)
$ouByCanonical = @{}
foreach ($ou in $allOus) {
    $canonical = ([string]$ou.CanonicalName).Trim().TrimEnd('/')
    if (-not [string]::IsNullOrWhiteSpace($canonical)) { $ouByCanonical[$canonical.ToLowerInvariant()] = $ou }
}

$policyEvidence = New-Object System.Collections.Generic.List[object]
$managedPolicyTargets = New-Object System.Collections.Generic.List[string]
foreach ($gpo in $gpos) {
    $links = @(Get-SasPolicyLinksFromReport -Gpo $gpo)
    $resolvedLinks = New-Object System.Collections.Generic.List[object]
    foreach ($link in $links) {
        $canonicalKey = ([string]$link.som_path).Trim().TrimEnd('/').ToLowerInvariant()
        $resolvedOu = if ($ouByCanonical.ContainsKey($canonicalKey)) { $ouByCanonical[$canonicalKey] } else { $null }
        $resolvedDn = if ($null -ne $resolvedOu) { [string]$resolvedOu.DistinguishedName } else { $null }
        $managed = Test-SasApprovedManagedTargetOU -DistinguishedName $resolvedDn
        if ($managed -and -not [string]::IsNullOrWhiteSpace($resolvedDn) -and -not $managedPolicyTargets.Contains($resolvedDn)) {
            [void]$managedPolicyTargets.Add($resolvedDn)
        }
        $resolvedLinks.Add([pscustomobject][ordered]@{
            som_path = [string]$link.som_path
            resolved_ou_dn = $resolvedDn
            resolved_ou_canonical = if ($null -ne $resolvedOu) { [string]$resolvedOu.CanonicalName } else { $null }
            approved_managed_target = $managed
            enabled = [string]$link.enabled
            no_override = [string]$link.no_override
        })
    }
    $policyEvidence.Add([pscustomobject][ordered]@{
        display_name = [string]$gpo.DisplayName
        gpo_id = [string]$gpo.Id
        description = [string]$gpo.Description
        link_count = $resolvedLinks.Count
        links = @($resolvedLinks | ForEach-Object { $_ })
    })
}

$computerEvidence = New-Object System.Collections.Generic.List[object]
foreach ($target in $targets) {
    $entry = [ordered]@{
        hostname = $target
        found = $false
        object_guid = $null
        distinguished_name = $null
        current_parent_dn = $null
        current_parent_canonical = $null
        current_parent_description = $null
        current_parent_is_ou = $false
        enabled = $null
        operating_system = $null
        policy_matches = @()
        error = $null
    }
    try {
        $computer = Get-SasAdComputer -Identity $target
        $parentDn = Get-SasParentDistinguishedName -DistinguishedName ([string]$computer.DistinguishedName)
        $entry.found = $true
        $entry.object_guid = [string]$computer.ObjectGUID
        $entry.distinguished_name = [string]$computer.DistinguishedName
        $entry.current_parent_dn = $parentDn
        $entry.enabled = $computer.Enabled
        $entry.operating_system = [string]$computer.OperatingSystem
        try {
            $ou = Get-SasAdOu -Identity $parentDn
            $entry.current_parent_is_ou = $true
            $entry.current_parent_canonical = [string]$ou.CanonicalName
            $entry.current_parent_description = [string]$ou.Description
            $entry.policy_matches = @(Get-SasInheritanceMatches -OuDn $parentDn -MatchingGpoIds $gpoIdSet)
        }
        catch {
            $entry.error = "Parent is not a readable OU or inheritance could not be queried: $(($_.Exception.Message -split "`r?`n")[0])"
        }
    }
    catch {
        $entry.error = ($_.Exception.Message -split "`r?`n")[0]
    }
    $computerEvidence.Add([pscustomobject]$entry)
}

$uniqueManagedTarget = if ($managedPolicyTargets.Count -eq 1) { $managedPolicyTargets[0] } else { $null }
$probe = [pscustomobject][ordered]@{
    schema = 'sysadminsuite/ad-ou-policy-probe/v1'
    run_id = $runId
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    policy_keyword = $PolicyKeyword
    target_count = $targets.Count
    matching_gpo_count = $policyEvidence.Count
    matching_gpos = @($policyEvidence | ForEach-Object { $_ })
    computers = @($computerEvidence | ForEach-Object { $_ })
    approved_managed_policy_link_targets = @($managedPolicyTargets | ForEach-Object { $_ })
    unique_managed_policy_link_target_dn = $uniqueManagedTarget
    candidate_role = 'read-only policy-link evidence only; not authorization and not automatic move selection'
    target_mutation_performed = $false
    gpo_mutation_performed = $false
    group_membership_mutation_performed = $false
}

$jsonPath = Join-Path $runDir 'Probe.json'
$computerCsvPath = Join-Path $runDir 'Computers.csv'
$policyCsvPath = Join-Path $runDir 'PolicyLinks.csv'
$ticketPath = Join-Path $runDir 'TicketNotes.txt'
$probe | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
@($computerEvidence | ForEach-Object { $_ }) | Select-Object hostname,found,object_guid,current_parent_dn,current_parent_canonical,current_parent_is_ou,enabled,operating_system,error | Export-Csv -LiteralPath $computerCsvPath -NoTypeInformation -Encoding UTF8
@($policyEvidence | ForEach-Object {
    $gpo = $_
    foreach ($link in @($gpo.links)) {
        [pscustomobject]@{
            policy_keyword = $PolicyKeyword
            gpo_display_name = $gpo.display_name
            gpo_id = $gpo.gpo_id
            som_path = $link.som_path
            resolved_ou_dn = $link.resolved_ou_dn
            resolved_ou_canonical = $link.resolved_ou_canonical
            approved_managed_target = $link.approved_managed_target
            link_enabled = $link.enabled
            no_override = $link.no_override
        }
    }
}) | Export-Csv -LiteralPath $policyCsvPath -NoTypeInformation -Encoding UTF8

$ticket = New-Object System.Collections.Generic.List[string]
$ticket.Add("SysAdminSuite AD OU / policy evidence - $PolicyKeyword")
$ticket.Add("Generated UTC: $($probe.generated_utc)")
$ticket.Add('Read-only probe: no AD object, GPO, or group membership mutation was performed.')
$ticket.Add('')
$ticket.Add("Matching GPOs: $($probe.matching_gpo_count)")
foreach ($gpo in @($probe.matching_gpos)) {
    $ticket.Add("- $($gpo.display_name) [$($gpo.gpo_id)]")
    foreach ($link in @($gpo.links)) {
        $resolved = if ([string]::IsNullOrWhiteSpace([string]$link.resolved_ou_dn)) { 'unresolved/non-OU scope' } else { [string]$link.resolved_ou_dn }
        $ticket.Add("  Link: $($link.som_path) -> $resolved; managed-target=$($link.approved_managed_target)")
    }
}
$ticket.Add('')
foreach ($computer in @($probe.computers)) {
    $ticket.Add("Computer: $($computer.hostname)")
    $ticket.Add("  Current parent: $($computer.current_parent_dn)")
    $ticket.Add("  Canonical OU: $($computer.current_parent_canonical)")
    if (@($computer.policy_matches).Count -gt 0) {
        foreach ($match in @($computer.policy_matches)) {
            if ([string]$match.relation -eq 'INHERITANCE_QUERY_FAILED') {
                $ticket.Add("  Policy inheritance: query failed - $($match.error)")
            } else {
                $ticket.Add("  Policy inheritance: $($match.relation) $($match.display_name) [$($match.gpo_id)] enabled=$($match.enabled) enforced=$($match.enforced)")
            }
        }
    } else {
        $ticket.Add("  Policy inheritance: no matching '$PolicyKeyword' GPO observed")
    }
}
$ticket.Add('')
if ($uniqueManagedTarget) {
    $ticket.Add("Unique approved managed OU linked by matching policy evidence: $uniqueManagedTarget")
    if ($targets.Count -eq 1) {
        $ticket.Add("Plan-only SAS command: sas ad ou plan $($targets[0]) `"$uniqueManagedTarget`"")
    }
} elseif ($managedPolicyTargets.Count -gt 1) {
    $ticket.Add("Multiple approved managed OU links match '$PolicyKeyword'; no automatic move target is selected.")
} else {
    $ticket.Add("No unique approved managed OU link was resolved for '$PolicyKeyword'; no automatic move target is selected.")
}
$ticket.Add('A policy-linked OU is evidence of GPO scope, not proof that OU placement alone installs/configures the application. Validate the actual field effect before promotion.')
$ticket | Set-Content -LiteralPath $ticketPath -Encoding UTF8

Write-Host "AD OU / policy probe complete: $runDir" -ForegroundColor Green
Write-Host "Structured evidence: $jsonPath"
Write-Host "Ticket notes: $ticketPath"
if ($uniqueManagedTarget) { Write-Host "Unique managed policy-linked OU candidate: $uniqueManagedTarget" -ForegroundColor Cyan }
else { Write-Host 'No unique managed policy-linked OU candidate was selected.' -ForegroundColor Yellow }
Write-Host 'TARGET MUTATION: NONE' -ForegroundColor Green
Write-Host 'GPO MUTATION: NONE' -ForegroundColor Green

if (@($computerEvidence | Where-Object { -not $_.found }).Count -gt 0) { exit 20 }
if ($policyEvidence.Count -eq 0) { exit 21 }
exit 0
