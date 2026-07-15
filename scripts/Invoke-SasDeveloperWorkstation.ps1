[CmdletBinding()]
param(
    [ValidateSet('Inventory','Plan','Apply','Start','Status','Stop','Repair','Validate','Rollback')][string]$Mode = 'Inventory',
    [ValidateSet('auto','windows','linux','macos')][string]$Platform = 'auto',
    [ValidateSet('auto','windows-native','windows-wsl','linux-native','unsupported')][string]$ExecutionDomain = 'auto',
    [string]$FixtureScenario,
    [string]$OutputRoot,
    [string]$AgentSwitchboardRoot,
    [switch]$AllowTargetMutation,
    [switch]$BridgePermission,
    [switch]$LaunchGui,
    [int]$TimeoutSeconds = 15
)
$ErrorActionPreference = 'Stop'
$python = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) { $python = Get-Command python3 -ErrorAction Stop | Select-Object -First 1 }
$arguments = @((Join-Path $PSScriptRoot 'Invoke-SasDeveloperWorkstation.py'), '--mode', $Mode, '--platform', $Platform, '--execution-domain', $ExecutionDomain, '--timeout-seconds', [string]$TimeoutSeconds)
if ($FixtureScenario) { $arguments += @('--fixture-scenario', $FixtureScenario) }
if ($OutputRoot) { $arguments += @('--output-root', $OutputRoot) }
if ($AgentSwitchboardRoot) { $arguments += @('--agentswitchboard-root', $AgentSwitchboardRoot) }
if ($AllowTargetMutation) { $arguments += '--allow-target-mutation' }
if ($BridgePermission) { $arguments += '--bridge-permission' }
if ($LaunchGui) { $arguments += '--launch-gui' }
& $python.Source @arguments
exit $LASTEXITCODE
