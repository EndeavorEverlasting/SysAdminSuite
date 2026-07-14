#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

Set-StrictMode -Version Latest

Describe 'Cybernet COM AutoFix readiness helpers' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:parserScript = Join-Path $script:repoRoot 'scripts/Test-CybernetComPortAutoFixParser.ps1'
    $script:starterScript = Join-Path $script:repoRoot 'scripts/Start-CybernetComPortAutoFix.ps1'
    $script:inspectorScript = Join-Path $script:repoRoot 'scripts/Inspect-CybernetComPortAutoFixEvidence.ps1'
  }

  It 'parses the AutoFix script without shell interpolation' {
    & $script:parserScript | Should -Be 'PARSE OK'
  }

  It 'parses the elevation helper cleanly' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      $script:starterScript,
      [ref]$tokens,
      [ref]$errors
    ) | Out-Null
    @($errors).Count | Should -Be 0
  }

  It 'fails clearly instead of reusing stale state when no evidence root exists' {
    $missingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sas-autofix-missing-' + [guid]::NewGuid().Guid)
    { & $script:inspectorScript -EvidenceRoot $missingRoot } | Should -Throw '*No AutoFix evidence root exists*'
  }

  It 'accepts an already-correct no-op summary without requiring registry backups' {
    $root = Join-Path $TestDrive 'CybernetCOM'
    $run = Join-Path $root 'autofix_20260713_120000'
    New-Item -ItemType Directory -Path $run -Force | Out-Null
    [pscustomobject]@{
      status = 'already-correct'
      registry_backups = $null
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'autofix-summary.json') -Encoding UTF8

    $output = & $script:inspectorScript -EvidenceRoot $root
    $output | Should -Contain 'ALREADY CORRECT - COM1-COM4 detected; no registry backup or mutation was required.'
  }
}
