#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the bounded Resume Matcher live acceptance chain in Windows WSL.
.DESCRIPTION
    Delegates to Invoke-SasResumeMatcherWorkstation.ps1 with Action Accept and the
    explicit mutation gate. By default it proves saved provider configuration
    without issuing an LLM request. -RequireProviderHealth opts into one bounded
    provider test and possible API usage cost. No API key or model output is
    written to the acceptance artifact.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$Distro,
    [string]$ConfigPath,
    [string]$AppRoot,
    [string]$StateRoot,
    [string]$OutputPath,
    [switch]$RequireProviderHealth
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$service = Join-Path $PSScriptRoot 'Invoke-SasResumeMatcherWorkstation.ps1'
if (-not (Test-Path -LiteralPath $service -PathType Leaf)) {
    throw "Resume Matcher workstation service not found: $service"
}

$invoke = @{
    Action = 'Accept'
    AllowMutation = $true
    Confirm = $false
}
foreach ($entry in @{
    Distro = $Distro
    ConfigPath = $ConfigPath
    AppRoot = $AppRoot
    StateRoot = $StateRoot
    OutputPath = $OutputPath
}.GetEnumerator()) {
    if (-not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
        $invoke[$entry.Key] = $entry.Value
    }
}
if ($RequireProviderHealth) {
    $invoke.RequireProviderHealth = $true
}

if (-not $PSCmdlet.ShouldProcess('Resume Matcher in WSL', 'Run bounded live acceptance')) {
    return
}
& $service @invoke
