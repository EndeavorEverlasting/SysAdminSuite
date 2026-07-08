[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$DeploymentId = 'fixture-dry-run',
    [string]$OutputRoot
)

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $RepoRoot 'Tests/fixtures/deployment/deployment-manifest.fixture.json'
}

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $RepoRoot 'output/deployments'
}
$deployScript = Join-Path $PSScriptRoot 'Invoke-AuthorizedAppDeployment.ps1'

# For the sanitized fixture, keep the committed manifest portable while resolving
# the local fixture payload to an absolute path for this validation run only.
$ResolvedManifestPath = $ManifestPath
if ($ManifestPath -like '*Tests*fixtures*deployment*deployment-manifest.fixture.json') {
    $fixtureRows = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    foreach ($row in @($fixtureRows)) {
        if (-not [System.IO.Path]::IsPathRooted([string]$row.InstallerPath)) {
            $row.InstallerPath = Join-Path $RepoRoot ([string]$row.InstallerPath)
        }
    }

    $fixtureOutput = Join-Path $OutputRoot $DeploymentId
    New-Item -Path $fixtureOutput -ItemType Directory -Force | Out-Null
    $ResolvedManifestPath = Join-Path $fixtureOutput 'deployment-manifest.resolved.json'
    @($fixtureRows) | ConvertTo-Json -Depth 8 | Set-Content -Path $ResolvedManifestPath -Encoding UTF8
}

& $deployScript -ManifestPath $ResolvedManifestPath -DeploymentId $DeploymentId -OutputRoot $OutputRoot -TargetLimit 1
