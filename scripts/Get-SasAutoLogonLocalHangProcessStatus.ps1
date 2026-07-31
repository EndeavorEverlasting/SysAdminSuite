#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetToken
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$taskProcesses = @(Get-CimInstance Win32_Process -Filter "Name='schtasks.exe'" -ErrorAction Stop)
$matching = @(
    $taskProcesses |
        Where-Object {
            [string]$_.CommandLine -match [regex]::Escape($TargetToken) -or
            [string]$_.CommandLine -match '(?i)SysAdminSuite-AutoLogonS4U|AutoLogonKerberosS4U'
        }
)

$classification = if ($matching.Count -gt 0) {
    'HUNG_IN_NATIVE_SCHTASKS'
}
elseif ($taskProcesses.Count -gt 0) {
    'OTHER_SCHTASKS_PRESENT'
}
else {
    'LIKELY_HUNG_IN_UNC_RESULT_PROBE'
}

[pscustomobject][ordered]@{
    schema_version = 'sas-autologon-local-hang-process-status/v1'
    classification = $classification
    matching_schtasks_count = $matching.Count
    total_schtasks_count = $taskProcesses.Count
    matching_processes = @($matching | ForEach-Object {
        [pscustomobject][ordered]@{
            pid = [int]$_.ProcessId
            parent_pid = [int]$_.ParentProcessId
            command_line = [string]$_.CommandLine
        }
    })
    all_schtasks_processes = @($taskProcesses | ForEach-Object {
        [pscustomobject][ordered]@{
            pid = [int]$_.ProcessId
            parent_pid = [int]$_.ParentProcessId
            command_line = [string]$_.CommandLine
        }
    })
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
}
