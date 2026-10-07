#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
  Contract tests for Config/SoftwareDeploy/ScanSnap package.
  Offline / no remote mutation.
#>

BeforeAll {
  $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $script:pkg = Join-Path $repoRoot 'Config\SoftwareDeploy\ScanSnap'
  $script:ps1 = Join-Path $script:pkg 'Deploy-ScanSnap.ps1'
  $script:cmd = Join-Path $script:pkg 'Deploy-ScanSnap.cmd'
  $script:manifest = Join-Path $script:pkg 'package.manifest.json'
  $script:smoke = Join-Path $script:pkg 'hosts_smoke.txt'
  $script:field = Join-Path $script:pkg 'hosts_field.txt'
  $script:runbook = Join-Path $script:pkg 'Runbook-ScanSnap.md'
  $script:plan = Join-Path $repoRoot 'docs\SCANSNAP_DEPLOY_PLAN.md'
}

Describe 'ScanSnap deploy package layout' {
  It 'Package directory exists' { $script:pkg | Should -Exist }
  It 'Deploy-ScanSnap.ps1 exists' { $script:ps1 | Should -Exist }
  It 'Deploy-ScanSnap.cmd exists' { $script:cmd | Should -Exist }
  It 'package.manifest.json exists' { $script:manifest | Should -Exist }
  It 'hosts_smoke.txt exists' { $script:smoke | Should -Exist }
  It 'hosts_field.txt exists' { $script:field | Should -Exist }
  It 'Runbook-ScanSnap.md exists' { $script:runbook | Should -Exist }
  It 'Durable plan docs/SCANSNAP_DEPLOY_PLAN.md exists' { $script:plan | Should -Exist }
}

Describe 'ScanSnap host lists' {
  It 'Smoke hosts target CheexMcClappeth' {
    $text = Get-Content -LiteralPath $script:smoke -Raw
    $text | Should -Match 'CheexMcClappeth'
  }

  It 'Smoke hosts do not include stale LPW003ASI105' {
    $text = Get-Content -LiteralPath $script:smoke -Raw
    $text | Should -Not -Match 'LPW003ASI105'
  }

  It 'Field hosts include WRH250STR001 and WRH250STR002' {
    $text = Get-Content -LiteralPath $script:field -Raw
    $text | Should -Match 'WRH250STR001'
    $text | Should -Match 'WRH250STR002'
  }

  It 'Field hosts do not include stale LPW003ASI105' {
    $text = Get-Content -LiteralPath $script:field -Raw
    $text | Should -Not -Match 'LPW003ASI105'
  }
}

Describe 'ScanSnap scripts parse and refuse stale host' {
  It 'Deploy-ScanSnap.ps1 parses without syntax errors' {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script:ps1, [ref]$null, [ref]$errors)
    $errors | Should -BeNullOrEmpty
  }

  It 'CMD delegates to Deploy-ScanSnap.ps1 without embedding robocopy/schtasks logic' {
    $cmdText = Get-Content -LiteralPath $script:cmd -Raw
    $cmdText | Should -Match 'Deploy-ScanSnap\.ps1'
    $cmdText | Should -Not -Match 'robocopy'
    $cmdText | Should -Not -Match 'schtasks'
  }

  It 'Engine rejects LPW003ASI105 in ComputerList' {
    { & $script:ps1 -PackageRoot $script:pkg -ComputerList 'LPW003ASI105' -WhatIfPreferenceOverride } |
      Should -Throw -ExpectedMessage '*LPW003ASI105*'
  }

  It 'Classifies precise SMB auth failures including DC-unavailable and logon failure' {
    $raw = Get-Content -LiteralPath $script:ps1 -Raw
    foreach ($state in @('RESOLVE_FAILED', 'UNREACHABLE', 'ACCESS_DENIED', 'ADMIN_SHARE_READY', 'AUTH_DC_UNAVAILABLE', 'LOGON_FAILURE')) {
      $raw | Should -Match $state
    }
    $raw | Should -Match 'Resolve-SsAccessClassFromText'
    $raw | Should -Match 'cannot contact a domain controller'
    $raw | Should -Match 'user name or password is incorrect'
  }

  It 'Uses schtasks SYSTEM remote execution and SoftwareRepo\\ScanSnap staging' {
    $raw = Get-Content -LiteralPath $script:ps1 -Raw
    $raw | Should -Match 'schtasks\.exe'
    $raw | Should -Match '/RU SYSTEM'
    $raw | Should -Match 'SoftwareRepo\\ScanSnap'
    $raw | Should -Not -Match '/MIR'
  }
}

Describe 'ScanSnap manifest starts unbound' {
  It 'Manifest Bound is false until operator binding' {
    $m = Get-Content -LiteralPath $script:manifest -Raw | ConvertFrom-Json
    [bool]$m.Bound | Should -BeFalse
  }

  It 'Manifest does not invent SilentArgs' {
    $m = Get-Content -LiteralPath $script:manifest -Raw | ConvertFrom-Json
    [string]$m.SilentArgs | Should -BeNullOrEmpty
  }
}
