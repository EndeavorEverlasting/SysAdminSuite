[CmdletBinding(DefaultParameterSetName = "Plan")]
param(
    [Parameter(ParameterSetName = "Plan")][switch]$Plan,
    [Parameter(Mandatory, ParameterSetName = "PromptFile")][switch]$Launch,
    [Parameter(Mandatory, ParameterSetName = "PromptText")][switch]$LaunchWithPrompt,
    [Parameter(ParameterSetName = "PromptFile")][Parameter(ParameterSetName = "PromptText")][string]$RepoPath = (Get-Location).Path,
    [Parameter(Mandatory, ParameterSetName = "PromptFile")][string]$PromptPath,
    [Parameter(Mandatory, ParameterSetName = "PromptText")][string]$Prompt,
    [string]$Name = "sysadminsuite-auto-routed",
    [ValidateRange(1, 100)][int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)][int]$MaxTokens = 250000,
    [string]$StopWhen = "The bounded sprint is committed in the isolated worktree, targeted validation passes, and no unrelated files changed.",
    [string]$AgentSwitchboardInstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$PolicyPath,
    [bool]$AllowPaid = $true,
    [bool]$HeavyWorkload = $true,
    [switch]$AllowPeakPaid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required."
}

$AgentSwitchboardInstallRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($AgentSwitchboardInstallRoot))
$router = Join-Path $AgentSwitchboardInstallRoot "Start-AutoRoutedGnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $router -PathType Leaf)) {
    throw @"
AgentSwitchboard model router is not installed:
  $router

From the AgentSwitchboard repository, run:
  pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Install-AgentModelRouter.ps1
"@
}

if (-not $PolicyPath) {
    $PolicyPath = Join-Path $AgentSwitchboardInstallRoot "model-route-policy.json"
}
$PolicyPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PolicyPath))
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "AgentSwitchboard model route policy not found: $PolicyPath"
}

Write-Host "`n=== SysAdminSuite agent/model routing ===" -ForegroundColor Cyan
Write-Host "Authority: AgentSwitchboard"
Write-Host "Router:    $router"
Write-Host "Policy:    $PolicyPath"
Write-Host "Paid:      $AllowPaid"
Write-Host "Heavy:     $HeavyWorkload"

if ($PSCmdlet.ParameterSetName -eq "Plan") {
    & $router `
        -InstallRoot $AgentSwitchboardInstallRoot `
        -PolicyPath $PolicyPath `
        -AllowPaid $AllowPaid `
        -HeavyWorkload $HeavyWorkload `
        -AllowPeakPaid:$AllowPeakPaid `
        -ListRoutes
    return
}

$repo = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RepoPath))
if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
    throw "Target repository does not exist: $repo"
}

$gitInside = & git -C $repo rev-parse --is-inside-work-tree 2>&1
if ($LASTEXITCODE -ne 0 -or ($gitInside | Select-Object -First 1).Trim() -ne "true") {
    throw "Target path is not a Git working tree: $repo"
}
$dirty = @(& git -C $repo status --porcelain=v1 2>&1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect target Git status: $repo"
}
if ($dirty.Count -gt 0) {
    throw "Target repository must be clean before routed GNHF work:`n$($dirty -join [Environment]::NewLine)"
}

$arguments = @{
    RepoPath = $repo
    Name = $Name
    MaxIterations = $MaxIterations
    MaxTokens = $MaxTokens
    StopWhen = $StopWhen
    InstallRoot = $AgentSwitchboardInstallRoot
    PolicyPath = $PolicyPath
    AllowPaid = $AllowPaid
    HeavyWorkload = $HeavyWorkload
    AllowPeakPaid = [bool]$AllowPeakPaid
}

if ($PSCmdlet.ParameterSetName -eq "PromptFile") {
    $resolvedPromptPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PromptPath))
    if (-not (Test-Path -LiteralPath $resolvedPromptPath -PathType Leaf)) {
        throw "Prompt file not found: $resolvedPromptPath"
    }
    $arguments.PromptPath = $resolvedPromptPath
}
else {
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw "-Prompt cannot be blank."
    }
    $arguments.Prompt = $Prompt
}

& $router @arguments
if ($LASTEXITCODE -ne 0) {
    throw "AgentSwitchboard routed sprint failed with exit code $LASTEXITCODE. Review the route selection, GNHF worktree, and launcher logs."
}
