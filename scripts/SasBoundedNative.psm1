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

    # S4U task creation is a remote RPC operation. A controller-side timeout does not prove that
    # the exact GUID-unique task failed to commit remotely. Give only the AutoLogon S4U create
    # operation a larger bounded window and, if it still times out, reconcile only that exact task.
    # Reconciliation is read-only and finite; the exact /Create mutation is never replayed here.
    $requestedTimeoutSeconds = $TimeoutSeconds
    $effectiveTimeoutSeconds = $TimeoutSeconds
    $timeoutPolicy = 'requested'
    $s4uCreateTarget = $null
    $s4uCreateTaskName = $null
    $isExactS4UCreate = $false

    if ([IO.Path]::GetFileName($FilePath).Equals('schtasks.exe', [StringComparison]::OrdinalIgnoreCase)) {
        $hasCreate = @($Arguments | Where-Object { ([string]$_).Equals('/Create', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 1
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if (([string]$Arguments[$i]).Equals('/S', [StringComparison]::OrdinalIgnoreCase)) {
                $s4uCreateTarget = [string]$Arguments[$i + 1]
            }
            elseif (([string]$Arguments[$i]).Equals('/TN', [StringComparison]::OrdinalIgnoreCase)) {
                $s4uCreateTaskName = [string]$Arguments[$i + 1]
            }
        }
        $isExactS4UCreate = ($hasCreate -and
            -not [string]::IsNullOrWhiteSpace($s4uCreateTarget) -and
            [string]$s4uCreateTaskName -match '^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$')
    }

    if ($isExactS4UCreate -and $effectiveTimeoutSeconds -lt 120) {
        $effectiveTimeoutSeconds = 120
        $timeoutPolicy = 's4u_task_create_minimum_120'
    }

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

    $result = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $effectiveTimeoutSeconds
    $initialTimedOut = [bool]$result.timed_out
    $reconciledAfterTimeout = $false
    $reconciliation = $null
    $reconciliationAttempts = @()
    $reconciliationAttemptLimit = 3
    $reconciliationTimeoutSeconds = [Math]::Max(1, [Math]::Min(30, $requestedTimeoutSeconds))

    if ($isExactS4UCreate -and $initialTimedOut) {
        for ($attempt = 1; $attempt -le $reconciliationAttemptLimit; $attempt++) {
            if ($attempt -gt 1) { Start-Sleep -Seconds 2 }
            $attemptResult = Invoke-SasBoundedNative -FilePath $FilePath -Arguments @(
                '/Query','/S',$s4uCreateTarget,'/TN',$s4uCreateTaskName
            ) -TimeoutSeconds $reconciliationTimeoutSeconds
            $reconciliationAttempts += $attemptResult
            $reconciliation = $attemptResult
            if (-not [bool]$attemptResult.timed_out -and [int]$attemptResult.exit_code -eq 0) {
                $reconciledAfterTimeout = $true
                break
            }
        }
    }

    if ($reconciledAfterTimeout) {
        return [pscustomobject][ordered]@{
            file_path = $FilePath
            arguments = @($Arguments)
            process_id = $result.process_id
            exit_code = 0
            timed_out = $false
            timeout_seconds = $effectiveTimeoutSeconds
            requested_timeout_seconds = $requestedTimeoutSeconds
            timeout_policy = $timeoutPolicy
            initial_timed_out = $true
            reconciled_after_timeout = $true
            reconciliation_attempt_limit = $reconciliationAttemptLimit
            reconciliation_attempt_count = @($reconciliationAttempts).Count
            reconciliation_timeout_seconds = $reconciliationTimeoutSeconds
            reconciliation_attempts = @($reconciliationAttempts)
            reconciliation = $reconciliation
            child_tree_termination_attempted = $result.child_tree_termination_attempted
            child_tree_terminated = $result.child_tree_terminated
            output = [string]$reconciliation.output
            error = ''
            initial_error = [string]$result.error
            started_utc = $result.started_utc
            completed_utc = $reconciliation.completed_utc
        }
    }

    [pscustomobject][ordered]@{
        file_path = $FilePath
        arguments = @($Arguments)
        process_id = $result.process_id
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        timeout_seconds = $effectiveTimeoutSeconds
        requested_timeout_seconds = $requestedTimeoutSeconds
        timeout_policy = $timeoutPolicy
        initial_timed_out = $initialTimedOut
        reconciled_after_timeout = $false
        reconciliation_attempt_limit = $(if ($isExactS4UCreate) { $reconciliationAttemptLimit } else { 0 })
        reconciliation_attempt_count = @($reconciliationAttempts).Count
        reconciliation_timeout_seconds = $(if ($isExactS4UCreate) { $reconciliationTimeoutSeconds } else { 0 })
        reconciliation_attempts = @($reconciliationAttempts)
        reconciliation = $reconciliation
        child_tree_termination_attempted = $result.child_tree_termination_attempted
        child_tree_terminated = $result.child_tree_terminated
        output = $result.output
        error = $result.error
        initial_error = $(if ($initialTimedOut) { [string]$result.error } else { $null })
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

function Invoke-SasNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [ValidateRange(1,86400)][int]$TimeoutSeconds = 30,
        [hashtable]$Environment = @{},
        [string]$CommandLine,
        [string]$StandardOutputPath,
        [string]$StandardErrorPath,
        [ValidateRange(1,10485760)][int]$MaxCaptureCharacters = 1048576
    )

    if ($PSBoundParameters.ContainsKey('CommandLine') -and @($Arguments).Count -gt 0) { throw 'CommandLine and Arguments are mutually exclusive.' }
    # Pump native streams off the PowerShell thread. Capture is bounded; optional
    # adapter-owned files receive the full stream incrementally, including before timeout.
    if (-not ('SasNativeStreamCapture528V1' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
public sealed class SasNativeStreamCapture528V1 : IDisposable {
    private readonly int limit;
    private readonly StringBuilder text = new StringBuilder();
    private readonly object gate = new object();
    private readonly StreamWriter writer;
    private bool truncated;
    public SasNativeStreamCapture528V1(string path, int maximum) {
        limit = maximum;
        if (!String.IsNullOrEmpty(path)) {
            writer = new StreamWriter(new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read), new UTF8Encoding(false));
            writer.AutoFlush = true;
        }
    }
    public Task Start(StreamReader reader) { return Task.Run(() => Pump(reader)); }
    private async Task Pump(StreamReader reader) {
        char[] buffer = new char[4096];
        int count;
        while ((count = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) > 0) {
            lock (gate) {
                int keep = Math.Min(count, limit - text.Length);
                if (keep > 0) text.Append(buffer, 0, keep);
                if (keep < count) truncated = true;
            }
            if (writer != null) writer.Write(buffer, 0, count);
        }
    }
    public string Output { get { lock (gate) { return text.ToString(); } } }
    public bool Truncated { get { lock (gate) { return truncated; } } }
    public void Dispose() { if (writer != null) writer.Dispose(); }
}
"@ -ErrorAction Stop
    }
    # Windows CommandLineToArgvW / CRT quoting. CMD interpretation belongs to its caller.
    $quotedArguments = foreach ($argument in $Arguments) {
        $value = [string]$argument
        if ($value.Length -gt 0 -and $value -notmatch '[\s"]') { $value; continue }
        $builder = New-Object Text.StringBuilder
        [void]$builder.Append('"')
        $slashes = 0
        foreach ($character in $value.ToCharArray()) {
            if ($character -eq '\') { $slashes++; continue }
            if ($character -eq '"') {
                [void]$builder.Append(('\' * (2 * $slashes + 1)))
                [void]$builder.Append('"')
            }
            else {
                if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)) }
                [void]$builder.Append($character)
            }
            $slashes = 0
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
        [void]$builder.Append('"')
        $builder.ToString()
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.Arguments = $(if ($PSBoundParameters.ContainsKey('CommandLine')) { $CommandLine } else { $quotedArguments -join ' ' })
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) {
        if ($null -eq $Environment[$key]) { $process.StartInfo.EnvironmentVariables.Remove([string]$key) }
        else { $process.StartInfo.EnvironmentVariables[[string]$key] = [string]$Environment[$key] }
    }
    $startedUtc = (Get-Date).ToUniversalTime()
    $childPid = $null
    $exitCode = $null
    $timedOut = $false
    $terminationAttempted = $false
    $terminationAcknowledged = $false
    $outputComplete = $false
    $stdout = ''
    $stderr = ''
    $stdoutCapture = $null
    $stderrCapture = $null
    try {
        $stdoutCapture = New-Object SasNativeStreamCapture528V1 -ArgumentList @($StandardOutputPath,$MaxCaptureCharacters)
        $stderrCapture = New-Object SasNativeStreamCapture528V1 -ArgumentList @($StandardErrorPath,$MaxCaptureCharacters)
        if (-not $process.Start()) { throw 'Unable to start native child process.' }
        $childPid = [int]$process.Id
        $stdoutTask = $stdoutCapture.Start($process.StandardOutput)
        $stderrTask = $stderrCapture.Start($process.StandardError)
        $wait = [Diagnostics.Stopwatch]::StartNew()
        $exited = $false
        while (-not $exited -and $wait.ElapsedMilliseconds -lt ($TimeoutSeconds * 1000)) {
            if ($stdoutTask.IsFaulted) { throw $stdoutTask.Exception.GetBaseException() }
            if ($stderrTask.IsFaulted) { throw $stderrTask.Exception.GetBaseException() }
            $remaining = [int][Math]::Max(1, ($TimeoutSeconds * 1000) - $wait.ElapsedMilliseconds)
            $exited = $process.WaitForExit([Math]::Min(100, $remaining))
        }
        if (-not $exited) {
            $timedOut = $true
            # Only the still-owned live process is eligible for PID-bound cleanup.
            if (-not $process.HasExited) {
                $terminationAttempted = $true
                $terminationAcknowledged = Stop-SasBoundedProcessTree -ProcessId $childPid -TimeoutSeconds 5
                if (-not $process.HasExited) { try { $process.Kill() } catch { } }
            }
        }
        else { $exitCode = [int]$process.ExitCode }

        # A descendant can retain redirected handles after the root exits. Never call
        # parameterless WaitForExit or await an unfinished ReadToEndAsync task.
        $drain = [Diagnostics.Stopwatch]::StartNew()
        while ((-not $stdoutTask.IsCompleted -or -not $stderrTask.IsCompleted) -and $drain.ElapsedMilliseconds -lt 2000) {
            [Threading.Thread]::Sleep(20)
        }
        $outputComplete = ($stdoutTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion -and
            $stderrTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion)
        if ($stdoutTask.IsFaulted) { throw $stdoutTask.Exception.GetBaseException() }
        if ($stderrTask.IsFaulted) { throw $stderrTask.Exception.GetBaseException() }
        $stdout = $stdoutCapture.Output
        $stderr = $stderrCapture.Output
        [pscustomobject][ordered]@{
            process_id = $childPid
            exit_code = $exitCode
            timed_out = $timedOut
            timeout_seconds = $TimeoutSeconds
            output = $stdout
            error = $stderr
            started_utc = $startedUtc.ToString('o')
            completed_utc = (Get-Date).ToUniversalTime().ToString('o')
            child_tree_termination_attempted = $terminationAttempted
            # This is taskkill acknowledgment, never independently verified descendant absence.
            child_tree_terminated = $terminationAcknowledged
            output_complete = $outputComplete
            output_truncated = $stdoutCapture.Truncated
            error_truncated = $stderrCapture.Truncated
        }
    }
    finally {
        if ($null -ne $childPid) {
            if (-not $process.HasExited) {
                [void](Stop-SasBoundedProcessTree -ProcessId $childPid -TimeoutSeconds 5)
                if (-not $process.HasExited) { try { $process.Kill() } catch { } }
            }
            if (-not $outputComplete) {
                try { $process.StandardOutput.Close() } catch { }
                try { $process.StandardError.Close() } catch { }
            }
        }
        if ($null -ne $stdoutCapture) { try { $stdoutCapture.Dispose() } catch { } }
        if ($null -ne $stderrCapture) { try { $stderrCapture.Dispose() } catch { } }
        $process.Dispose()
    }
}
Export-ModuleMember -Function Invoke-SasNativeProcess,Invoke-SasBoundedNative,Invoke-SasBoundedPowerShell,Test-SasBoundedPath,New-SasBoundedDirectory,Copy-SasBoundedFile,Get-SasBoundedFileHash
