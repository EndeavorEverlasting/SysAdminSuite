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

function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )

    # Invoke the requested utility from one isolated child PowerShell so Windows PowerShell 5.1
    # preserves the original string[] argument semantics used by the repo. On timeout, taskkill /T
    # terminates only that isolated child tree (wrapper + requested native child), never the caller.
    $payload = [pscustomobject]@{
        file_path = $FilePath
        arguments = @($Arguments)
    } | ConvertTo-Json -Depth 4 -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))

    $child = @'
$ErrorActionPreference = 'Stop'
$p = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))) | ConvertFrom-Json
$lines = @(& ([string]$p.file_path) @($p.arguments | ForEach-Object { [string]$_ }) 2>&1 | ForEach-Object { [string]$_ })
if ($lines.Count -gt 0) { [Console]::Out.Write(($lines -join [Environment]::NewLine)) }
exit [int]$LASTEXITCODE
'@.Replace('__PAYLOAD__', $payload64)

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
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
        if (-not $process.Start()) { throw "Unable to start bounded native wrapper for $FilePath" }
        $childPid = [int]$process.Id
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $treeTerminated = Stop-SasBoundedProcessTree -ProcessId $childPid -TimeoutSeconds 5
            if (-not $process.HasExited) {
                try { $process.Kill() } catch { }
            }
            return [pscustomobject][ordered]@{
                file_path = $FilePath
                arguments = @($Arguments)
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
        [pscustomobject][ordered]@{
            file_path = $FilePath
            arguments = @($Arguments)
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

Export-ModuleMember -Function Invoke-SasBoundedNative
