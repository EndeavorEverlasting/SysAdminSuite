#Requires -Version 5.1
<#
.SYNOPSIS
    Invokes the operator-safe Resume Matcher workstation lifecycle in WSL.
.DESCRIPTION
    Plan is the default and is read-only. Apply, Start, Stop, and Accept require
    -AllowMutation. Existing clean application clones are not fast-forwarded
    unless -AllowApplicationUpdate is also supplied. Provider health requires
    both -RequireProviderHealth and -ConfirmProviderCharge. Stop terminates only
    the repo-owned tmux session and reports when an unmanaged runtime remains.
    The wrapper never collects or forwards API keys.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Plan', 'Apply', 'Start', 'Status', 'Stop', 'Validate', 'Accept')]
    [string]$Action = 'Plan',

    [string]$Distro,
    [string]$ConfigPath,
    [string]$AppRoot,
    [string]$StateRoot,
    [string]$OutputPath,
    [string]$FixtureRoot,

    [switch]$AllowMutation,
    [switch]$AllowApplicationUpdate,
    [switch]$RequireProviderHealth,
    [switch]$ConfirmProviderCharge
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$mutatingActions = @('Apply', 'Start', 'Stop', 'Accept')
if ($mutatingActions -contains $Action -and -not $AllowMutation) {
    throw "$Action requires -AllowMutation. Plan, Status, and Validate remain non-mutating defaults."
}
if ($AllowApplicationUpdate -and $Action -ne 'Apply') {
    throw '-AllowApplicationUpdate is valid only with -Action Apply.'
}
if ($RequireProviderHealth -and $Action -ne 'Accept') {
    throw '-RequireProviderHealth is valid only with -Action Accept.'
}
if ($ConfirmProviderCharge -and $Action -ne 'Accept') {
    throw '-ConfirmProviderCharge is valid only with -Action Accept.'
}
if ($ConfirmProviderCharge -and -not $RequireProviderHealth) {
    throw '-ConfirmProviderCharge requires -RequireProviderHealth.'
}
if ($RequireProviderHealth -and -not $ConfirmProviderCharge) {
    throw '-RequireProviderHealth requires -ConfirmProviderCharge because the test may consume provider credits.'
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    throw 'wsl.exe was not found. Resume Matcher workstation deployment requires a Windows WSL distribution or direct Bash execution on Linux.'
}

if ([string]::IsNullOrWhiteSpace($Distro)) {
    $distros = @(& $wsl.Source --list --quiet 2>$null | ForEach-Object {
        ("$_" -replace "`0", '').Trim()
    } | Where-Object { $_ -and $_ -notmatch '(?i)docker' })
    if ($distros.Count -ne 1) {
        throw "Specify -Distro explicitly. Detected non-Docker WSL distributions: $($distros -join ', ')"
    }
    $Distro = $distros[0]
}

$bashScriptWindowsPath = Join-Path $PSScriptRoot 'invoke-sas-resume-matcher-workstation-safe.sh'
if (-not (Test-Path -LiteralPath $bashScriptWindowsPath -PathType Leaf)) {
    throw "Resume Matcher safe Bash front door not found: $bashScriptWindowsPath"
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = $Path
    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
    }
    $converted = (& $wsl.Source -d $Distro -- wslpath -a -u $resolved 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($converted)) {
        throw "Unable to convert Windows path for WSL: $Path"
    }
    return $converted.Trim()
}

$bashScript = ConvertTo-WslPath -Path $bashScriptWindowsPath
$arguments = @('-d', $Distro, '--', 'bash', $bashScript, '--action', $Action)
if ($AllowMutation) { $arguments += '--apply' }
if ($AllowApplicationUpdate) { $arguments += '--allow-application-update' }
if ($RequireProviderHealth) { $arguments += '--require-provider-health' }
if ($ConfirmProviderCharge) { $arguments += '--confirm-provider-charge' }

foreach ($pair in @(
    @('--config', $ConfigPath),
    @('--app-root', $AppRoot),
    @('--state-root', $StateRoot),
    @('--output', $OutputPath),
    @('--fixture-root', $FixtureRoot)
)) {
    $flag = $pair[0]
    $value = $pair[1]
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $arguments += $flag
    $arguments += (ConvertTo-WslPath -Path $value)
}

$target = "WSL distribution '$Distro'"
$operation = "Resume Matcher workstation action '$Action'"
if ($mutatingActions -contains $Action -and -not $PSCmdlet.ShouldProcess($target, $operation)) {
    return
}

& $wsl.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Resume Matcher workstation service failed with exit code $LASTEXITCODE."
}
