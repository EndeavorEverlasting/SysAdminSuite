#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$candidates = New-Object 'System.Collections.Generic.List[object]'
foreach ($root in @(
    (Join-Path $env:ProgramData 'SysAdminSuite'),
    (Join-Path $env:LOCALAPPDATA 'SysAdminSuite')
)) {
    if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }

    $pointer = Join-Path $root 'active-sas-cmd.txt'
    if (Test-Path -LiteralPath $pointer -PathType Leaf) {
        try {
            $pointed = ([string](Get-Content -LiteralPath $pointer -Raw -ErrorAction Stop)).Trim()
            if ($pointed -and (Test-Path -LiteralPath $pointed -PathType Leaf)) {
                $pointerStamp = (Get-Item -LiteralPath $pointer).LastWriteTimeUtc
                $cmdStamp = (Get-Item -LiteralPath $pointed).LastWriteTimeUtc
                $stamp = if ($pointerStamp -gt $cmdStamp) { $pointerStamp } else { $cmdStamp }
                [void]$candidates.Add([pscustomobject]@{ Path = $pointed; Stamp = $stamp })
            }
        } catch { }
    }

    $cmdPath = Join-Path $root 'bin\sas.cmd'
    if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
        [void]$candidates.Add([pscustomobject]@{
            Path = $cmdPath
            Stamp = (Get-Item -LiteralPath $cmdPath).LastWriteTimeUtc
        })
    }
}

$pick = @($candidates | Sort-Object Stamp -Descending | Select-Object -First 1)
if ($pick.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$pick[0].Path)) {
    throw 'No installed SysAdminSuite sas.cmd launcher was found after refresh.'
}

Write-Output $pick[0].Path
