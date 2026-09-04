#Requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasAutoLogonProgressStageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1,22)]
        [int]$Number
    )

    switch ($Number) {
        1  { 'transport preflight' }
        2  { 'canonical software source resolution' }
        3  { 'source CIFS ticket' }
        4  { 'baseline capture' }
        5  { 'baseline eligibility' }
        6  { 'final-step gate' }
        7  { 'source hash' }
        8  { 'staging/hash verification' }
        9  { 'Probe task create' }
        10 { 'Probe task run' }
        11 { 'Probe result' }
        12 { 'Probe cleanup' }
        13 { 'Install task create' }
        14 { 'Install task run' }
        15 { 'Install result' }
        16 { 'Install cleanup' }
        17 { 'after-state capture' }
        18 { 'staging cleanup' }
        19 { 'restart handoff' }
        20 { 'offline observation' }
        21 { 'online observation' }
        22 { 'restart-task cleanup' }
    }
}

function ConvertTo-SasAutoLogonContiguousProgress {
    <#
    .SYNOPSIS
    Preserves AutoLogon output while filling forward stage-number gaps with explicit SKIP records.

    .DESCRIPTION
    The AutoLogon engine owns deployment behavior and evidence. This function is presentation-only.
    It never contacts a target and never changes an AutoLogon result. The first numbered stage seen
    anchors the stream; no earlier stages are invented. After that anchor, when the underlying console
    stream advances to a later non-adjacent stage, every missing stage is rendered explicitly as SKIP
    before the later stage is shown. Repeated START/PASS/FAIL lines for the same stage remain unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject
    )

    begin {
        $lastStage = $null
    }

    process {
        $text = if ($null -eq $InputObject) { '' } else { [string]$InputObject }
        $match = [regex]::Match($text, '^\[(?<stage>\d{1,2})/22\]\s+')
        if ($match.Success) {
            $stage = [int]$match.Groups['stage'].Value
            if ($null -ne $lastStage -and $stage -gt ($lastStage + 1)) {
                for ($missing = $lastStage + 1; $missing -lt $stage; $missing++) {
                    $name = Get-SasAutoLogonProgressStageName -Number $missing
                    Write-Output ("[{0}/22] {1}: SKIP - underlying path did not enter this stage before advancing to stage {2}." -f $missing,$name,$stage)
                }
            }
            if ($null -eq $lastStage -or $stage -gt $lastStage) {
                $lastStage = $stage
            }
        }
        Write-Output $text
    }
}

Export-ModuleMember -Function Get-SasAutoLogonProgressStageName,ConvertTo-SasAutoLogonContiguousProgress
