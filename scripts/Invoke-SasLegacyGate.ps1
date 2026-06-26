function Invoke-SasLegacyGate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ToolPath,

    [switch]$AllowLegacy,

    [string]$PosturePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Config\operational-posture.json')
  )

  if ($AllowLegacy -or $env:SAS_ALLOW_LEGACY_TOOLS -eq '1') {
    Write-Verbose "LEGACY_TOOLS_ENABLED: $ToolPath"
    return $true
  }

  $classification = 'LEGACY_TOOLS_DISABLED'
  if (Test-Path -LiteralPath $PosturePath) {
    try {
      $posture = Get-Content -LiteralPath $PosturePath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($posture.defaults.legacyDisabledClassification) {
        $classification = [string]$posture.defaults.legacyDisabledClassification
      }
    } catch {
      Write-Verbose "Could not read operational posture manifest: $($_.Exception.Message)"
    }
  }

  Write-Error @"
${classification}: $ToolPath
Legacy deployment/mapping tools are preserved but disabled by default for low-waste posture control.
Use -AllowLegacy or set SAS_ALLOW_LEGACY_TOOLS=1 only for authorized deployment lanes.
See docs/OPERATIONAL_POSTURE.md and docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md.
"@
  return $false
}
