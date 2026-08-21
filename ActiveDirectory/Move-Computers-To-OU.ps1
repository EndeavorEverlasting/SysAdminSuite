<#
.SYNOPSIS
  Safely plans and, when explicitly authorized, moves AD computer objects to an approved managed OU.

.DESCRIPTION
  This is intentionally separate from Add-Computers-To-PrintingGroup.ps1. Group membership and OU placement
  are different operations and keep separate proof/rollback contracts.

  Default behavior is plan-only and writes local preflight/plan artifacts. AD mutation requires -Apply plus
  -AuthorizationReference. More than one planned change also requires -ConfirmBatch and a raised -MaxChanges.
  Every applied move is re-read from AD and verified before the next object is touched. A verified move emits
  an Undo-OUMove.ps1 script that will only restore the object while it is still in this run's target OU.

.NOTES
  OU PLACEMENT POLICY (Security / Alex Lent 2025-07-08)
  - Legacy _Workstations\Workstations and _Workstations\Shared_Workstations paths are forbidden.
  - Managed workstation placement belongs under _Workstations\Managed or _Workstations\Managed_Shared.

  This script does not guess an environment-specific target OU and contains no tracked live hostnames.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'Single')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Batch')]
    [ValidateNotNullOrEmpty()]
    [string]$HostListPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetOU,

    [Parameter(ParameterSetName = 'Single')]
    [string]$ExpectedSourceOU,

    [string]$Server,
    [string]$OutputRoot,

    [switch]$Apply,
    [string]$AuthorizationReference,

    [ValidateRange(1, 1000)]
    [int]$MaxChanges = 1,

    [switch]$ConfirmBatch
)

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
    param([Parameter(Mandatory = $true)][string]$DistinguishedName)

    # Match complete DN components, not arbitrary substrings inside another OU value.
    $forbiddenPattern = '(?i)(?:^|,)OU=(?:Workstations|Shared_Workstations),OU=_Workstations(?:,|$)'
    if ($DistinguishedName -match $forbiddenPattern) {
        return $false
    }

    $managedPattern = '(?i)(?:^|,)OU=(?:Managed|Managed_Shared),OU=_Workstations(?:,|$)'
    return [bool]($DistinguishedName -match $managedPattern)
}

function ConvertTo-SasSingleQuotedLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-SasComputer {
    param([Parameter(Mandatory = $true)]$Identity)
    $params = @{
        Identity = $Identity
        Properties = @(
            'DistinguishedName', 'CanonicalName', 'ObjectGUID', 'DNSHostName', 'Enabled',
            'OperatingSystem', 'whenChanged', 'sAMAccountName'
        )
        ErrorAction = 'Stop'
    }
    if ($Server) { $params.Server = $Server }
    return Get-ADComputer @params
}

function Write-SasJson {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8
    )
    $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    throw "ActiveDirectory module is required (install RSAT). $($_.Exception.Message)"
}

if ($PSCmdlet.ParameterSetName -eq 'Batch' -and -not (Test-Path -LiteralPath $HostListPath)) {
    throw "Host list not found: $HostListPath"
}

if (-not (Test-SasApprovedManagedTargetOU -DistinguishedName $TargetOU)) {
    throw "TargetOU is outside the approved managed placement roots or is a forbidden legacy OU. Expected a child of OU=Managed,OU=_Workstations or OU=Managed_Shared,OU=_Workstations."
}

$targetParams = @{ Identity = $TargetOU; Properties = @('DistinguishedName', 'CanonicalName'); ErrorAction = 'Stop' }
if ($Server) { $targetParams.Server = $Server }
try {
    $targetObject = Get-ADOrganizationalUnit @targetParams
} catch {
    throw "Target OU '$TargetOU' was not found or is not readable. $($_.Exception.Message)"
}
$resolvedTargetOU = [string]$targetObject.DistinguishedName
if (-not (Test-SasApprovedManagedTargetOU -DistinguishedName $resolvedTargetOU)) {
    throw "Resolved target OU '$resolvedTargetOU' is not an approved managed placement path."
}

$hosts = if ($PSCmdlet.ParameterSetName -eq 'Single') {
    @($ComputerName.Trim())
} else {
    @(Get-Content -LiteralPath $HostListPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        Sort-Object -Unique)
}
if (-not $hosts -or $hosts.Count -eq 0) {
    throw 'No computer names were supplied.'
}

if ($Apply -and [string]::IsNullOrWhiteSpace($AuthorizationReference)) {
    throw '-AuthorizationReference is required with -Apply (ticket/change/approved pilot reference).'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $localBase = if ($env:LOCALAPPDATA) {
        $env:LOCALAPPDATA
    } elseif ($env:TEMP) {
        $env:TEMP
    } else {
        [System.IO.Path]::GetTempPath()
    }
    $OutputRoot = Join-Path $localBase 'SysAdminSuite\Cache\ActiveDirectory\OUMove'
}

$runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runDir = Join-Path $OutputRoot $runId
$doIO = -not $PSBoundParameters.ContainsKey('WhatIf')
if ($doIO) {
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
}

$preflightPath = Join-Path $runDir 'Preflight.csv'
$planPath = Join-Path $runDir 'Plan.json'
$resultsCsvPath = Join-Path $runDir 'Results.csv'
$resultsJsonPath = Join-Path $runDir 'Results.json'
$undoPath = Join-Path $runDir 'Undo-OUMove.ps1'
$logPath = Join-Path $runDir 'Run.log'

$transcriptStarted = $false
if ($doIO) {
    try {
        Start-Transcript -Path $logPath -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-Warning "Transcript could not be started: $($_.Exception.Message)"
    }
}

try {
    $preflight = New-Object System.Collections.Generic.List[object]
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($hostName in $hosts) {
        $row = [ordered]@{
            Timestamp = (Get-Date).ToString('s')
            Hostname = $hostName
            Found = $false
            ObjectGUID = $null
            DistinguishedName = $null
            SourceOU = $null
            TargetOU = $resolvedTargetOU
            Enabled = $null
            OperatingSystem = $null
            Action = 'None'
            Outcome = 'Planned'
            Error = $null
        }

        try {
            $computer = Get-SasComputer -Identity $hostName
            $sourceOU = Get-SasParentDistinguishedName -DistinguishedName $computer.DistinguishedName
            $row.Found = $true
            $row.ObjectGUID = [string]$computer.ObjectGUID
            $row.DistinguishedName = [string]$computer.DistinguishedName
            $row.SourceOU = $sourceOU
            $row.Enabled = $computer.Enabled
            $row.OperatingSystem = [string]$computer.OperatingSystem

            if ($PSCmdlet.ParameterSetName -eq 'Single' -and -not [string]::IsNullOrWhiteSpace($ExpectedSourceOU) -and
                -not $sourceOU.Equals($ExpectedSourceOU, [System.StringComparison]::OrdinalIgnoreCase)) {
                $row.Outcome = 'SourceMismatch'
                $row.Error = "Expected source OU '$ExpectedSourceOU' but found '$sourceOU'."
            } elseif ($sourceOU.Equals($resolvedTargetOU, [System.StringComparison]::OrdinalIgnoreCase)) {
                $row.Action = 'NoChange'
                $row.Outcome = 'AlreadyInTarget'
            } else {
                $row.Action = 'MoveToOU'
                $row.Outcome = if ($Apply) { 'Pending' } else { 'WouldMove' }
            }

            $preflight.Add([pscustomobject]@{
                SnapshotTime = (Get-Date).ToString('s')
                Hostname = $hostName
                ObjectGUID = [string]$computer.ObjectGUID
                DistinguishedName = [string]$computer.DistinguishedName
                CanonicalName = [string]$computer.CanonicalName
                SourceOU = $sourceOU
                TargetOU = $resolvedTargetOU
                DNSHostName = [string]$computer.DNSHostName
                Enabled = $computer.Enabled
                OperatingSystem = [string]$computer.OperatingSystem
                WhenChanged = $computer.whenChanged
                sAMAccountName = [string]$computer.sAMAccountName
            })
        } catch {
            $row.Outcome = 'LookupFailed'
            $row.Error = ($_.Exception.Message -split "`r?`n")[0]
        }
        $results.Add([pscustomobject]$row)
    }

    $blockingPreflight = @($results | Where-Object { $_.Outcome -in @('LookupFailed', 'SourceMismatch') })
    $plannedChanges = @($results | Where-Object { $_.Action -eq 'MoveToOU' })

    if ($doIO) {
        $preflight | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $preflightPath
        Write-SasJson -Path $planPath -InputObject ([ordered]@{
            schema = 'sysadminsuite/ad-ou-move-plan/v1'
            run_id = $runId
            created_at = (Get-Date).ToString('o')
            mode = if ($Apply) { 'apply' } else { 'plan' }
            parameter_set = $PSCmdlet.ParameterSetName
            authorization_reference = if ($Apply) { $AuthorizationReference } else { $null }
            target_ou = $resolvedTargetOU
            host_count = $hosts.Count
            planned_change_count = $plannedChanges.Count
            max_changes = $MaxChanges
            batch_confirmed = [bool]$ConfirmBatch
            items = @($results)
        })
    }

    if ($Apply) {
        if ($blockingPreflight.Count -gt 0) {
            throw "Preflight failed for $($blockingPreflight.Count) computer(s); no OU moves were attempted. Review $preflightPath."
        }
        if ($plannedChanges.Count -gt $MaxChanges) {
            throw "Planned changes ($($plannedChanges.Count)) exceed -MaxChanges $MaxChanges. The default is one computer for pilot safety."
        }
        if ($plannedChanges.Count -gt 1 -and -not $ConfirmBatch) {
            throw 'More than one OU move requires -ConfirmBatch in addition to an explicit -MaxChanges value.'
        }

        $stopAfterFailure = $false
        foreach ($row in $results) {
            if ($row.Action -ne 'MoveToOU') { continue }
            if ($stopAfterFailure) {
                $row.Outcome = 'SkippedAfterFailure'
                continue
            }

            try {
                # Re-read immediately before mutation. A source OU drift invalidates the preflight snapshot.
                $fresh = Get-SasComputer -Identity ([guid]$row.ObjectGUID)
                $freshSourceOU = Get-SasParentDistinguishedName -DistinguishedName $fresh.DistinguishedName
                if (-not $freshSourceOU.Equals([string]$row.SourceOU, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Source OU changed after preflight from '$($row.SourceOU)' to '$freshSourceOU'."
                }

                $moveParams = @{
                    Identity = [guid]$row.ObjectGUID
                    TargetPath = $resolvedTargetOU
                    ErrorAction = 'Stop'
                }
                if ($Server) { $moveParams.Server = $Server }

                if ($PSCmdlet.ShouldProcess($row.Hostname, "Move AD computer from '$freshSourceOU' to '$resolvedTargetOU'")) {
                    Move-ADObject @moveParams

                    $verified = Get-SasComputer -Identity ([guid]$row.ObjectGUID)
                    $verifiedOU = Get-SasParentDistinguishedName -DistinguishedName $verified.DistinguishedName
                    if (-not $verifiedOU.Equals($resolvedTargetOU, [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Post-move verification failed: object is in '$verifiedOU'."
                    }
                    $row.DistinguishedName = [string]$verified.DistinguishedName
                    $row.Outcome = 'Moved'
                } else {
                    $row.Outcome = 'WhatIf'
                }
            } catch {
                $row.Outcome = 'Failed'
                $row.Error = ($_.Exception.Message -split "`r?`n")[0]
                $stopAfterFailure = $true
            }
        }
    }

    $moved = @($results | Where-Object { $_.Outcome -eq 'Moved' })

    if ($doIO) {
        $results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $resultsCsvPath
        Write-SasJson -Path $resultsJsonPath -InputObject ([ordered]@{
            schema = 'sysadminsuite/ad-ou-move-result/v1'
            run_id = $runId
            completed_at = (Get-Date).ToString('o')
            mode = if ($Apply) { 'apply' } else { 'plan' }
            target_ou = $resolvedTargetOU
            authorization_reference = if ($Apply) { $AuthorizationReference } else { $null }
            moved_count = $moved.Count
            failed_count = @($results | Where-Object { $_.Outcome -eq 'Failed' }).Count
            items = @($results)
        })

        if ($moved.Count -gt 0) {
            $undoLines = New-Object System.Collections.Generic.List[string]
            $undoLines.Add('<# Generated by SysAdminSuite Move-Computers-To-OU.ps1. Restores only objects still in the expected target OU. #>')
            $undoLines.Add('[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = ''High'')]')
            $undoLines.Add('param([string]$Server, [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$AuthorizationReference)')
            $undoLines.Add('$ErrorActionPreference = ''Stop''')
            $undoLines.Add('Import-Module ActiveDirectory -ErrorAction Stop')
            $undoLines.Add('function Get-ParentDn { param([string]$Dn); $p=$Dn -split ''(?<!\\),'',2; if($p.Count -ne 2){throw "Invalid DN: $Dn"}; $p[1] }')
            $undoLines.Add('$items = @(')
            foreach ($row in $moved) {
                $guidLiteral = ConvertTo-SasSingleQuotedLiteral -Value ([string]$row.ObjectGUID)
                $hostLiteral = ConvertTo-SasSingleQuotedLiteral -Value ([string]$row.Hostname)
                $expectedLiteral = ConvertTo-SasSingleQuotedLiteral -Value $resolvedTargetOU
                $restoreLiteral = ConvertTo-SasSingleQuotedLiteral -Value ([string]$row.SourceOU)
                $undoLines.Add("  [pscustomobject]@{ ObjectGUID=$guidLiteral; Hostname=$hostLiteral; ExpectedCurrentOU=$expectedLiteral; RestoreOU=$restoreLiteral }")
            }
            $undoLines.Add(')')
            $undoLines.Add('foreach($item in $items){')
            $undoLines.Add('  $get=@{Identity=[guid]$item.ObjectGUID;Properties=@(''DistinguishedName'');ErrorAction=''Stop''}; if($Server){$get.Server=$Server}')
            $undoLines.Add('  $before=Get-ADComputer @get; $current=Get-ParentDn $before.DistinguishedName')
            $undoLines.Add('  if(-not $current.Equals($item.ExpectedCurrentOU,[System.StringComparison]::OrdinalIgnoreCase)){ throw "Rollback blocked for $($item.Hostname): expected current OU ''$($item.ExpectedCurrentOU)'', found ''$current''." }')
            $undoLines.Add('  if($PSCmdlet.ShouldProcess($item.Hostname,"Restore AD computer to ''$($item.RestoreOU)''")){')
            $undoLines.Add('    $move=@{Identity=[guid]$item.ObjectGUID;TargetPath=$item.RestoreOU;ErrorAction=''Stop''}; if($Server){$move.Server=$Server}; Move-ADObject @move')
            $undoLines.Add('    $after=Get-ADComputer @get; $actual=Get-ParentDn $after.DistinguishedName; if(-not $actual.Equals($item.RestoreOU,[System.StringComparison]::OrdinalIgnoreCase)){ throw "Rollback verification failed for $($item.Hostname): ''$actual''." }')
            $undoLines.Add('    Write-Host "RESTORED: $($item.Hostname) -> $actual"')
            $undoLines.Add('  }')
            $undoLines.Add('}')
            $undoLines -join [Environment]::NewLine | Set-Content -LiteralPath $undoPath -Encoding UTF8
        }
    }

    Write-Host ''
    if ($Apply) {
        Write-Host ("OU MOVE RESULT: {0} moved, {1} failed." -f $moved.Count, @($results | Where-Object { $_.Outcome -eq 'Failed' }).Count)
    } else {
        Write-Host ("OU MOVE PLAN: {0} change(s) would be attempted." -f $plannedChanges.Count)
    }
    Write-Host "Target OU: $resolvedTargetOU"
    if ($doIO) {
        Write-Host "Run       : $runDir"
        Write-Host "Preflight : $preflightPath"
        Write-Host "Plan      : $planPath"
        Write-Host "Results   : $resultsJsonPath"
        if ($moved.Count -gt 0) { Write-Host "Undo      : $undoPath" }
    } else {
        Write-Host 'No files written because -WhatIf was supplied.'
    }

    if (@($results | Where-Object { $_.Outcome -eq 'Failed' }).Count -gt 0) {
        exit 2
    }
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}
