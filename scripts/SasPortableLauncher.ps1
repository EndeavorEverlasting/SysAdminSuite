#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)][AllowEmptyString()][string[]]$CommandArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SysAdminSuite'
$cachePath = Join-Path -Path $stateRoot -ChildPath 'repo-root.txt'
$autoLogonRuntimeStatePath = Join-Path -Path $stateRoot -ChildPath 'autologon-short-runtime.json'
$PathLengthThreshold = 100
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SasRepoRoot {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $candidate = [IO.Path]::GetFullPath($Path.Trim()) } catch { return $false }
    foreach ($relative in @(
        'Run-AutoLogonOnsite.cmd','Run-CybernetBatchConfiguration.cmd','Probe-CybernetSoftware.cmd',
        'Deploy-CybernetSoftware.cmd','Deploy-CybernetClinicalCore.cmd','Deploy-CybernetProfiledClinicalCore.cmd',
        'Find-SasEvidence.cmd','Refresh-SasOperatorCommand.cmd','Switch-Back-To-Previous-Network.cmd',
        'scripts\SasNetworkGuard.psm1','scripts\Return-SasOperatorToPreviousNetwork.ps1',
        'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path -Path $candidate -ChildPath $relative) -PathType Leaf)) { return $false }
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
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        try { Add-SasCandidate -List $candidates -Path ((Get-Content -LiteralPath $cachePath -Raw).Trim()) } catch { }
    }
    try { Add-SasCandidate -List $candidates -Path (& git -C (Get-Location).Path rev-parse --show-toplevel 2>$null | Select-Object -First 1) } catch { }
    foreach ($root in @($env:USERPROFILE,$env:OneDrive,$env:OneDriveCommercial,$env:OneDriveConsumer) | Where-Object { $_ } | Select-Object -Unique) {
        foreach ($relative in @('SysAdminSuite','SysAdminSuite-portable-onsite','SysAdminSuite-Live','dev\SysAdminSuite','Desktop\dev\SysAdminSuite','OG Laptop Backup\Desktop\dev\SysAdminSuite')) {
            Add-SasCandidate -List $candidates -Path (Join-Path -Path $root -ChildPath $relative)
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

function Get-SasActualArguments {
    param([AllowNull()][string[]]$Arguments)
    return @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Resolve-SasPreparedAutoLogonRuntime {
    if (-not (Test-Path -LiteralPath $autoLogonRuntimeStatePath -PathType Leaf)) {
        throw "AutoLogon short runtime is not prepared. Run 'sas refresh' on Guest/Internet before switching to the protected network."
    }
    try { $state = Get-Content -LiteralPath $autoLogonRuntimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "AutoLogon short-runtime manifest is unreadable. Run 'sas refresh' on Guest/Internet: $($_.Exception.Message)" }
    if ([string]$state.schema_version -ne 'sas-autologon-short-runtime/v1') {
        throw "AutoLogon short-runtime manifest schema is unsupported. Run 'sas refresh' on Guest/Internet."
    }
    $runtimeRoot = [IO.Path]::GetFullPath([string]$state.runtime_root)
    if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        throw "Prepared AutoLogon runtime is missing: $runtimeRoot. Run 'sas refresh' on Guest/Internet."
    }
    $preparedCommit = ([string]$state.prepared_commit).Trim()
    if ([string]::IsNullOrWhiteSpace($preparedCommit)) {
        throw "Prepared AutoLogon runtime has no sealed commit. Run 'sas refresh' on Guest/Internet."
    }
    if ([string]$state.preparation_network_classification -ne 'GUEST_INTERNET' -or
        [string]$state.runtime_git_transport -ne 'LOCAL_FILESYSTEM_ONLY' -or
        [bool]$state.protected_bootstrap_git_network_allowed) {
        throw "Prepared AutoLogon runtime does not satisfy the Guest-to-protected staging contract. Run 'sas refresh' on Guest/Internet."
    }
    $bootstrap = Join-Path $runtimeRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
    if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
        throw "Prepared AutoLogon runtime is missing the protected launcher: $bootstrap"
    }
    return [pscustomobject]@{ root=$runtimeRoot; commit=$preparedCommit; bootstrap=$bootstrap }
}

function Get-SasAvailableSubstDrive {
    foreach ($letter in @('S','R','Q','P','O','N','M','L','K','J')) {
        if ($null -eq (Get-PSDrive -Name $letter -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath "${letter}:\")) { return "${letter}:" }
    }
    throw 'No free temporary drive letter is available for the SysAdminSuite short-path alias.'
}

function Invoke-SasPortableRepoCommand {
    param([string]$RepoRoot,[string]$RelativePath,[AllowNull()][string[]]$Arguments)
    $Arguments = @(Get-SasActualArguments -Arguments $Arguments)
    $entryPoint = Join-Path -Path $RepoRoot -ChildPath $RelativePath
    $isLocalDrivePath = $RepoRoot -match '^[A-Za-z]:\\'
    if (-not $isLocalDrivePath -or $RepoRoot.Length -lt $PathLengthThreshold) {
        & $entryPoint @Arguments | Out-Host
        return [int]$LASTEXITCODE
    }
    $drive = Get-SasAvailableSubstDrive
    $substExe = Join-Path -Path $env:WINDIR -ChildPath 'System32\subst.exe'
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
$actualCommandArgs = Get-SasActualArguments -Arguments $CommandArgs
$sessionModule = Join-Path -Path $repoRoot -ChildPath 'scripts\SasOperatorSession.psm1'
if (Test-Path -LiteralPath $sessionModule -PathType Leaf) { Import-Module $sessionModule -Force }

if ([string]::IsNullOrWhiteSpace($normalized)) {
    Write-Host 'SysAdminSuite operator command' -ForegroundColor Cyan
    Write-Host "Repo: $repoRoot"
    Write-Host ''
    Write-Host '  sas context                          Show persistent operator/session state'
    Write-Host '  sas next                             Show only next network + one next command'
    Write-Host '  sas refresh                          GUEST / INTERNET: refresh repo and seal C:\SASAL for protected AutoLogon'
    Write-Host '  sas leave                            LOCAL ONLY: return to recorded previous guest/internet Wi-Fi'
    Write-Host '  sas cybernet Core HOST              PROTECTED NORTHWELL: five clinical apps; AutoLogon untouched; no reboot'
    Write-Host '  sas cybernet Recover HOST           PROTECTED NORTHWELL: exact previous-run cleanup/recovery only'
    Write-Host '  sas cybernet Probe HOST             PROTECTED NORTHWELL: optional read-only readiness'
    Write-Host '  sas cybernet Deploy HOST            PROTECTED NORTHWELL: full Cybernet software profile; readiness included; AutoLogon last; restart included'
    Write-Host '  The standalone Probe is optional diagnosis; it is NOT a prerequisite loop before Deploy'
    Write-Host '  Fixture/live-cert/runtime-proof loops are NOT prerequisites for deployment'
    Write-Host '  sas cybernet Plan HOST              Hardware-only Cybernet plan'
    Write-Host '  sas cybernet Apply HOST             Hardware-only Cybernet apply'
    Write-Host '  sas cybernet Validate HOST          Hardware-only Cybernet validation'
    Write-Host '  sas evidence Cybernet               OFFLINE: recover newest Cybernet evidence'
    Write-Host '  sas autologon Remote HOST           PROTECTED NORTHWELL: use sealed C:\SASAL; no Git network I/O; apply + restart'
    Write-Host '  sas autologon Recover HOST          PROTECTED NORTHWELL: recovery gate from sealed C:\SASAL'
    Write-Host '  sas network                          Read-only Northwell network posture'
    Write-Host '  sas network HOST                     Optional one-target read-only readiness probe'
    Write-Host '  sas repo                             Print resolved repository path'
    Write-Host '  sas open                             Open repository in Explorer'
    Write-Host ''
    Write-Host 'Cybernet readiness marker: CYBERNET_DEPLOYMENT_READINESS_READY (read-only; not deployment completion)' -ForegroundColor DarkGray
    Write-Host 'Cybernet terminal marker: CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED' -ForegroundColor DarkGray
    Write-Host 'AutoLogon terminal marker: AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED' -ForegroundColor DarkGray
    Write-Host 'These markers do not claim human-observed interactive desktop sign-in.' -ForegroundColor Green
    exit 0
}

switch ($normalized) {
    'repo' { Write-Output $repoRoot; exit 0 }
    'open' { Start-Process -FilePath 'explorer.exe' -ArgumentList @($repoRoot) | Out-Null; exit 0 }
    'context' {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path -Path $repoRoot -ChildPath 'scripts\Show-SasOperatorContext.ps1')
        exit $LASTEXITCODE
    }
    'next' {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path -Path $repoRoot -ChildPath 'scripts\Show-SasOperatorContext.ps1') -NextOnly
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
                Write-Host 'LOCAL RETURN COMMAND: sas leave' -ForegroundColor Green
                exit 20
            }
        }
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path -Path $repoRoot -ChildPath 'scripts\Refresh-SasOperatorCommand.ps1') -RepositoryRoot $repoRoot
        exit $LASTEXITCODE
    }
    { $_ -in @('leave','guest','return-network') } {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path -Path $repoRoot -ChildPath 'scripts\Return-SasOperatorToPreviousNetwork.ps1')
        exit $LASTEXITCODE
    }
    'evidence' { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Find-SasEvidence.cmd' -Arguments $actualCommandArgs) }
    'network' {
        if ($actualCommandArgs.Count -eq 0) {
            & (Join-Path -Path $repoRoot -ChildPath 'scripts\Confirm-SasNorthwellNetwork.ps1') -Purpose 'manual SysAdminSuite operator check'
            exit $LASTEXITCODE
        }
        if ($actualCommandArgs.Count -eq 1) {
            exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Probe-CybernetSoftware.cmd' -Arguments @('Probe',[string]$actualCommandArgs[0]))
        }
        Write-Host 'Usage: sas network  OR  sas network HOST' -ForegroundColor Red
        exit 2
    }
    'autologon' {
        if ($actualCommandArgs.Count -eq 2) {
            $mode = ([string]$actualCommandArgs[0]).Trim().ToLowerInvariant()
            $target = [string]$actualCommandArgs[1]
            if ($mode -eq 'remote') {
                $runtime = Resolve-SasPreparedAutoLogonRuntime
                Write-Host "Using sealed AutoLogon runtime: $($runtime.root)" -ForegroundColor Cyan
                Write-Host "Prepared commit: $($runtime.commit)" -ForegroundColor Cyan
                Write-Host 'Protected-side Git network I/O: NONE' -ForegroundColor Green
                & $runtime.bootstrap $target $runtime.commit
                exit $LASTEXITCODE
            }
            if ($mode -eq 'recover') {
                $runtime = Resolve-SasPreparedAutoLogonRuntime
                $recoveryLauncher = Join-Path $runtime.root 'Run-AutoLogonOnsite.cmd'
                & $recoveryLauncher 'Recover' $target
                exit $LASTEXITCODE
            }
        }
        exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-AutoLogonOnsite.cmd' -Arguments $actualCommandArgs)
    }
    'qualify' {
        exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-AutoLogonOnsite.cmd' -Arguments $actualCommandArgs)
    }
    'cybernet' {
        $args = @($actualCommandArgs)
        if ($args.Count -gt 0) {
            $mode = ([string]$args[0]).Trim().ToLowerInvariant()
            if ($mode -eq 'probe') { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Probe-CybernetSoftware.cmd' -Arguments $args) }
            if ($mode -in @('core','profiled-core')) {
                if ($args.Count -ne 2) { Write-Host 'Usage: sas cybernet Core HOST' -ForegroundColor Red; exit 2 }
                exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetProfiledClinicalCore.cmd' -Arguments @([string]$args[1]))
            }
            if ($mode -eq 'recover') {
                if ($args.Count -ne 2) { Write-Host 'Usage: sas cybernet Recover HOST' -ForegroundColor Red; exit 2 }
                & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasCybernetCoreRecovery.ps1') -ComputerName ([string]$args[1])
                exit $LASTEXITCODE
            }
            if ($mode -eq 'deploy') { exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Deploy-CybernetSoftware.cmd' -Arguments $args) }
        }
        exit (Invoke-SasPortableRepoCommand -RepoRoot $repoRoot -RelativePath 'Run-CybernetBatchConfiguration.cmd' -Arguments $args)
    }
    default {
        Write-Host "Unknown sas command: $Command" -ForegroundColor Red
        Write-Host 'Run `sas` for available commands.'
        exit 2
    }
}
