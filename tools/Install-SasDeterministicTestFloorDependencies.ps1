<#
.SYNOPSIS
    Installs the exact dependency set used by the deterministic SysAdminSuite test floor.

.DESCRIPTION
    This is the network-bearing setup step for the test floor. The test runner itself
    remains offline/fixture-safe. Versions are intentionally exact so developer and
    GitHub Actions runs do not silently float to a new pytest, Pester, or ws release.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $pythonPackages = @(
        'pytest==8.4.1',
        'websockets==15.0.1',
        'jsonschema==4.25.1'
    )
    $requiredPythonVersion = '3.12.10'
    $pesterVersion = [version]'5.7.1'
    $requiredNodeVersion = 'v20.19.4'
    $nodePackage = 'ws@8.18.3'

    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw 'Python is required before deterministic test-floor dependency bootstrap.'
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'Node/npm is required before deterministic test-floor dependency bootstrap.'
    }

    $pythonRuntimeVersion = (& python -c 'import sys; print(sys.version.split()[0])').Trim()
    if ($LASTEXITCODE -ne 0 -or $pythonRuntimeVersion -ne $requiredPythonVersion) {
        throw "Python $requiredPythonVersion is required; detected '$pythonRuntimeVersion'."
    }
    $nodeRuntimeVersion = (& node -p 'process.version').Trim()
    if ($LASTEXITCODE -ne 0 -or $nodeRuntimeVersion -ne $requiredNodeVersion) {
        throw "Node $requiredNodeVersion is required; detected '$nodeRuntimeVersion'."
    }

    & python -m pip install --disable-pip-version-check --no-input @pythonPackages
    if ($LASTEXITCODE -ne 0) {
        throw "pip dependency bootstrap failed with exit code $LASTEXITCODE."
    }

    $exactPester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq $pesterVersion } |
        Select-Object -First 1
    if (-not $exactPester) {
        Install-Module Pester -RequiredVersion $pesterVersion -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    }

    & npm install --no-save --no-package-lock --ignore-scripts $nodePackage
    if ($LASTEXITCODE -ne 0) {
        throw "npm dependency bootstrap failed with exit code $LASTEXITCODE."
    }

    $pythonVersions = (& python -c 'from importlib.metadata import version; print("pytest="+version("pytest")+";websockets="+version("websockets")+";jsonschema="+version("jsonschema"))').Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Python dependency version verification failed.'
    }
    if ($pythonVersions -ne 'pytest=8.4.1;websockets=15.0.1;jsonschema=4.25.1') {
        throw "Unexpected Python dependency versions: $pythonVersions"
    }

    $installedPester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq $pesterVersion } |
        Select-Object -First 1
    if (-not $installedPester) {
        throw "Pester $pesterVersion was not available after bootstrap."
    }

    $wsVersion = (& node -e "console.log(require('ws/package.json').version)").Trim()
    if ($LASTEXITCODE -ne 0 -or $wsVersion -ne '8.18.3') {
        throw "Unexpected ws dependency version: $wsVersion"
    }

    Write-Host "[PASS] deterministic test-floor dependencies: Python=$pythonRuntimeVersion; Node=$nodeRuntimeVersion; $pythonVersions; Pester=$pesterVersion; ws=$wsVersion"
}
finally {
    Pop-Location
}
