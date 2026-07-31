#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Stop-SasBoundedProcessTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [ValidateRange(1,15)][int]$TimeoutSeconds = 5
    )

    $taskkill = Join-Path -Path $env:WINDIR -ChildPath 'System32\taskkill.exe'
    $killer = New-Object Diagnostics.Process
    $killer.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $killer.StartInfo.FileName = $taskkill
    $killer.StartInfo.Arguments = "/PID $ProcessId /T /F"
    $killer.StartInfo.UseShellExecute = $false
    $killer.StartInfo.CreateNoWindow = $true
    $killer.StartInfo.RedirectStandardOutput = $true
    $killer.StartInfo.RedirectStandardError = $true

    try {
        if (-not $killer.Start()) { return $false }
        [void]$killer.StandardOutput.ReadToEndAsync()
        [void]$killer.StandardError.ReadToEndAsync()
        if (-not $killer.WaitForExit($TimeoutSeconds * 1000)) {
            try { $killer.Kill() } catch { }
            return $false
        }
        return ($killer.ExitCode -eq 0 -or $killer.ExitCode -eq 128)
    }
    finally {
        $killer.Dispose()
    }
}

function Invoke-SasBoundedPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $powershellExe = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $powershellExe
    $process.StartInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true

    $startedUtc = (Get-Date).ToUniversalTime()
    try {
        if (-not $process.Start()) { throw 'Unable to start bounded child PowerShell.' }
        $childPid = [int]$process.Id
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $treeTerminated = Stop-SasBoundedProcessTree -ProcessId $childPid -TimeoutSeconds 5
            if (-not $process.HasExited) {
                try { $process.Kill() } catch { }
            }
            return [pscustomobject][ordered]@{
                process_id = $childPid
                exit_code = -1
                timed_out = $true
                timeout_seconds = $TimeoutSeconds
                child_tree_termination_attempted = $true
                child_tree_terminated = $treeTerminated
                output = ''
                error = "Timed out after $TimeoutSeconds seconds."
                started_utc = $startedUtc.ToString('o')
                completed_utc = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
        $process.WaitForExit()
        return [pscustomobject][ordered]@{
            process_id = $childPid
            exit_code = [int]$process.ExitCode
            timed_out = $false
            timeout_seconds = $TimeoutSeconds
            child_tree_termination_attempted = $false
            child_tree_terminated = $false
            output = [string]$stdoutTask.Result
            error = [string]$stderrTask.Result
            started_utc = $startedUtc.ToString('o')
            completed_utc = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )

    # Keep Windows PowerShell 5.1 string[] argument semantics without constructing a fragile
    # native command line. The isolated wrapper and its native child are killed as one tree.
    $payload = [pscustomobject]@{ file_path=$FilePath; arguments=@($Arguments) } | ConvertTo-Json -Depth 4 -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $child = @'
$ErrorActionPreference = 'Stop'
$p = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))) | ConvertFrom-Json
try {
    $lines = @(& ([string]$p.file_path) @($p.arguments | ForEach-Object { [string]$_ }) 2>&1 | ForEach-Object { [string]$_ })
    if ($lines.Count -gt 0) { [Console]::Out.Write(($lines -join [Environment]::NewLine)) }
    exit [int]$LASTEXITCODE
}
catch {
    [Console]::Error.Write($_.Exception.Message)
    exit 1
}
'@.Replace('__PAYLOAD__', $payload64)

    $result = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $TimeoutSeconds
    [pscustomobject][ordered]@{
        file_path = $FilePath
        arguments = @($Arguments)
        process_id = $result.process_id
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        timeout_seconds = $result.timeout_seconds
        child_tree_termination_attempted = $result.child_tree_termination_attempted
        child_tree_terminated = $result.child_tree_terminated
        output = $result.output
        error = $result.error
        started_utc = $result.started_utc
        completed_utc = $result.completed_utc
    }
}

function Test-SasBoundedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Any','Leaf','Container')][string]$PathType = 'Any',
        [ValidateRange(1,60)][int]$TimeoutSeconds = 8
    )

    $payload = [pscustomobject]@{ path=$Path; path_type=$PathType } | ConvertTo-Json -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $child = @'
$ErrorActionPreference = 'Stop'
$p = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))) | ConvertFrom-Json
try {
    $parameters = @{ LiteralPath=[string]$p.path; ErrorAction='Stop' }
    if ([string]$p.path_type -eq 'Leaf') { $parameters.PathType='Leaf' }
    elseif ([string]$p.path_type -eq 'Container') { $parameters.PathType='Container' }
    $exists = [bool](Test-Path @parameters)
    [Console]::Out.Write(([pscustomobject]@{ exists=$exists } | ConvertTo-Json -Compress))
    exit 0
}
catch {
    [Console]::Error.Write($_.Exception.Message)
    exit 1
}
'@.Replace('__PAYLOAD__', $payload64)
    $run = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $TimeoutSeconds
    $exists = $false
    if (-not $run.timed_out -and $run.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$run.output)) {
        try { $exists = [bool](($run.output | ConvertFrom-Json).exists) } catch { }
    }
    [pscustomobject][ordered]@{
        path = $Path
        path_type = $PathType
        exists = $exists
        succeeded = (-not $run.timed_out -and $run.exit_code -eq 0)
        timed_out = $run.timed_out
        exit_code = $run.exit_code
        error = $run.error
    }
}

function New-SasBoundedDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1,60)][int]$TimeoutSeconds = 15
    )
    $path64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Path))
    $child = @'
$ErrorActionPreference = 'Stop'
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PATH__'))
try {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { exit 5 }
    exit 0
}
catch { [Console]::Error.Write($_.Exception.Message); exit 1 }
'@.Replace('__PATH__', $path64)
    $run = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $TimeoutSeconds
    [pscustomobject][ordered]@{ path=$Path; succeeded=(-not $run.timed_out -and $run.exit_code -eq 0); timed_out=$run.timed_out; exit_code=$run.exit_code; error=$run.error }
}

function Copy-SasBoundedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 30
    )
    $payload = [pscustomobject]@{ source=$Source; destination=$Destination } | ConvertTo-Json -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $child = @'
$ErrorActionPreference = 'Stop'
$p = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))) | ConvertFrom-Json
try {
    Copy-Item -LiteralPath ([string]$p.source) -Destination ([string]$p.destination) -Force -ErrorAction Stop
    exit 0
}
catch { [Console]::Error.Write($_.Exception.Message); exit 1 }
'@.Replace('__PAYLOAD__', $payload64)
    $run = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $TimeoutSeconds
    [pscustomobject][ordered]@{ source=$Source; destination=$Destination; succeeded=(-not $run.timed_out -and $run.exit_code -eq 0); timed_out=$run.timed_out; exit_code=$run.exit_code; error=$run.error }
}

function Get-SasBoundedFileHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('SHA256')][string]$Algorithm = 'SHA256',
        [ValidateRange(1,120)][int]$TimeoutSeconds = 30
    )
    $payload = [pscustomobject]@{ path=$Path; algorithm=$Algorithm } | ConvertTo-Json -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $child = @'
$ErrorActionPreference = 'Stop'
$p = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))) | ConvertFrom-Json
try {
    $hash = Get-FileHash -LiteralPath ([string]$p.path) -Algorithm ([string]$p.algorithm) -ErrorAction Stop
    [Console]::Out.Write(([pscustomobject]@{ hash=[string]$hash.Hash } | ConvertTo-Json -Compress))
    exit 0
}
catch { [Console]::Error.Write($_.Exception.Message); exit 1 }
'@.Replace('__PAYLOAD__', $payload64)
    $run = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $TimeoutSeconds
    $hashValue = $null
    if (-not $run.timed_out -and $run.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$run.output)) {
        try { $hashValue = [string](($run.output | ConvertFrom-Json).hash) } catch { }
    }
    [pscustomobject][ordered]@{ path=$Path; hash=$hashValue; succeeded=(-not $run.timed_out -and $run.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace($hashValue)); timed_out=$run.timed_out; exit_code=$run.exit_code; error=$run.error }
}

Export-ModuleMember -Function Invoke-SasBoundedNative,Invoke-SasBoundedPowerShell,Test-SasBoundedPath,New-SasBoundedDirectory,Copy-SasBoundedFile,Get-SasBoundedFileHash
