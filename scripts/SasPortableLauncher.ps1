#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$cachePath = Join-Path $stateRoot 'repo-root.txt'
$PathLengthThreshold = 100
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SasRepoRoot {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $candidate = [IO.Path]::GetFullPath($Path.Trim()) } catch { return $false }
    foreach ($relative in @(
        'Run-AutoLogonOnsite.cmd','Run-CybernetBatchConfiguration.cmd','Probe-CybernetSoftware.cmd',
        'Deploy-CybernetSoftware.cmd','Deploy-CybernetClinicalCore.cmd','Deploy-CybernetProfiledClinicalCore.cmd',
        'Find-SasEvidence.cmd','Refresh-SasOperatorCommand.cmd','scripts\SasNetworkGuard.psm1'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $candidate $relative) -PathType Leaf)) { return $false }
    }
    return $true
}

function Add-SasCandidate {
    param([System.Collections.Generic.List[string]]$List,[AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [IO.Path]::GetFullPath($Path.Trim()) } catch { return }
    if (-not $List.Contains($full)) { [void]$List.Add($full) }
}

function Resolve-SasRepoRoot {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    Add-SasCandidate -List $candidates -Path $env:SAS_REPO_ROOT
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) { try { Add-SasCandidate -List $candidates -Path ((Get-Content -LiteralPath $cachePath -Raw).Trim()) } catch {} }
    try { Add-SasCandidate -List $candidates -Path (& git -C (Get-Location).Path rev-parse --show-toplevel 2>$null | Select-Object -First 1) } catch {}
    foreach ($root in @($env:USERPROFILE,$env:OneDrive,$env:OneDriveCommercial,$env:OneDriveConsumer) | Where-Object { $_ } | Select-Object -Unique) {
        foreach ($relative in @('SysAdminSuite','SysAdminSuite-portable-onsite','SysAdminSuite-Live','dev\SysAdminSuite','Desktop\dev\SysAdminSuite','OG Laptop Backup\Desktop\dev\SysAdminSuite')) {
            Add-SasCandidate -List $candidates -Path (Join-Path $root $relative)
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-SasRepoRoot -Path $candidate) {
            Set-Content -LiteralPath $cachePath -Value $candidate -Encoding ASCII
            return $candidate
        }
    }
    throw 'SysAdminSuite could not be located. Run Install-SasOperatorCommand.cmd once from a valid checkout.'
}

function Get-SasAvailableSubstDrive {
    foreach ($letter in @('S','R','Q','P','O','N','M','L','K','J')) {
        if ($null -eq (Get-PSDrive -Name $letter -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath "${letter}:\")) { return "${letter}:" }
    }
    throw 'No free temporary drive letter is available for the SysAdminSuite short-path alias.'
}

function Invoke-SasPortableRepoCommand {
    param([string]$RepoRoot,[string]$RelativePath,[AllowNull()][string[]]$Arguments)
    $entryPoint = Join-Path $RepoRoot $RelativePath
    $isLocalDrivePath = $RepoRoot -match '^[A-Za-z]:\\'
    if (-not $isLocalDrivePath -or $RepoRoot.Length -lt $PathLengthThreshold) {
        & $entryPoint @Arguments | Out-Host
        return [int]$LASTEXITCODE
    }
    $drive = Get-SasAvailableSubstDrive
    $substExe = Join-Path $env:WINDIR 'System32\subst.exe'
    $created = $false
    $commandExit = 1
    try {
        & $substExe $drive $RepoRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not create temporary short-path alias $drive" }
        $created = $true
        & (Join-Path "$drive\" $RelativePath) @Arguments | Out-Host
        $commandExit = [int]$LASTEXITCODE
    }
    finally { if ($created) { & $substExe $drive '/D' | Out-Null } }
    return $commandExit
}

$repoRoot = Resolve-SasRepoRoot
$normalized = if ($Command) { $Command.Trim().ToLowerInvariant() } else { '' }
$sessionModule = Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
if (Test-Path -LiteralPath $sessionModule -PathType Leaf) { Import-Module $sessionModule -Force }

if ([string]::IsNullOrWhiteSpace($normalized)) {
    Write-Host 'SysAdminSuite operator command' -ForegroundColor Cyan
    Write-Host "Repo: $repoRoot"
    Write-Host ''
    Write-Host '  sas context                          Show persistent operator/session state'
    Write-Host '  sas next                             Show only next network + one next command'
    Write-Host '  sas refresh                          GUEST / INTERNET: refresh origin/main field-ready checkout'
    Write-Host '  sas cybernet Core HOST              PROTECTED NORTHWELL: five clinical apps; AutoLogon untouched; no reboot'
    Write-Host '  sas cybernet Recover HOST           PROTECTED NORTHWELL: exact previous-run cleanup/recovery only'
    Write-Host '  sas cybernet Probe HOST             PROTECTED NORTHWELL: optional read-only readiness'
    Write-Host '  sas cybernet Deploy HOST            PROTECTED NORTHWELL: full Cybernet software profile; readiness included; AutoLogon last; restart included'
    Write-Host '  sas cybernet Plan HOST              Hardware-only Cybernet plan'
    Write-Host '  sas cybernet Apply HOST             Hardware-only Cybernet apply'
    Write-Host '  sas cybernet Validate HOST          Hardware-only Cybernet validation'
    Write-Host '  sas evidence Cybernet               OFFLINE: recover newest Cybernet evidence'
    Write-Host '  sas autologon Remote HOST           PROTECTED NORTHWELL: AutoLogon-only lane; restart included'
    Write-Host '  sas network                          Read-only Northwell network posture'
    Write-Host '  sas repo                             Print resolved repository path'
    Write-Host '  sas open                             Open repository in Explorer'
    Write-Host ''
    Write-Host 'GUEST-SAFE refresh: On Guest/Internet: sas refresh' -ForegroundColor Cyan
    Write-Host 'After refresh, Move to the approved protected network. `sas next` retains the target/lane.' -ForegroundColor Cyan
    Write-Host 'Core completion marker: CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED' -ForegroundColor DarkGray
    Write-Host 'Readiness marker: CYBERNET_DEPLOYMENT_READINESS_READY' -ForegroundColor DarkGray
    Write-Host 'AutoLogon marker: AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED' -ForegroundColor DarkGray
    Write-Host 'Full deployment marker: CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED' -ForegroundColor DarkGray
    Write-Host 'Fixture/live-cert/runtime-proof loops are NOT prerequisites for software deployment completion.' -ForegroundColor Green
    Write-Host 'The standalone Probe is optional diagnosis; it is NOT a prerequisite loop before Deploy.' -ForegroundColor Green
    Write-Host 'Use `sas next` after a terminal/network/conversation change. The harness remembers the lane.' -ForegroundColor Green
    exit 0
}

switch ($normalized) {
    'repo' { Write-Output $repoRoot; exit 0 }
    'open' { Start-Process -FilePath 'explorer.exe' -ArgumentList @($repoRoot) | Out-Null; exit 0 }
    'context' {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Show-SasOperatorContext.ps1')
        exit $LASTEXITCODE
    }
    'next' {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Show-SasOperatorContext.ps1') -NextOnly
        exit $LASTEXITCODE
    }
    'refresh' {
        Write-Host 'NETWORK REQUIRED: GUEST / INTERNET' -ForegroundColor Cyan
        if (Test-Path -LiteralPath $sessionModule -PathType Leaf) {
            $network = Get-SasOperatorNetworkClassification -RepoRoot $repoRoot
            [void](Set-SasOperatorSessionValues -Values @{ current_network_classification=$network.classification; current_network_label=$network.label; next_required_network='GUEST / INTERNET'; next_command='sas refresh' })
            if ($network.classification -ne 'GUEST_INTERNET') {
                Write-Host "CURRENT NETWORK: $($network.classification) [$($network.label)]" -ForegroundColor Yellow
                Write-Host 'NEXT NETWORK: GUEST / INTERNET' -ForegroundColor Cyan
                Write-Host 'NEXT COMMAND: sas refresh' -ForegroundColor Green
                exit 20
            }
        }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Refresh-SasOperatorCommand.ps1') -RepositoryRoot $repoRoot
        exit $LASTEXITCODE
    }
    'evidence' { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Find-SasEvidence.cmd' -Arguments $CommandArgs) }
    'network' {
        $args = @($CommandArgs)
        if ($args.Count -eq 0) { & (Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1') -Purpose 'manual SysAdminSuite operator check'; exit $LASTEXITCODE }
        if ($args.Count -eq 1 -and $args[0]) { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Probe-CybernetSoftware.cmd' -Arguments @('Probe',[string]$args[0])) }
        Write-Host 'Usage: sas network  OR  sas network HOST' -ForegroundColor Red; exit 2
    }
    { $_ -in @('autologon','qualify') } { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-AutoLogonOnsite.cmd' -Arguments $CommandArgs) }
    'cybernet' {
        $args = @($CommandArgs)
        if ($args.Count -gt 0 -and $args[0]) {
            $mode = ([string]$args[0]).Trim().ToLowerInvariant()
            if ($mode -eq 'probe') { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Probe-CybernetSoftware.cmd' -Arguments $args) }
            if ($mode -in @('core','profiled-core')) {
                if ($args.Count -ne 2 -or -not $args[1]) { Write-Host 'Usage: sas cybernet Core HOST' -ForegroundColor Red; exit 2 }
                exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetProfiledClinicalCore.cmd' -Arguments @([string]$args[1]))
            }
            if ($mode -eq 'recover') {
                if ($args.Count -ne 2 -or -not $args[1]) { Write-Host 'Usage: sas cybernet Recover HOST' -ForegroundColor Red; exit 2 }
                & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Invoke-SasCybernetCoreRecovery.ps1') -ComputerName ([string]$args[1])
                exit $LASTEXITCODE
            }
            if ($mode -eq 'deploy') { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetSoftware.cmd' -Arguments $args) }
        }
        exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-CybernetBatchConfiguration.cmd' -Arguments $args)
    }
    default { Write-Host "Unknown sas command: $Command" -ForegroundColor Red; Write-Host 'Run `sas` for available commands.'; exit 2 }
}
