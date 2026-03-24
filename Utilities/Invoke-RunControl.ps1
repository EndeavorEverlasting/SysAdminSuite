<#
.SYNOPSIS
    File-based stop-signal and status-snapshot helpers for GUI-safe long runs.
#>

function Request-RunStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [string]$Reason = 'User requested stop.',
        [string]$RequestedBy = $env:USERNAME
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $signal = [pscustomobject]@{
        RequestedAt = Get-Date
        RequestedBy = $RequestedBy
        Reason      = $Reason
    }

    $signal | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $signal
}

function Test-RunStopRequested {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $raw = $null
    try { $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop } catch { }

    try {
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'Empty signal.' }
        $signal = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        $signal = [pscustomobject]@{
            RequestedAt = if ($item) { $item.LastWriteTime } else { Get-Date }
            RequestedBy = $null
            Reason      = if ($raw) { $raw.Trim() } else { 'Stop signal file detected.' }
        }
    }

    if (-not $signal.PSObject.Properties['RequestedAt']) {
        $signal | Add-Member -NotePropertyName RequestedAt -NotePropertyValue (Get-Date) -Force
    }

    return $signal
}

function Export-RunStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$State,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Stage,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $snapshot = [pscustomobject]@{
        GeneratedAt = Get-Date
        State       = $State
        Stage       = $Stage
        Message     = $Message
        Data        = $Data
    }

    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $snapshot
}

function Import-RunStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Run status snapshot not found: $Path"
    }

    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}