# Sibling bootstrap only: resolve repository-owned canonical checkout and force
# the approved Admin Box developer-tools role; caller role overrides fail closed.
$ErrorActionPreference='Stop'
foreach($argument in @($args)){if([string]$argument -match '^-noderole(:|=|$)'){throw 'ADMINBOX_ROLE_OVERRIDE_FORBIDDEN'}}
$resolved=& (Join-Path $PSScriptRoot 'Resolve-SasCanonicalDevelopmentPath.ps1') -RequireCheckout -AsJson | ConvertFrom-Json
$root=$resolved.canonical_development_checkout
$engine=Join-Path $root 'scripts/Invoke-SasAndroidToolchain.ps1'
if(-not (Test-Path -LiteralPath $engine)){throw 'CURRENT_ANDROID_TOOLCHAIN_ENGINE_REQUIRED'}
& $engine -NodeRole adminbox_reference @args
exit $LASTEXITCODE
