<#
.SYNOPSIS
  Detects the current PowerShell runtime and pivots to the required version.
.DESCRIPTION
  Dot-source this script at the top of any tool that needs a specific PS version.
  It exposes:
    $PSRuntimeVersion   - Major version of the running engine (5 or 7+)
    $PSRuntimeIs5       - $true when running Windows PowerShell 5.x
    $PSRuntimeIs7       - $true when running PowerShell 7+
    Invoke-PSPivot      - Re-launches the calling script under the required engine.

  When a pivot occurs the function writes a structured log line so the user
  understands why a second process was spawned.

.PARAMETER RequiredVersion
  Pass to Invoke-PSPivot: '5' or '7'.

.EXAMPLE
  . "$PSScriptRoot\Resolve-PSRuntime.ps1"
  if ($PSRuntimeIs5 -and $needsPS7Feature) {
      Invoke-PSPivot -RequiredVersion 7 -ScriptPath $PSCommandPath -Arguments $PSBoundParameters
  }
#>

# ---- Runtime detection ----
$script:PSRuntimeVersion = $PSVersionTable.PSVersion.Major
$script:PSRuntimeIs5     = $script:PSRuntimeVersion -le 5
$script:PSRuntimeIs7     = $script:PSRuntimeVersion -ge 7

# Expose as module-scope variables when dot-sourced
Set-Variable -Name PSRuntimeVersion -Value $script:PSRuntimeVersion -Scope 1 -ErrorAction SilentlyContinue
Set-Variable -Name PSRuntimeIs5     -Value $script:PSRuntimeIs5     -Scope 1 -ErrorAction SilentlyContinue
Set-Variable -Name PSRuntimeIs7     -Value $script:PSRuntimeIs7     -Scope 1 -ErrorAction SilentlyContinue

function Invoke-PSPivot {
    <#
    .SYNOPSIS
      Re-launches the calling script under a different PowerShell engine.
    .PARAMETER RequiredVersion
      Target major version: 5 or 7.
    .PARAMETER ScriptPath
      Full path to the script to re-launch. Typically $PSCommandPath.
    .PARAMETER Arguments
      Optional hashtable of parameters to forward.
    .PARAMETER LogFile
      Optional path to append a pivot-log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('5','7')]
        [string]$RequiredVersion,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [hashtable]$Arguments = @{},

        [string]$LogFile
    )

    $currentMajor = $PSVersionTable.PSVersion.Major

    # Already on the right version -- no pivot needed
    if (($RequiredVersion -eq '5' -and $currentMajor -le 5) -or
        ($RequiredVersion -eq '7' -and $currentMajor -ge 7)) {
        Write-Verbose "[Resolve-PSRuntime] Already on PS $currentMajor -- no pivot needed."
        return
    }

    # Locate the target engine
    if ($RequiredVersion -eq '7') {
        $exe = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if (-not $exe) {
            $candidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
            if (Test-Path $candidate) { $exe = $candidate }
        }
        if (-not $exe) {
            Write-Warning "[Resolve-PSRuntime] PIVOT FAILED -- pwsh.exe (PS7) not found. Continuing on PS $currentMajor."
            return
        }
    } else {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $exe)) {
            Write-Warning "[Resolve-PSRuntime] PIVOT FAILED -- powershell.exe (PS5) not found."
            return
        }
    }

    # Build argument string
    $argStr = ''
    foreach ($k in $Arguments.Keys) {
        $v = $Arguments[$k]
        if ($v -is [switch] -and $v.IsPresent) { $argStr += " -$k" }
        elseif ($v -is [bool] -and $v)          { $argStr += " -$k" }
        elseif ($null -ne $v)                    { $argStr += " -$k `"$v`"" }
    }

    # Log the pivot
    $msg = "[Resolve-PSRuntime] PIVOT: PS $currentMajor -> PS $RequiredVersion | Script: $ScriptPath | Engine: $exe"
    Write-Host $msg -ForegroundColor Magenta

    if ($LogFile) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$ts  $msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
    }

    # Launch and exit current process
    $cmd = "& `"$exe`" -NoProfile -File `"$ScriptPath`"$argStr"
    Write-Verbose "[Resolve-PSRuntime] Executing: $cmd"
    & $exe -NoProfile -File $ScriptPath @Arguments
    exit $LASTEXITCODE
}

function Write-PSPivotLog {
    <#
    .SYNOPSIS
      Writes a structured pivot-log entry without actually pivoting.
      Useful when a script detects it CAN run on the current version but
      wants to note the version for diagnostics.
    #>
    [CmdletBinding()]
    param(
        [string]$Context = 'General',
        [string]$LogFile
    )
    $msg = "[Resolve-PSRuntime] Running on PS $($PSVersionTable.PSVersion) | Context: $Context"
    Write-Verbose $msg
    if ($LogFile) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$ts  $msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

