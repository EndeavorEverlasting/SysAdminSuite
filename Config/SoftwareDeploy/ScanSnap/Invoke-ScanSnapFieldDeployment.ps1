#Requires -Version 5.1
<#
.SYNOPSIS
Runs the deterministic ScanSnap field deployment from the Admin Box.

.DESCRIPTION
Binds a locally frozen ScanSnap package to the canonical Northwell protected-network
authority, exact DNS/FQDN target identity, the bounded read-only software deployment
transport preflight, and the canonical Kerberos SMB + SYSTEM Scheduled Task adapter.

All human confirmation is performed on the controller (Admin Box). The target receives
only a noninteractive SYSTEM task. Ordinary Internet Wi-Fi may coexist with an approved
DomainAuthenticated non-Wi-Fi VPN/LAN path because network admission is delegated to the
canonical SasNorthwellNetworkAuthority contract.

PreflightOnly performs package, network, DNS, and transport authorization proof without
target mutation. Live execution reruns the same preflight and then requires the operator
to type the exact local confirmation phrase before any target mutation.
#>
[CmdletBinding()]
param(
    [string]$HostsFile,
    [string]$PackageRoot,
    [string]$ManifestPath,
    [switch]$PreflightOnly,
    [ValidateRange(1,30)][int]$TransportTimeoutSeconds = 8,
    [ValidateRange(10,7200)][int]$ResultTimeoutSeconds = 1800,
    [ValidateRange(10,7200)][int]$InstallerTimeoutSeconds = 1800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot '..\..\..'))
if ([string]::IsNullOrWhiteSpace($HostsFile)) { $HostsFile = Join-Path $scriptRoot 'hosts_field.txt' }
elseif (-not [IO.Path]::IsPathRooted($HostsFile)) { $HostsFile = [IO.Path]::GetFullPath((Join-Path $scriptRoot $HostsFile)) }
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot = $scriptRoot }
elseif (-not [IO.Path]::IsPathRooted($PackageRoot)) { $PackageRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot $PackageRoot)) }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $localManifest = Join-Path $PackageRoot 'package.local.manifest.json'
    $trackedTemplate = Join-Path $PackageRoot 'package.manifest.json'
    $ManifestPath = if (Test-Path -LiteralPath $localManifest -PathType Leaf) { $localManifest } else { $trackedTemplate }
}
elseif (-not [IO.Path]::IsPathRooted($ManifestPath)) { $ManifestPath = [IO.Path]::GetFullPath((Join-Path $PackageRoot $ManifestPath)) }

$networkAuthorityModule = Join-Path $repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
$deploymentAdapterModule = Join-Path $repoRoot 'scripts\SasSoftwareDeploymentAdapter.psm1'
$transportPreflightScript = Join-Path $repoRoot 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
foreach ($required in @($networkAuthorityModule,$deploymentAdapterModule,$transportPreflightScript,$HostsFile,$ManifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "SCANSNAP_REQUIRED_INPUT_MISSING: $required" }
}
Import-Module $networkAuthorityModule -Force -ErrorAction Stop
Import-Module $deploymentAdapterModule -Force -ErrorAction Stop

function Write-ScanSnapState {
    param([Parameter(Mandatory=$true)][string]$State,[hashtable]$Data=@{})
    $parts = @("SAS_SCANSNAP","STATE=$State")
    foreach ($key in @($Data.Keys | Sort-Object)) {
        $value = ([string]$Data[$key]).Replace('|','/').Replace([Environment]::NewLine,' ')
        $parts += "$key=$value"
    }
    Write-Host ($parts -join '|')
}

function Test-LocalAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-ExactTargetFqdn {
    param([Parameter(Mandatory=$true)][string]$Requested)
    $trimmed = $Requested.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { throw 'SCANSNAP_TARGET_EMPTY' }
    if ($trimmed -ieq 'LPW003ASI105') { throw 'SCANSNAP_STALE_TARGET_FORBIDDEN: LPW003ASI105' }

    $entry = $null
    try { $entry = [Net.Dns]::GetHostEntry($trimmed) }
    catch { throw "SCANSNAP_DNS_RESOLUTION_FAILED: $trimmed :: $($_.Exception.Message)" }

    $fqdn = [string]$entry.HostName
    if (-not (Test-SasDeploymentFqdn -ComputerName $fqdn)) {
        throw "SCANSNAP_CANONICAL_FQDN_REQUIRED: requested=$trimmed resolved=$fqdn"
    }

    if ($trimmed -notmatch '\.' -and (($fqdn -split '\.')[0] -ine $trimmed)) {
        throw "SCANSNAP_ALIAS_MISMATCH: requested=$trimmed canonical=$fqdn"
    }

    $addresses = @($entry.AddressList | Where-Object { $null -ne $_ } | ForEach-Object { $_.IPAddressToString } | Sort-Object -Unique)
    if ($addresses.Count -lt 1) { throw "SCANSNAP_DNS_NO_ADDRESS: $fqdn" }

    [pscustomobject][ordered]@{
        requested = $trimmed
        fqdn = $fqdn.ToLowerInvariant()
        addresses = @($addresses)
    }
}

function Convert-ScanSnapDetectionToValidationCheck {
    param([Parameter(Mandatory=$true)]$Manifest)
    $detectType = ([string]$Manifest.DetectType).Trim().ToLowerInvariant()
    $detectValue = ([Environment]::ExpandEnvironmentVariables(([string]$Manifest.DetectValue).Trim()))
    if ([string]::IsNullOrWhiteSpace($detectValue)) { throw 'SCANSNAP_DETECTION_VALUE_MISSING' }

    switch ($detectType) {
        'file' {
            if (-not [IO.Path]::IsPathRooted($detectValue) -or $detectValue -match '[*?]') {
                throw "SCANSNAP_FILE_DETECTION_MUST_BE_EXACT_ABSOLUTE_PATH: $detectValue"
            }
            return [pscustomobject][ordered]@{
                id = 'scansnap-detection'
                type = 'FileExists'
                required = $true
                path = [IO.Path]::GetFullPath($detectValue)
            }
        }
        'regkey' {
            $path = $detectValue.Replace('HKEY_LOCAL_MACHINE\','HKLM:\')
            if ($path -match '^HKLM\\') { $path = 'HKLM:\' + $path.Substring(5) }
            if ($path -notmatch '^HKLM:\\[^*?]+$') {
                throw "SCANSNAP_REGKEY_DETECTION_MUST_BE_EXACT_HKLM_PATH: $detectValue"
            }
            return [pscustomobject][ordered]@{
                id = 'scansnap-detection'
                type = 'RegistryKeyExists'
                required = $true
                registry_path = $path
            }
        }
        default { throw "SCANSNAP_DETECTION_TYPE_UNSUPPORTED: $detectType" }
    }
}

function Read-ScanSnapPackage {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$manifest.Bound) { throw 'SCANSNAP_PACKAGE_UNBOUND: bind the real installer before field deployment.' }

    foreach ($name in @('ProductName','InstallerFileName','Sha256','Type','SilentArgs','DetectType','DetectValue')) {
        if ($manifest.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$manifest.$name)) {
            throw "SCANSNAP_MANIFEST_FIELD_MISSING: $name"
        }
    }
    if ([string]$manifest.ProductName -ne 'ScanSnap') { throw 'SCANSNAP_MANIFEST_PRODUCT_MISMATCH' }
    if ([string]$manifest.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'SCANSNAP_MANIFEST_SHA256_INVALID' }
    if (([string]$manifest.Type).ToLowerInvariant() -notin @('msi','exe')) { throw 'SCANSNAP_INSTALLER_TYPE_UNSUPPORTED' }

    $installerPath = Join-Path (Join-Path $PackageRoot 'installers') ([string]$manifest.InstallerFileName)
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "SCANSNAP_INSTALLER_NOT_FOUND: $installerPath" }
    $observed = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    if ($observed -ine [string]$manifest.Sha256) {
        throw "SCANSNAP_INSTALLER_HASH_MISMATCH: expected=$($manifest.Sha256) observed=$observed"
    }

    [pscustomobject][ordered]@{
        manifest = $manifest
        installer_path = $installerPath
        source_sha256 = $observed.ToLowerInvariant()
        installer_arguments = @([string]$manifest.SilentArgs)
        validation_checks = @((Convert-ScanSnapDetectionToValidationCheck -Manifest $manifest))
    }
}

function Write-JsonAtomic {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

try {
    if (-not (Test-LocalAdministrator)) { throw 'SCANSNAP_ADMINBOX_ELEVATION_REQUIRED' }

    $package = Read-ScanSnapPackage
    Write-ScanSnapState -State 'PACKAGE_VERIFIED' -Data @{
        product = [string]$package.manifest.ProductName
        installer = [string]$package.manifest.InstallerFileName
        sha256 = [string]$package.source_sha256
        detection = [string]$package.manifest.DetectType
    }

    $authority = Assert-SasNorthwellNetwork
    Write-ScanSnapState -State 'NETWORK_AUTHORIZED' -Data @{
        route = [string]$authority.Route
        evidence = [string]$authority.Evidence
        controller = [string]$env:COMPUTERNAME
    }

    $rawTargets = @(Get-Content -LiteralPath $HostsFile -Encoding UTF8 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($rawTargets.Count -lt 1) { throw 'SCANSNAP_TARGET_LIST_EMPTY' }
    if ($rawTargets.Count -gt 25) { throw 'SCANSNAP_TARGET_LIMIT_EXCEEDED' }
    $duplicates = @($rawTargets | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw "SCANSNAP_DUPLICATE_TARGET: $(@($duplicates.Name) -join ',')" }

    $targets = @()
    foreach ($raw in $rawTargets) {
        $resolved = Resolve-ExactTargetFqdn -Requested $raw
        $targets += $resolved
        Write-ScanSnapState -State 'TARGET_BOUND' -Data @{
            requested = $resolved.requested
            fqdn = $resolved.fqdn
            address_count = @($resolved.addresses).Count
        }
    }

    $stateRoot = Join-Path $env:ProgramData 'SysAdminSuite\SoftwareDeploy\ScanSnap'
    $runId = 'scansnap-field-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
    $runRoot = Join-Path (Join-Path $stateRoot 'runs') $runId
    $preflightRoot = Join-Path $runRoot 'preflight'
    New-Item -ItemType Directory -Path $preflightRoot -Force | Out-Null

    $preflights = @()
    foreach ($target in $targets) {
        Write-ScanSnapState -State 'TRANSPORT_PREFLIGHT_STARTED' -Data @{ fqdn = $target.fqdn }
        $probeArgs = @{
            ComputerName = $target.fqdn
            AllowNetworkActivity = $true
            TransportIntent = 'kerberos_smb_task'
            TimeoutSeconds = $TransportTimeoutSeconds
            OutputRoot = $preflightRoot
            PassThru = $true
        }
        $probe = & $transportPreflightScript @probeArgs
        $classification = [string]$probe.result.decision.classification
        $selected = [string]$probe.result.decision.selected_transport
        Write-ScanSnapState -State 'TRANSPORT_PREFLIGHT_RESULT' -Data @{ fqdn=$target.fqdn; classification=$classification; transport=$selected }
        if ($classification -ne 'kerberos_smb_task_ready' -or $selected -ne 'kerberos_smb_task') {
            throw "SCANSNAP_TRANSPORT_NOT_READY: fqdn=$($target.fqdn) classification=$classification transport=$selected"
        }

        $decisionArgs = @{
            Transport = 'SmbScheduledTask'
            PreflightResultPath = [string]$probe.result_path
            PreflightMaxAgeMinutes = 15
        }
        $decision = Resolve-SasSoftwareDeploymentTransport @decisionArgs
        if ([string]$decision.selected_transport -ne 'SmbScheduledTask') {
            throw "SCANSNAP_TRANSPORT_DECISION_MISMATCH: $($target.fqdn)"
        }
        $preflights += [pscustomobject][ordered]@{
            fqdn = $target.fqdn
            result_path = [string]$probe.result_path
            classification = $classification
            selected_transport = $selected
        }
    }

    $preflightSummary = [pscustomobject][ordered]@{
        schema_version = 'sas-scansnap-field-deployment/v1'
        run_id = $runId
        phase = 'preflight'
        controller = [string]$env:COMPUTERNAME
        network_route = [string]$authority.Route
        package_sha256 = [string]$package.source_sha256
        target_count = $targets.Count
        targets = @($targets | ForEach-Object { [pscustomobject]@{ requested=$_.requested; fqdn=$_.fqdn; address_count=@($_.addresses).Count } })
        preflights = @($preflights)
        target_mutation_performed = $false
        next_action = if ($PreflightOnly) { 'Preflight complete. Run Deploy-ScanSnap-Field.cmd for the same package and target set.' } else { 'Await local Admin Box confirmation.' }
    }
    $preflightSummaryPath = Join-Path $runRoot 'preflight-summary.json'
    $latestPointerPath = Join-Path $stateRoot 'latest-run.json'
    Write-JsonAtomic -Path $preflightSummaryPath -Value $preflightSummary
    Write-JsonAtomic -Path $latestPointerPath -Value ([pscustomobject][ordered]@{
        schema_version = 'sas-scansnap-latest-run/v1'
        run_id = $runId
        phase = 'preflight'
        terminal_state = 'PREFLIGHT_READY'
        evidence_path = $preflightSummaryPath
        updated_utc = (Get-Date).ToUniversalTime().ToString('o')
    })
    Write-ScanSnapState -State 'PREFLIGHT_READY' -Data @{ run_id=$runId; targets=$targets.Count; evidence=$preflightSummaryPath }

    if ($PreflightOnly) {
        Write-ScanSnapState -State 'COMPLETE_NO_MUTATION' -Data @{ run_id=$runId }
        exit 0
    }

    Write-Host ''
    Write-Host 'ScanSnap field deployment is READY.' -ForegroundColor Green
    Write-Host "Controller: $env:COMPUTERNAME"
    Write-Host "Protected route: $($authority.Route)"
    Write-Host "Installer: $($package.manifest.InstallerFileName)"
    Write-Host "SHA-256: $($package.source_sha256)"
    Write-Host 'Targets:'
    $targets | ForEach-Object { Write-Host ("  - {0}" -f $_.fqdn) }
    Write-Host ''
    $confirmation = Read-Host 'ADMIN BOX CONFIRMATION - type DEPLOY SCANSNAP exactly'
    if ($confirmation -cne 'DEPLOY SCANSNAP') {
        Write-JsonAtomic -Path $latestPointerPath -Value ([pscustomobject][ordered]@{
            schema_version = 'sas-scansnap-latest-run/v1'
            run_id = $runId
            phase = 'cancelled'
            terminal_state = 'CANCELLED_BEFORE_MUTATION'
            evidence_path = $preflightSummaryPath
            updated_utc = (Get-Date).ToUniversalTime().ToString('o')
        })
        Write-ScanSnapState -State 'CANCELLED_BEFORE_MUTATION' -Data @{ run_id=$runId; evidence=$preflightSummaryPath }
        exit 4
    }

    $identityCachePath = Join-Path $stateRoot 'process-identity.json'
    $identityHint = $null
    if (Test-Path -LiteralPath $identityCachePath -PathType Leaf) {
        try {
            $identityCache = Get-Content -LiteralPath $identityCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$identityCache.schema_version -ne 'sas-scansnap-process-identity-cache/v1') {
                throw 'cache_schema_mismatch'
            }
            if ([string]$identityCache.package_sha256 -ne [string]$package.source_sha256) {
                Write-ScanSnapState -State 'PROCESS_IDENTITY_CACHE_IGNORED' -Data @{ reason='package_hash_changed'; path=$identityCachePath }
            }
            elseif ([string]$identityCache.installer_file_name -ne [string]$package.manifest.InstallerFileName) {
                Write-ScanSnapState -State 'PROCESS_IDENTITY_CACHE_IGNORED' -Data @{ reason='installer_name_changed'; path=$identityCachePath }
            }
            elseif ($null -eq $identityCache.identity) {
                Write-ScanSnapState -State 'PROCESS_IDENTITY_CACHE_IGNORED' -Data @{ reason='identity_missing'; path=$identityCachePath }
            }
            else {
                $identityHint = $identityCache.identity
                Write-ScanSnapState -State 'PROCESS_IDENTITY_CACHE_LOADED' -Data @{ path=$identityCachePath; package_sha256=$package.source_sha256 }
            }
        }
        catch {
            Write-ScanSnapState -State 'PROCESS_IDENTITY_CACHE_IGNORED' -Data @{ reason='malformed_local_cache'; path=$identityCachePath }
            $identityHint = $null
        }
    }

    $adapterResults = @()
    $canonicalRunId = 'software-install-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
    for ($i = 0; $i -lt $targets.Count; $i++) {
        $target = $targets[$i]
        Write-ScanSnapState -State 'DEPLOYMENT_STARTED' -Data @{ fqdn=$target.fqdn; index=($i+1); total=$targets.Count }
        $invoke = @{
            ComputerName = $target.fqdn
            InstallerPath = [string]$package.installer_path
            ExpectedSourceSha256 = [string]$package.source_sha256
            PackageName = 'ScanSnap'
            InstallerArguments = @($package.installer_arguments)
            ValidationChecks = @($package.validation_checks)
            RunId = $canonicalRunId
            LocalRunRoot = $runRoot
            ResultTimeoutSeconds = $ResultTimeoutSeconds
            InstallerTimeoutSeconds = $InstallerTimeoutSeconds
        }
        if ($null -ne $identityHint) { $invoke.ProcessIdentityHint = $identityHint }
        $adapter = Invoke-SasSmbScheduledTaskDeployment @invoke
        $adapterResults += $adapter
        $resultPath = Join-Path $runRoot ("deployment-result-{0}.json" -f ($i+1))
        Write-JsonAtomic -Path $resultPath -Value $adapter
        Write-ScanSnapState -State 'DEPLOYMENT_RESULT' -Data @{ fqdn=$target.fqdn; status=[string]$adapter.status; evidence=$resultPath }

        if ($adapter.execution.PSObject.Properties.Name -contains 'process_observation' -and
            $null -ne $adapter.execution.process_observation -and
            $null -ne $adapter.execution.process_observation.selected_identity) {
            $observedIdentity = $adapter.execution.process_observation.selected_identity
            $identityHint = [pscustomobject][ordered]@{
                name = [string]$observedIdentity.name
                executable_leaf = [string]$observedIdentity.executable_leaf
                file_version = [string]$observedIdentity.file_version
            }
            $identityCache = [pscustomobject][ordered]@{
                schema_version = 'sas-scansnap-process-identity-cache/v1'
                package_sha256 = [string]$package.source_sha256
                installer_file_name = [string]$package.manifest.InstallerFileName
                identity = $identityHint
                learned_from = [string]$adapter.execution.process_observation.selection_source
                learned_utc = (Get-Date).ToUniversalTime().ToString('o')
            }
            Write-JsonAtomic -Path $identityCachePath -Value $identityCache
            Write-ScanSnapState -State 'PROCESS_IDENTITY_CACHE_UPDATED' -Data @{
                source = [string]$adapter.execution.process_observation.selection_source
                path = $identityCachePath
                package_sha256 = [string]$package.source_sha256
            }
        }
    }

    $failures = @($adapterResults | Where-Object { [string]$_.status -notin @('completed','completed_reboot_required') })
    $summary = [pscustomobject][ordered]@{
        schema_version = 'sas-scansnap-field-deployment/v1'
        run_id = $runId
        phase = 'deployment'
        controller = [string]$env:COMPUTERNAME
        network_route = [string]$authority.Route
        package_sha256 = [string]$package.source_sha256
        target_count = $targets.Count
        completed_count = ($targets.Count - $failures.Count)
        failed_count = $failures.Count
        results = @($adapterResults)
        target_mutation_performed = $true
        evidence_root = $runRoot
    }
    $summaryPath = Join-Path $runRoot 'deployment-summary.json'
    Write-JsonAtomic -Path $summaryPath -Value $summary
    Write-JsonAtomic -Path $latestPointerPath -Value ([pscustomobject][ordered]@{
        schema_version = 'sas-scansnap-latest-run/v1'
        run_id = $runId
        phase = 'deployment'
        terminal_state = if ($failures.Count -eq 0) { 'DEPLOYMENT_VALIDATED' } else { 'FAILED' }
        evidence_path = $summaryPath
        updated_utc = (Get-Date).ToUniversalTime().ToString('o')
    })

    if ($failures.Count -gt 0) {
        Write-ScanSnapState -State 'FAILED' -Data @{ failed=$failures.Count; evidence=$summaryPath }
        exit 3
    }

    Write-ScanSnapState -State 'DEPLOYMENT_VALIDATED' -Data @{ completed=$targets.Count; evidence=$summaryPath }
    exit 0
}
catch {
    Write-ScanSnapState -State 'BLOCKED' -Data @{ error=$_.Exception.Message }
    Write-Error $_
    exit 2
}
