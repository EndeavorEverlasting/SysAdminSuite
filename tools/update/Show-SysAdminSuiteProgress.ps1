<#
.SYNOPSIS
    Shared stage-based progress helpers for SysAdminSuite field scripts.

.DESCRIPTION
    These helpers show honest stage progress for long-running field operations.
    They intentionally report stage completion only; commands such as git clone
    and git fetch keep their own network/protocol output.
#>
Set-StrictMode -Version Latest

function Show-SysAdminSuiteStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 999)]
        [int]$Step,

        [Parameter(Mandatory)]
        [ValidateRange(1, 999)]
        [int]$Total,

        [Parameter(Mandatory)]
        [string]$Activity,

        [Parameter(Mandatory)]
        [string]$Status
    )

    if ($Step -gt $Total) {
        throw "Step $Step cannot be greater than total $Total."
    }

    $percent = [math]::Round(($Step / $Total) * 100)
    Write-Progress -Activity $Activity -Status "[$Step/$Total] $Status ($percent%)" -PercentComplete $percent
    Write-Host "[$Step/$Total] $Status - $percent%"
}

function Complete-SysAdminSuiteProgress {
    [CmdletBinding()]
    param(
        [string]$Activity = 'SysAdminSuite Update'
    )

    Write-Progress -Activity $Activity -Completed
}
