#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcherPath = Join-Path $repoRoot 'Run-AutoLogonCrashSafe.cmd'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Crash-safe CMD launcher not found: $launcherPath"
}

$tempRoot = Join-Path $env:TEMP ('SAS AutoLogon Cmd Binding ' + [guid]::NewGuid().ToString('N'))
$scriptsRoot = Join-Path $tempRoot 'scripts'
$fixtureLauncher = Join-Path $tempRoot 'Run-AutoLogonCrashSafe.cmd'
$fixtureRunner = Join-Path $scriptsRoot 'Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$receiptPath = Join-Path $tempRoot 'binding-receipt.json'

New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null

$launcherText = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
# Keep the production invocation line byte-for-byte while disabling only the interactive
# pauses so CI can execute the real CMD parameter boundary noninteractively.
$fixtureLauncherText = [regex]::Replace(
    $launcherText,
    '(?im)^\s*pause\s*$',
    'rem pause disabled by AutoLogonCrashSafeCmdBinding fixture'
)
Set-Content -LiteralPath $fixtureLauncher -Value $fixtureLauncherText -Encoding ASCII

$runnerFixture = @'
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ComputerName,
    [string]$RepositoryRoot,
    [switch]$ConfirmDeployment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmDeployment) {
    Write-Error 'FIELD_REGRESSION: ConfirmDeployment was not bound through the CMD launcher.'
    exit 71
}
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    Write-Error 'FIELD_REGRESSION: RepositoryRoot was not bound through the CMD launcher.'
    exit 72
}
if ($ComputerName -ne 'fixture-host.example') {
    Write-Error "FIELD_REGRESSION: unexpected ComputerName '$ComputerName'."
    exit 73
}
if ([string]::IsNullOrWhiteSpace($env:SAS_CMD_BINDING_RECEIPT)) {
    Write-Error 'Fixture receipt path was not supplied.'
    exit 74
}

[pscustomobject][ordered]@{
    computer_name = $ComputerName
    repository_root = $RepositoryRoot
    confirm_deployment = [bool]$ConfirmDeployment
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $env:SAS_CMD_BINDING_RECEIPT -Encoding UTF8
exit 0
'@
Set-Content -LiteralPath $fixtureRunner -Value $runnerFixture -Encoding UTF8

$previousReceipt = $env:SAS_CMD_BINDING_RECEIPT
try {
    $env:SAS_CMD_BINDING_RECEIPT = $receiptPath
    $process = Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/d', '/c', 'call Run-AutoLogonCrashSafe.cmd fixture-host.example') `
        -WorkingDirectory $tempRoot -Wait -PassThru -NoNewWindow

    if ([int]$process.ExitCode -ne 0) {
        throw "Production CMD invocation failed the binding fixture with exit code $($process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw 'Production CMD invocation did not reach the runner fixture.'
    }

    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$receipt.confirm_deployment) {
        throw 'ConfirmDeployment was false after the production CMD invocation.'
    }
    if ([string]$receipt.computer_name -ne 'fixture-host.example') {
        throw "ComputerName binding changed unexpectedly: $($receipt.computer_name)"
    }

    $expectedRoot = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    $actualRoot = [IO.Path]::GetFullPath([string]$receipt.repository_root).TrimEnd('\')
    if (-not $actualRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "RepositoryRoot binding mismatch. Expected '$expectedRoot'; got '$actualRoot'."
    }
}
finally {
    if ($null -eq $previousReceipt) {
        Remove-Item Env:SAS_CMD_BINDING_RECEIPT -ErrorAction SilentlyContinue
    }
    else {
        $env:SAS_CMD_BINDING_RECEIPT = $previousReceipt
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: Run-AutoLogonCrashSafe.cmd preserves RepositoryRoot and -ConfirmDeployment across the Windows CMD -> powershell.exe -File boundary.' -ForegroundColor Green
