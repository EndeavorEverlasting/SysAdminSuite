#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Cybernet COM AutoFix readiness helpers' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:parserScript = Join-Path $script:repoRoot 'scripts/Test-CybernetComPortAutoFixParser.ps1'
    $script:inspectorScript = Join-Path $script:repoRoot 'scripts/Inspect-CybernetComPortAutoFixEvidence.ps1'
  }

  It 'parses the AutoFix script without shell interpolation' {
    & $script:parserScript | Should -Be 'PARSE OK'
  }

  It 'fails clearly instead of reusing stale state when no evidence root exists' {
    $missingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-autofix-missing-' + [guid]::NewGuid().Guid)
    { & $script:inspectorScript -EvidenceRoot $missingRoot } | Should -Throw '*No AutoFix evidence root exists*'
  }
}
