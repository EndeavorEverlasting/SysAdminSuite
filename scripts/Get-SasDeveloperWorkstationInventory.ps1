<#
.SYNOPSIS
    Collects a read-only developer workstation inventory on Windows.
.DESCRIPTION
    Detects WezTerm, shell, tmux (WSL), repository presence, agent commands,
    and AgentSwitchboard availability without installing, upgrading, or mutating
    anything. Emits schema-valid JSON and an English summary.
.PARAMETER ProfilePath
    Path to the developer-workstation-profile sample to resolve eligible profiles.
.PARAMETER OutputPath
    Optional path to write the machine-readable JSON inventory.
.PARAMETER FixtureMode
    When set, emits a synthetic Windows-native fixture instead of probing the host.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$FixtureMode
)

$ErrorActionPreference = "Stop"

function Get-ToolCheck {
    param(
        [string]$Command,
        [string[]]$VersionArgs = @("--version")
    )
    $result = @{ status = "FAIL"; reason = "$Command not found"; version = $null; path = $null }
    try {
        $found = Get-Command $Command -ErrorAction SilentlyContinue
        if ($found) {
            $result.path = $found.Source
            try {
                $output = & $Command @VersionArgs 2>&1 | Select-Object -First 1
                $result.version = "$output".Trim()
                $result.status = "PASS"
                $result.reason = "$Command found with version"
            } catch {
                $result.status = "PASS"
                $result.reason = "$Command found but version not obtainable"
            }
        }
    } catch {}
    return $result
}

function Get-RepoRoot {
    param([string]$StartPath)
    $cursor = $StartPath
    while ($cursor) {
        if ((Test-Path -LiteralPath (Join-Path $cursor "targets/README.md")) -and
            (Test-Path -LiteralPath (Join-Path $cursor "survey"))) {
            return $cursor
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $null
}

function Get-AgentCheck {
    param([string]$AgentId, [string]$Command, [string[]]$VersionArgs = @("--version"))
    $check = Get-ToolCheck -Command $Command -VersionArgs $VersionArgs
    return @{
        agent_id = $AgentId
        status   = $check.status
        reason   = $check.reason
        version  = $check.version
    }
}

function Get-EnglishSummary {
    param($Inventory)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Developer Workstation Inventory")
    $lines.Add("================================")
    $lines.Add("")
    $lines.Add("Platform: $($Inventory.detected_platform)")
    $lines.Add("Environment: $($Inventory.execution_environment)")
    $lines.Add("Generated: $($Inventory.generated_at)")
    $lines.Add("")

    $allChecks = @(
        @{ Name = "WezTerm"; Check = $Inventory.checks.wezterm },
        @{ Name = "Shell"; Check = $Inventory.checks.shell },
        @{ Name = "Multiplexer"; Check = $Inventory.checks.multiplexer },
        @{ Name = "Repository"; Check = $Inventory.checks.repository },
        @{ Name = "AgentSwitchboard"; Check = $Inventory.checks.agent_switchboard }
    )

    foreach ($item in $allChecks) {
        $status = $item.Check.status
        $icon = switch ($status) { "PASS" { "[PASS]" } "SKIP" { "[SKIP]" } "FAIL" { "[FAIL]" } }
        $lines.Add("$icon $($item.Name): $($item.Check.reason)")
    }

    if ($Inventory.checks.wsl -and $Inventory.checks.wsl.status -ne "SKIP") {
        $lines.Add("")
        $lines.Add("WSL Distributions:")
        foreach ($dist in $Inventory.checks.wsl.distributions) {
            $dIcon = switch ($dist.status) { "PASS" { "[PASS]" } "SKIP" { "[SKIP]" } "FAIL" { "[FAIL]" } }
            $lines.Add("  $dIcon $($dist.name): $($dist.reason)")
            if ($dist.tmux) {
                $tIcon = switch ($dist.tmux.status) { "PASS" { "[PASS]" } "SKIP" { "[SKIP]" } "FAIL" { "[FAIL]" } }
                $lines.Add("    $tIcon tmux: $($dist.tmux.reason)")
            }
        }
    }

    $lines.Add("")
    $lines.Add("Agent Commands:")
    foreach ($agent in $Inventory.checks.agent_commands) {
        $aIcon = switch ($agent.status) { "PASS" { "[PASS]" } "SKIP" { "[SKIP]" } "FAIL" { "[FAIL]" } }
        $lines.Add("  $aIcon $($agent.agent_id): $($agent.reason)")
    }

    $lines.Add("")
    $lines.Add("Selected Profile: $($Inventory.selected_profile)")
    $lines.Add("Eligible Profiles: $($Inventory.eligible_profiles -join ', ')")
    $lines.Add("")
    $lines.Add("Proof Ceiling: $($Inventory.proof_ceiling)")

    return $lines -join "`n"
}

if ($FixtureMode) {
    $inventory = @{
        schema_version      = "sas-developer-workstation-inventory/v1"
        generated_at        = (Get-Date).ToUniversalTime().ToString("o")
        detected_platform   = "windows"
        execution_environment = "native"
        checks = @{
            wezterm = @{
                status  = "PASS"
                reason  = "WezTerm found with version"
                version = "20240203-115803-5022569c"
                path    = "C:\Program Files\WezTerm\wezterm.exe"
            }
            shell = @{
                status  = "PASS"
                reason  = "pwsh found with version"
                version = "7.4.3"
                path    = "C:\Program Files\PowerShell\7\pwsh.exe"
            }
            multiplexer = @{
                status  = "SKIP"
                reason  = "tmux not applicable on Windows native"
                version = $null
                path    = $null
            }
            repository = @{
                status        = "PASS"
                reason        = "SysAdminSuite repository detected"
                relative_path = "projects/SysAdminSuite"
            }
            agent_commands = @(
                @{
                    agent_id = "opencode"
                    status   = "PASS"
                    reason   = "opencode found with version"
                    version  = "0.1.0"
                },
                @{
                    agent_id = "agy"
                    status   = "FAIL"
                    reason   = "agy not found"
                    version  = $null
                },
                @{
                    agent_id = "goose"
                    status   = "PASS"
                    reason   = "goose found with version"
                    version  = "1.0.0"
                }
            )
            agent_switchboard = @{
                status  = "FAIL"
                reason  = "AgentSwitchboard not found on PATH"
                version = $null
                path    = $null
            }
            wsl = @{
                status        = "SKIP"
                reason        = "WSL check not performed in fixture mode"
                distributions = @()
            }
        }
        selected_profile  = "windows-native"
        eligible_profiles = @("windows-native")
        proof_ceiling     = "Presence is not successful launch. Version output is not authentication readiness. Inventory does not prove installation or repair."
    }
} else {
    $startTime = Get-Date

    $detectedPlatform = "unsupported"
    $executionEnv = "unknown"

    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        $detectedPlatform = "windows"
        $executionEnv = "native"
        if ($env:WSL_DISTRO_NAME) {
            $executionEnv = "wsl"
        }
    } elseif ($IsLinux) {
        $detectedPlatform = "linux"
        $executionEnv = "native"
    }

    $repoRoot = Get-RepoRoot -StartPath $PSScriptRoot
    $repoCheck = if ($repoRoot) {
        $repoRel = $repoRoot
        $gitRoot = (git -C $repoRoot rev-parse --show-toplevel 2>$null)
        if ($gitRoot) {
            $repoRel = $gitRoot
        }
        @{
            status        = "PASS"
            reason        = "SysAdminSuite repository detected"
            relative_path = $repoRel.Replace('\', '/').Split('/')[-2..-1] -join '/'
        }
    } else {
        @{
            status        = "FAIL"
            reason        = "SysAdminSuite repository not found"
            relative_path = $null
        }
    }

    $weztermCheck = Get-ToolCheck -Command "wezterm" -VersionArgs @("--version")
    $shellCheck = Get-ToolCheck -Command "pwsh" -VersionArgs @("--version")
    if ($shellCheck.status -ne "PASS") {
        $shellCheck = Get-ToolCheck -Command "powershell" -VersionArgs @("--version")
        if ($shellCheck.status -ne "PASS") {
            $shellCheck = Get-ToolCheck -Command "cmd" -VersionArgs @("/c", "ver")
        }
    }

    $multiplexerCheck = if ($detectedPlatform -eq "windows" -and $executionEnv -eq "native") {
        @{ status = "SKIP"; reason = "tmux not applicable on Windows native"; version = $null; path = $null }
    } else {
        Get-ToolCheck -Command "tmux" -VersionArgs @("-V")
    }

    $agentCommands = @()
    foreach ($agent in @(
        @{ id = "opencode"; cmd = "opencode" },
        @{ id = "agy"; cmd = "agy" },
        @{ id = "goose"; cmd = "goose" }
    )) {
        $agentCommands += Get-AgentCheck -AgentId $agent.id -Command $agent.cmd
    }

    $switchboardCheck = Get-ToolCheck -Command "agent-switchboard" -VersionArgs @("--version")

    $wslCheck = @{ status = "SKIP"; reason = "WSL not applicable on this platform"; distributions = @() }
    if ($detectedPlatform -eq "windows" -and $executionEnv -eq "native") {
        try {
            $wslOutput = wsl --list --verbose 2>&1
            if ($LASTEXITCODE -eq 0 -and $wslOutput) {
                $dists = @()
                foreach ($line in $wslOutput) {
                    $trimmed = "$line".Trim() -replace '[\x00-\x1F]', ''
                    if ($trimmed -match '^\*?\s*(\S+)') {
                        $distName = $Matches[1]
                        if ($distName -and $distName -ne "NAME" -and $distName -ne "---") {
                            $dists += @{
                                name   = $distName
                                status = "SKIP"
                                reason = "WSL distribution discovered but tmux check requires inner-session probing"
                                tmux   = @{ status = "SKIP"; reason = "tmux check inside WSL requires WSL session"; version = $null; path = $null }
                            }
                        }
                    }
                }
                $wslCheck = if ($dists.Count -gt 0) {
                    @{ status = "PASS"; reason = "WSL available with $($dists.Count) distribution(s)"; distributions = $dists }
                } else {
                    @{ status = "FAIL"; reason = "WSL listed but no distributions found"; distributions = @() }
                }
            } else {
                $wslCheck = @{ status = "FAIL"; reason = "WSL not available"; distributions = @() }
            }
        } catch {
            $wslCheck = @{ status = "FAIL"; reason = "WSL detection failed"; distributions = @() }
        }
    }

    $eligibleProfiles = @()
    $selectedProfile = $null

    $profileSamplePath = $ProfilePath
    if (-not $profileSamplePath -and $repoRoot) {
        $candidate = Join-Path $repoRoot "Config/developer-workstation-profile.sample.json"
        if (Test-Path $candidate) { $profileSamplePath = $candidate }
    }

    if ($profileSamplePath -and (Test-Path $profileSamplePath)) {
        $profile = Get-Content -LiteralPath $profileSamplePath -Raw | ConvertFrom-Json
        foreach ($ep in $profile.terminal.execution_profiles) {
            if ($ep.enabled -and $ep.platform -eq $detectedPlatform) {
                if ($ep.environment -eq $executionEnv -or ($ep.environment -eq "wsl" -and $wslCheck.status -eq "PASS")) {
                    $eligibleProfiles += $ep.id
                }
            }
        }
        if ($eligibleProfiles.Count -gt 0) {
            $selectedProfile = $eligibleProfiles[0]
        }
    }

    $inventory = @{
        schema_version        = "sas-developer-workstation-inventory/v1"
        generated_at          = $startTime.ToUniversalTime().ToString("o")
        detected_platform     = $detectedPlatform
        execution_environment = $executionEnv
        checks = @{
            wezterm           = $weztermCheck
            shell             = $shellCheck
            multiplexer       = $multiplexerCheck
            repository        = $repoCheck
            agent_commands    = $agentCommands
            agent_switchboard = $switchboardCheck
            wsl               = $wslCheck
        }
        selected_profile  = $selectedProfile
        eligible_profiles = $eligibleProfiles
        proof_ceiling     = "Presence is not successful launch. Version output is not authentication readiness. Inventory does not prove installation or repair."
    }
}

$english = Get-EnglishSummary -Inventory $inventory

$json = $inventory | ConvertTo-Json -Depth 10

if ($OutputPath) {
    $parentDir = Split-Path -Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)

    $summaryPath = $OutputPath -replace '\.json$', '-summary.txt'
    [System.IO.File]::WriteAllText($summaryPath, $english, [System.Text.Encoding]::UTF8)
}

return @{ inventory = $inventory; summary = $english }
