#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^autologon-kerberos-s4u-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [switch]$ConfirmExactCleanup,

    [ValidateRange(5,60)]
    [int]$TimeoutSeconds = 15
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmExactCleanup) {
    throw 'Exact AutoLogon run-root cleanup requires -ConfirmExactCleanup.'
}

$remoteRoot = "\\$ComputerName\C$\ProgramData\SysAdminSuite\AutoLogonKerberosS4U\$RunId"
$expectedNames = @(
    'NW_AutoLogon_Setup_x64.exe',
    's4u-probe-worker.ps1',
    's4u-probe-result.json',
    's4u-probe-result.json.tmp',
    's4u-install-worker.ps1',
    's4u-install-result.json',
    's4u-install-result.json.tmp'
)

function Invoke-SasBoundedChildPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Unable to start bounded child PowerShell.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{
                timed_out=$true
                exit_code=-1
                output=''
                error="Timed out after $TimeoutSeconds seconds."
            }
        }
        $process.WaitForExit()
        [pscustomobject]@{
            timed_out = $false
            exit_code = [int]$process.ExitCode
            output = [string]$stdout.Result
            error = [string]$stderr.Result
        }
    }
    finally {
        $process.Dispose()
    }
}

$root64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteRoot))
$inventoryScript = @"
`$ErrorActionPreference = 'Stop'
`$root = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$root64'))
if (-not (Test-Path -LiteralPath `$root -PathType Container)) {
    [pscustomobject]@{ exists=`$false; names=@() } | ConvertTo-Json -Compress
    exit 0
}
`$names = @(Get-ChildItem -LiteralPath `$root -Force -ErrorAction Stop | ForEach-Object { [string]`$_.Name })
[pscustomobject]@{ exists=`$true; names=`$names } | ConvertTo-Json -Depth 4 -Compress
"@

$inventoryProbe = Invoke-SasBoundedChildPowerShell -ScriptText $inventoryScript -TimeoutSeconds $TimeoutSeconds
if ($inventoryProbe.timed_out) { throw 'Timed out inventorying the exact remote AutoLogon run root.' }
if ($inventoryProbe.exit_code -ne 0) { throw "Exact remote run-root inventory failed: $($inventoryProbe.error)" }
$inventory = $inventoryProbe.output | ConvertFrom-Json

$unexpected = @($inventory.names | Where-Object { [string]$_ -notin $expectedNames })
if ($unexpected.Count -gt 0) {
    throw "Exact remote run root contains unexpected entries; refusing cleanup: $($unexpected -join ', ')"
}

if ([bool]$inventory.exists) {
    $cleanupScript = @"
`$ErrorActionPreference = 'Stop'
`$root = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$root64'))
if (Test-Path -LiteralPath `$root -PathType Container) {
    Remove-Item -LiteralPath `$root -Recurse -Force -ErrorAction Stop
}
if (Test-Path -LiteralPath `$root) { exit 5 }
exit 0
"@
    $cleanup = Invoke-SasBoundedChildPowerShell -ScriptText $cleanupScript -TimeoutSeconds $TimeoutSeconds
    if ($cleanup.timed_out) { throw 'Timed out removing the exact remote AutoLogon run root.' }
    if ($cleanup.exit_code -ne 0) { throw "Exact remote AutoLogon run-root removal failed: $($cleanup.error)" }
}

$verifyScript = @"
`$ErrorActionPreference = 'Stop'
`$root = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$root64'))
if (Test-Path -LiteralPath `$root) { exit 5 }
exit 0
"@
$verify = Invoke-SasBoundedChildPowerShell -ScriptText $verifyScript -TimeoutSeconds $TimeoutSeconds
if ($verify.timed_out) { throw 'Timed out verifying exact remote AutoLogon run-root absence.' }
if ($verify.exit_code -ne 0) { throw 'Exact remote AutoLogon run root remains after cleanup.' }

[pscustomobject][ordered]@{
    classification = 'EXACT_REMOTE_AUTOLOGON_RUN_ROOT_CLEANED'
    target = $ComputerName
    run_id = $RunId
    root_existed_before_cleanup = [bool]$inventory.exists
    inventory_names = @($inventory.names)
    exact_run_root_absent = $true
    cleanup_scope = 'exact_autologon_s4u_run_root_only'
}
