[CmdletBinding()]
param(
  [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests/fixtures/deployment/deployment-manifest.fixture.json'),
  [string]$DeploymentId = 'fixture-dry-run',
  [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'output/deployments')
)
$deployScript = Join-Path $PSScriptRoot 'Invoke-AuthorizedAppDeployment.ps1'
& $deployScript -ManifestPath $ManifestPath -DeploymentId $DeploymentId -OutputRoot $OutputRoot -TargetLimit 1
