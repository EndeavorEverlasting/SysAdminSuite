#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )

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
    $powershellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $powershellExe
    $process.StartInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true

    try {
        if (-not $process.Start()) { throw "Unable to start bounded native wrapper for $FilePath" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{
                exit_code = -1
                timed_out = $true
                output = ''
                error = "Timed out after $TimeoutSeconds seconds."
            }
        }
        $process.WaitForExit()
        [pscustomobject]@{
            exit_code = [int]$process.ExitCode
            timed_out = $false
            output = [string]$stdoutTask.Result
            error = [string]$stderrTask.Result
        }
    }
    finally {
        $process.Dispose()
    }
}

Export-ModuleMember -Function Invoke-SasBoundedNative
