Set-StrictMode -Version Latest

$script:SasProgressStates = @('running', 'waiting', 'complete', 'failed', 'skipped')

function Test-SasProgressEnabled {
    [CmdletBinding()]
    param([switch]$NoProgress)

    if ($NoProgress) { return $false }
    return $env:SAS_PROGRESS -notmatch '^(0|false|no|off)$'
}

function New-SasProgressContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Activity,
        [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$Total,
        [switch]$NoProgress
    )

    [pscustomobject]@{
        Activity = $Activity
        Total = $Total
        Current = 0
        Enabled = Test-SasProgressEnabled -NoProgress:$NoProgress
        Terminal = $false
    }
}

function Write-SasProgressState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [Parameter(Mandatory)][ValidateSet('running', 'waiting', 'complete', 'failed', 'skipped')][string]$State,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Status,
        [ValidateRange(0, 2147483647)][int]$Current = $Context.Current
    )

    if ($Context.Terminal) { return }
    $bounded = [Math]::Min([Math]::Max($Current, 0), [int]$Context.Total)
    if ($State -eq 'complete') { $bounded = [int]$Context.Total }
    $Context.Current = $bounded
    $percent = [int][Math]::Floor(($bounded / [double]$Context.Total) * 100)
    $line = '[{0}/{1}] {2,-8} {3} - {4}%' -f $bounded, $Context.Total, $State, $Status, $percent

    if ($Context.Enabled) {
        # Write-Host uses the information stream, keeping success output available
        # for CSV/JSON/objects consumed by callers.
        Write-Host $line
        Write-Progress -Activity $Context.Activity -Status $line -PercentComplete $percent
    }

    if ($State -in @('complete', 'failed', 'skipped')) {
        if ($Context.Enabled) { Write-Progress -Activity $Context.Activity -Completed }
        $Context.Terminal = $true
    }
}

Export-ModuleMember -Function Test-SasProgressEnabled, New-SasProgressContext, Write-SasProgressState
