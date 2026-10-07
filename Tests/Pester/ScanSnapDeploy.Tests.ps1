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

  It 'Reuses SasNorthwellNetworkAuthority and records multimodal deployment modes' {
    $raw = Get-Content -LiteralPath $script:ps1 -Raw
    $raw | Should -Match 'SasNorthwellNetworkAuthority\.psm1'
    $raw | Should -Match 'Get-SasNorthwellNetworkAuthority'
    $raw | Should -Match 'Resolve-SsDeploymentMode'
    foreach ($mode in @('LAB_LOCAL', 'NORTHWELL_PROTECTED', 'NORTHWELL_VPN', 'UNKNOWN_BLOCKED')) {
      $raw | Should -Match $mode
    }
    $raw | Should -Match 'DeploymentMode'
    $raw | Should -Match 'NetworkRoute'
  }
}

Describe 'ScanSnap manifest binding contract' {
  It 'Manifest Bound is true after package qualification' {
    $m = Get-Content -LiteralPath $script:manifest -Raw | ConvertFrom-Json
    [bool]$m.Bound | Should -BeTrue
  }

  It 'Manifest freezes evidenced installer identity, silent args, and detection' {
    $m = Get-Content -LiteralPath $script:manifest -Raw | ConvertFrom-Json
    [string]$m.InstallerFileName | Should -Be 'WinSSHomeInstaller_4_1_0.exe'
    [string]$m.Type | Should -Be 'exe'
    [string]$m.Sha256 | Should -Match '^[A-F0-9]{64}$'
    [string]$m.SilentArgs | Should -Match '-s'
    [string]$m.SilentArgs | Should -Match '\.iss'
    [string]$m.DetectType | Should -Be 'file'
    [string]$m.DetectValue | Should -Match 'PFU\\ScanSnap\\Home'
  }

  It 'Engine stages InstallShield response sibling beside the installer' {
    $raw = Get-Content -LiteralPath $script:ps1 -Raw
    $raw | Should -Match 'ChangeExtension\(.+\.iss'
    $raw | Should -Match 'stageFiles\.Add\(\$issName\)'
  }
}

Describe 'ScanSnap installer PID delta route' {
  BeforeAll {
    $script:route = Join-Path $script:pkg 'installer-process-route.v1.json'
    $script:resolvePid = Join-Path $script:pkg 'Resolve-ScanSnapInstallerProcess.ps1'
    $script:setupDriver = Join-Path $script:pkg 'Invoke-ScanSnapHomeSetupDriver.ps1'
    $script:silentInstall = Join-Path $script:pkg 'Invoke-ScanSnapSilentInstall.ps1'
  }

  It 'Route manifest and PID scripts exist' {
    $script:route | Should -Exist
    $script:resolvePid | Should -Exist
    $script:setupDriver | Should -Exist
    $script:silentInstall | Should -Exist
  }

  It 'Route schema encodes pid_delta_window_route, silent args, and browser exclusions' {
    $r = Get-Content -LiteralPath $script:route -Raw | ConvertFrom-Json
    [string]$r.schema_version | Should -Be 'scansnap-installer-process-route/v1'
    [string]$r.strategy.name | Should -Be 'pid_delta_window_route'
    [string]$r.window_title_pattern | Should -Match 'ScanSnap Home Setup'
    @($r.exclude_process_names) | Should -Contain 'chrome'
    @($r.process_name_candidates) | Should -Contain 'SSHDownloadInstaller'
    @($r.process_name_candidates) | Should -Contain 'WinSSHomeInstaller_4_1_0'
    [string]$r.silent_install.SilentArgs | Should -Match '-s -f1'
    [string]$r.silent_install.product_name | Should -Be 'ScanSnap Home'
  }

  It 'Resolve/driver/silent scripts parse cleanly' {
    foreach ($path in @($script:resolvePid, $script:setupDriver, $script:silentInstall)) {
      $errors = $null
      $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
      $errors | Should -BeNullOrEmpty
    }
  }

  It 'Resolve and silent scripts refuse second launch when wizard already open' {
    $raw = Get-Content -LiteralPath $script:resolvePid -Raw
    $raw | Should -Match 'Refusing LaunchAndResolve'
    $raw | Should -Match 'AttachExisting'
    $raw | Should -Match 'before_pid_count'
    $silent = Get-Content -LiteralPath $script:silentInstall -Raw
    $silent | Should -Match 'Refusing silent launch'
  }
}


Describe 'ScanSnap first-shot regression hardening' {
  It 'Uses executable detection and non-identifying package provenance' {
    $m = Get-Content -LiteralPath $script:manifest -Raw | ConvertFrom-Json
    [string]$m.DetectValue | Should -Match 'PfuSshMain\.exe$'
    [string]$m.BoundBy | Should -Not -Match '\\|@|LPW003|PA_rperez'
  }

  It 'Keeps live PID observations out of tracked route metadata' {
    $routePath = Join-Path $script:pkg 'installer-process-route.v1.json'
    $r = Get-Content -LiteralPath $routePath -Raw | ConvertFrom-Json
    $r.PSObject.Properties.Name | Should -Not -Contain 'last_observed'
    @($r.path_fragment_candidates) | Should -Not -Contain 'ScanSnap'
    foreach ($candidate in @($r.detection_seed.DetectValueCandidates)) {
      [string]$candidate | Should -Match '\.exe$'
    }
  }

  It 'Makes remote InstallShield execution working-directory aware and exit-gated' {
    $raw = Get-Content -LiteralPath $script:ps1 -Raw
    $raw | Should -Match 'WorkingDirectory'
    $raw | Should -Match 'InstallerSucceeded'
    $raw | Should -Match 'Required InstallShield response file missing'
    $raw | Should -Match 'UNKNOWN_BLOCKED'
  }

  It 'Makes PID resolution private and readiness-gated' {
    $resolve = Get-Content -LiteralPath (Join-Path $script:pkg 'Resolve-ScanSnapInstallerProcess.ps1') -Raw
    $resolve | Should -Match 'installer-route-observed\.json'
    $resolve | Should -Match 'surfaceReady'
    $resolve | Should -Not -Match 'last_observed'
  }

  It 'Serializes silent installs and separates already-installed from new success' {
    $silent = Get-Content -LiteralPath (Join-Path $script:pkg 'Invoke-ScanSnapSilentInstall.ps1') -Raw
    $silent | Should -Match 'System\.Threading\.Mutex'
    $silent | Should -Match 'ALREADY_INSTALLED'
    $silent | Should -Match 'Get-SsActiveProcessTree'
    $silent | Should -Match 'EvidencePath must remain under ignored private evidence root'
  }

  It 'Never sends setup-driver keys after focus failure' {
    $driver = Get-Content -LiteralPath (Join-Path $script:pkg 'Invoke-ScanSnapHomeSetupDriver.ps1') -Raw
    $driver | Should -Match 'FOCUS_FAILED'
    $driver | Should -Match 'preexistingDetection'
    $driver | Should -Match '\$keys -and \$focused'
  }
}
