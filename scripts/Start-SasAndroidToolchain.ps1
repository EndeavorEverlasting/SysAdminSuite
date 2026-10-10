# Sibling bootstrap only: resolve repository-owned canonical machine/profile authority.
$ErrorActionPreference='Stop'
$resolved=& (Join-Path $PSScriptRoot 'Resolve-SasCanonicalDevelopmentPath.ps1') -RequireCheckout -AsJson | ConvertFrom-Json
$root=$resolved.canonical_development_checkout
$engine=Join-Path $root 'scripts/Invoke-SasAndroidToolchain.ps1'
if(-not (Test-Path -LiteralPath $engine)){throw 'CURRENT_ANDROID_TOOLCHAIN_ENGINE_REQUIRED'}
& $engine @args
exit $LASTEXITCODE
