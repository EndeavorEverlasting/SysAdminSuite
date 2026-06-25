# Requires PowerShell 5.1+
<#
.SYNOPSIS
Performs read-only target readiness checks for the Registry Install Diff Pipeline.

.DESCRIPTION
Runs Recon readiness checks for localhost, a single target, or a target list from CSV.
The script is evidence-first and read-only: it does not install software and does not edit
registry, service, or remoting settings.

.PARAMETER Target
Single target to check. Use localhost for local-only checks.

.PARAMETER TargetsCsv
CSV file containing targets. Expected column names include Target, ComputerName,
Hostname, or Name. First non-empty value in those columns is used.

.PARAMETER OutputRoot
Directory for generated outputs. Defaults to exports/registry-install-diff/readiness.

.PARAMETER OutputJson
Optional JSON output file path. If omitted, a run-specific JSON file is created under OutputRoot.

.PARAMETER OutputCsv
Optional CSV output file path. If omitted, a run-specific CSV file is created under OutputRoot.

.EXAMPLE
powershell.exe -File scripts/powershell/Test-TargetReadiness.ps1 -Target localhost

.NOTES
Safety:
- Read-only by design.
- No registry writes.
- No service start/stop operations.
- No WinRM enablement or remoting mutation.
- No write attempts to admin shares.
#>
[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Single')]
    [string]$Target = 'localhost',

    [Parameter(ParameterSetName = 'Csv', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetsCsv,

    [string]$OutputRoot = 'exports/registry-install-diff/readiness',
    [string]$OutputJson,
    [string]$OutputCsv
)

$ErrorActionPreference = 'Stop'

function New-CheckResult {
    param(
        [string]$Name,
        [string]$Status = 'NotChecked',
        [hashtable]$Details = @{},
        [string]$ErrorMessage
    )
    [pscustomobject]@{
        name          = $Name
        status        = $Status
        details       = $Details
        error_message = $ErrorMessage
    }
}

function Get-TargetsFromCsv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "TargetsCsv not found: $Path"
    }
    $rows = @(Import-Csv -LiteralPath $Path)
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        $candidate = $null
        foreach ($name in @('Target', 'ComputerName', 'Hostname', 'Name')) {
            if ($row.PSObject.Properties.Name -contains $name) {
                $value = [string]$row.$name
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $candidate = $value.Trim()
                    break
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $targets.Add($candidate)
        }
    }
    return @($targets | Select-Object -Unique)
}

function Get-PendingRebootEvidence {
    $signals = New-Object System.Collections.Generic.List[string]
    $keyPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($path in $keyPaths) {
        if (Test-Path -LiteralPath $path) { $signals.Add($path) }
    }
    try {
        $sessionMgr = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
        if ($null -ne $sessionMgr.PendingFileRenameOperations) {
            $signals.Add('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations')
        }
    } catch {}
    return @($signals)
}

function Get-OverallStatus {
    param([object[]]$Checks)
    $Checks = @($Checks)
    if (-not $Checks -or $Checks.Count -eq 0) { return 'Unknown' }
    $hasFail = $Checks.status -contains 'Fail'
    $hasPass = $Checks.status -contains 'Pass'
    $allNotChecked = @($Checks | Where-Object { $_.status -ne 'NotChecked' -and $_.status -ne 'Error' }).Count -eq 0
    if ($hasFail -and -not $hasPass) { return 'NotReady' }
    if ($hasFail -and $hasPass) { return 'PartiallyReady' }
    if ($allNotChecked) { return 'Unknown' }
    if ($hasPass) { return 'Ready' }
    return 'Unknown'
}

function Test-TargetReadinessInternal {
    param(
        [string]$TargetName,
        [string]$RunId,
        [datetime]$CheckedAt,
        [string]$JsonPath,
        [string]$CsvPath
    )
    $checks = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $scope = 'unresolved'
    $identityDetails = @{ input_target = $TargetName }
    $resolvedAddresses = @()

    try {
        if ($TargetName -in @('localhost', '.', $env:COMPUTERNAME)) {
            $scope = 'localhost'
            $identityDetails.resolved_hostname = $env:COMPUTERNAME
        } else {
            $scope = 'remote'
            $identityDetails.resolved_hostname = $TargetName
        }
        $checks.Add((New-CheckResult -Name 'TargetIdentity' -Status 'Pass' -Details $identityDetails))
    } catch {
        $scope = 'unresolved'
        $checks.Add((New-CheckResult -Name 'TargetIdentity' -Status 'Error' -Details $identityDetails -ErrorMessage $_.Exception.Message))
        $errors.Add("TargetIdentity: $($_.Exception.Message)")
    }

    try {
        if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
            $dns = Resolve-DnsName -Name $TargetName -ErrorAction Stop
            $resolvedAddresses = @($dns | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique)
            $checks.Add((New-CheckResult -Name 'DnsResolution' -Status 'Pass' -Details @{ resolved_addresses = $resolvedAddresses }))
        } else {
            $checks.Add((New-CheckResult -Name 'DnsResolution' -Status 'NotChecked' -Details @{ reason = 'Resolve-DnsName unavailable' }))
        }
    } catch {
        $checks.Add((New-CheckResult -Name 'DnsResolution' -Status 'Fail' -Details @{ resolved_addresses = @() } -ErrorMessage $_.Exception.Message))
    }

    try {
        if (Get-Command -Name Test-Connection -ErrorAction SilentlyContinue) {
            $reachable = Test-Connection -ComputerName $TargetName -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($reachable) {
                $checks.Add((New-CheckResult -Name 'Reachability' -Status 'Pass' -Details @{ reason = 'ICMP response received' }))
            } else {
                $checks.Add((New-CheckResult -Name 'Reachability' -Status 'Fail' -Details @{ reason = 'No ICMP response; firewall or host policy may block ICMP' }))
            }
        } else {
            $checks.Add((New-CheckResult -Name 'Reachability' -Status 'NotChecked' -Details @{ reason = 'Test-Connection unavailable' }))
        }
    } catch {
        $checks.Add((New-CheckResult -Name 'Reachability' -Status 'Error' -Details @{} -ErrorMessage $_.Exception.Message))
    }

    try {
        if ($scope -eq 'localhost') {
            $checks.Add((New-CheckResult -Name 'AdminShareAccess' -Status 'NotChecked' -Details @{ reason = 'Admin share check is remote-focused' }))
        } else {
            $adminPath = "\\$TargetName\C$"
            $exists = Test-Path -LiteralPath $adminPath -ErrorAction SilentlyContinue
            if ($exists) { $checks.Add((New-CheckResult -Name 'AdminShareAccess' -Status 'Pass' -Details @{ path = $adminPath; access = 'Readable' })) }
            else { $checks.Add((New-CheckResult -Name 'AdminShareAccess' -Status 'Fail' -Details @{ path = $adminPath; access = 'UnavailableOrUnauthorized' })) }
        }
    } catch {
        $checks.Add((New-CheckResult -Name 'AdminShareAccess' -Status 'Error' -Details @{} -ErrorMessage $_.Exception.Message))
    }

    try {
        if (Get-Command -Name Test-WSMan -ErrorAction SilentlyContinue) {
            Test-WSMan -ComputerName $TargetName -ErrorAction Stop | Out-Null
            $checks.Add((New-CheckResult -Name 'WinRMAvailability' -Status 'Pass' -Details @{ reason = 'Test-WSMan succeeded' }))
        } else {
            $checks.Add((New-CheckResult -Name 'WinRMAvailability' -Status 'NotChecked' -Details @{ reason = 'Test-WSMan unavailable' }))
        }
    } catch {
        $checks.Add((New-CheckResult -Name 'WinRMAvailability' -Status 'Fail' -Details @{ reason = 'WinRM not available or inaccessible' } -ErrorMessage $_.Exception.Message))
    }

    try {
        if ($scope -eq 'localhost') { $svc = Get-Service -Name 'RemoteRegistry' -ErrorAction Stop }
        else { $svc = Get-Service -Name 'RemoteRegistry' -ComputerName $TargetName -ErrorAction Stop }
        $svcStatus = if ($svc.Status -eq 'Running') { 'Pass' } else { 'Fail' }
        $checks.Add((New-CheckResult -Name 'RemoteRegistryAvailability' -Status $svcStatus -Details @{ service_status = [string]$svc.Status; startup_type = [string]$svc.StartType }))
    } catch {
        $checks.Add((New-CheckResult -Name 'RemoteRegistryAvailability' -Status 'NotChecked' -Details @{ reason = 'Service state unavailable without remote service access' } -ErrorMessage $_.Exception.Message))
    }

    try {
        if ($scope -eq 'localhost') {
            $signals = @(Get-PendingRebootEvidence)
            if ($signals.Count -gt 0) {
                $checks.Add((New-CheckResult -Name 'PendingRebootSignal' -Status 'Fail' -Details @{ signal_count = $signals.Count; evidence_summary = $signals }))
            } else {
                $checks.Add((New-CheckResult -Name 'PendingRebootSignal' -Status 'Pass' -Details @{ signal_count = 0; evidence_summary = @('No common pending reboot signals found') }))
            }
        } else {
            $checks.Add((New-CheckResult -Name 'PendingRebootSignal' -Status 'NotChecked' -Details @{ reason = 'Remote pending reboot check requires validated remote registry path' }))
        }
    } catch {
        $checks.Add((New-CheckResult -Name 'PendingRebootSignal' -Status 'Error' -Details @{} -ErrorMessage $_.Exception.Message))
    }

    $overall = Get-OverallStatus -Checks @($checks)
    return [pscustomobject]@{
        schema_version = '1.0.0'
        run_id         = $RunId
        checked_at     = $CheckedAt.ToString('o')
        target         = $TargetName
        scope          = $scope
        overall_status = $overall
        checks         = @($checks)
        errors         = @($errors)
        output_paths   = [pscustomobject]@{ json = $JsonPath; csv = $CsvPath }
    }
}

$runId = [guid]::NewGuid().Guid
$checkedAt = Get-Date
if (-not (Test-Path -LiteralPath $OutputRoot)) { New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null }
if (-not $OutputJson) { $OutputJson = Join-Path $OutputRoot "readiness-$runId.json" }
if (-not $OutputCsv) { $OutputCsv = Join-Path $OutputRoot "readiness-$runId.csv" }

$targets = @(if ($PSCmdlet.ParameterSetName -eq 'Csv') { Get-TargetsFromCsv -Path $TargetsCsv } else { $Target })
$targets = @($targets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
if ($targets.Count -eq 0) { throw 'No targets resolved for readiness checks.' }

$results = foreach ($item in $targets) {
    try { Test-TargetReadinessInternal -TargetName $item -RunId $runId -CheckedAt $checkedAt -JsonPath $OutputJson -CsvPath $OutputCsv }
    catch {
        [pscustomobject]@{
            schema_version = '1.0.0'
            run_id = $runId
            checked_at = $checkedAt.ToString('o')
            target = $item
            scope = 'unresolved'
            overall_status = 'Unknown'
            checks = @()
            errors = @($_.Exception.Message)
            output_paths = [pscustomobject]@{ json = $OutputJson; csv = $OutputCsv }
        }
    }
}
$results = @($results)
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding UTF8

$csvRows = foreach ($r in $results) {
    foreach ($c in @($r.checks)) {
        [pscustomobject]@{
            run_id = $r.run_id
            checked_at = $r.checked_at
            target = $r.target
            scope = $r.scope
            overall_status = $r.overall_status
            check_name = $c.name
            check_status = $c.status
            details = ($c.details | ConvertTo-Json -Compress)
            error_message = $c.error_message
        }
    }
}
@($csvRows) | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
$results
