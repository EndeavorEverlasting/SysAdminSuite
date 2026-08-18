#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Test-SasAutoLogonStateCaptureCleanupInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^autologon-recovery-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('baseline','after','current')]
        [string]$Phase,

        [Parameter(Mandatory = $true)]
        [object[]]$Entries
    )

    $allowedFiles = @(
        "$Phase\Invoke-StateReadWorker.ps1",
        "$Phase\worker-result.json",
        "$Phase\worker-result.json.tmp"
    )
    $allowedDirectories = @($Phase)

    $normalized = @()
    foreach ($entry in @($Entries)) {
        $path = ([string]$entry.path).Trim().TrimStart('\').Replace('/','\')
        $kind = ([string]$entry.kind).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw 'State-capture cleanup inventory contains an empty relative path.'
        }
        if ($path.Contains('..')) {
            throw "State-capture cleanup inventory contains a parent traversal segment: $path"
        }
        if ($kind -notin @('file','directory')) {
            throw "State-capture cleanup inventory contains an unsupported entry kind for ${path}: $kind"
        }
        $normalized += [pscustomobject]@{ path=$path; kind=$kind }
    }

    $unexpected = @()
    foreach ($entry in @($normalized)) {
        if ($entry.kind -eq 'directory') {
            if ([string]$entry.path -notin $allowedDirectories) { $unexpected += [string]$entry.path }
        }
        elseif ([string]$entry.path -notin $allowedFiles) {
            $unexpected += [string]$entry.path
        }
    }

    [pscustomobject][ordered]@{
        run_id = $RunId
        phase = $Phase
        allowed = ($unexpected.Count -eq 0)
        unexpected_paths = @($unexpected)
        inventory_paths = @($normalized | ForEach-Object { [string]$_.path })
        allowed_files = @($allowedFiles)
        allowed_directories = @($allowedDirectories)
    }
}

function Test-SasAutoLogonStateCaptureWorkerResultIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^autologon-recovery-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('baseline','after','current')]
        [string]$Phase,

        $WorkerResult
    )

    if ($null -eq $WorkerResult) {
        return [pscustomobject][ordered]@{
            present = $false
            valid = $true
            schema_valid = $null
            run_id_valid = $null
            phase_valid = $null
        }
    }

    $schemaValid = ([string]$WorkerResult.schema_version -eq 'sas-autologon-smb-state-worker-result/v1')
    $runIdValid = ([string]$WorkerResult.run_id -eq $RunId)
    $phaseValid = ([string]$WorkerResult.phase -eq $Phase)

    [pscustomobject][ordered]@{
        present = $true
        valid = ($schemaValid -and $runIdValid -and $phaseValid)
        schema_valid = $schemaValid
        run_id_valid = $runIdValid
        phase_valid = $phaseValid
    }
}

function Test-SasAutoLogonStateCaptureParentInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Entries
    )

    $runIdPattern = '^autologon-recovery-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$'
    $normalized = @()
    foreach ($entry in @($Entries)) {
        $path = ([string]$entry.path).Trim().TrimStart('\').Replace('/','\')
        $kind = ([string]$entry.kind).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw 'State-capture parent inventory contains an empty relative path.'
        }
        if ($path.Contains('..')) {
            throw "State-capture parent inventory contains a parent traversal segment: $path"
        }
        if ($kind -notin @('file','directory')) {
            throw "State-capture parent inventory contains an unsupported entry kind for ${path}: $kind"
        }
        $normalized += [pscustomobject]@{ path=$path; kind=$kind }
    }

    $activeResidue = @()
    $inertEmptyRunRoots = @()
    foreach ($entry in @($normalized)) {
        $path = [string]$entry.path
        $isTopLevel = (-not $path.Contains('\'))
        $isRunRoot = ($path -match $runIdPattern)
        if ($entry.kind -eq 'directory' -and $isTopLevel -and $isRunRoot) {
            $inertEmptyRunRoots += $path
            continue
        }
        $activeResidue += $path
    }

    [pscustomobject][ordered]@{
        operationally_clean = ($activeResidue.Count -eq 0)
        active_residue_paths = @($activeResidue)
        inert_empty_run_roots = @($inertEmptyRunRoots)
        inventory_paths = @($normalized | ForEach-Object { [string]$_.path })
        parent_policy = 'allow_only_empty_top_level_autologon_recovery_run_roots'
    }
}

Export-ModuleMember -Function Test-SasAutoLogonStateCaptureCleanupInventory,Test-SasAutoLogonStateCaptureWorkerResultIdentity,Test-SasAutoLogonStateCaptureParentInventory
