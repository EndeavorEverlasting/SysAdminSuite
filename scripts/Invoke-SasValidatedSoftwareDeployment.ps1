#Requires -Version 5.1
<#
.SYNOPSIS
Executes an authorized software installation, validates the requested package, and finalizes SysAdminSuite teardown.

.DESCRIPTION
This is the canonical deployment entrypoint when client-requested software must be installed and the workstation
must be left without SysAdminSuite tooling or staging. It validates a closed JSON request, pins the installer by
SHA-256, delegates installation to Invoke-SasSoftwareInstall.ps1, invokes package-specific read-only checks,
performs idempotent run-scoped cleanup, and confirms the package evidence remains after cleanup.
The WinRM adapter remains available when separately certified. The first-class
SmbScheduledTask adapter consumes one fresh P02 result per target, stages only
the pinned installer and transient worker, and uses the current Windows token.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$AllowTargetMutation,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'WinRM', 'SmbScheduledTask')]
    [string]$Transport = 'WinRM',

    [Parameter(Mandatory = $false)]
    [string[]]$TransportPreflightPath = @(),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1440)]
    [int]$PreflightMaxAgeMinutes = 15,

    [Parameter(Mandatory = $false)]
    [ValidateRange(10, 7200)]
    [int]$ResultTimeoutSeconds = 1800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path $PSScriptRoot 'SasSoftwareInstallFinalization.psm1'
$transportAdapterPath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentAdapter.psm1'
$installerScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstall.ps1'
$finalizerScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstallFinalization.ps1'
foreach ($requiredPath in @($modulePath, $transportAdapterPath, $installerScript, $finalizerScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Missing required validated deployment surface: $requiredPath" }
}
Import-Module $modulePath -Force
Import-Module $transportAdapterPath -Force

function Resolve-ApprovedRequestPath {
    param([string]$Path)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    $roots = @(
        [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/input')).TrimEnd('\'),
        [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\')
    )
    if ($AllowFixtures) { $roots += [IO.Path]::GetFullPath((Join-Path $repoRoot 'Tests/fixtures')).TrimEnd('\') }
    if (@($roots | Where-Object { $candidate.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        throw "Validated deployment request must remain under survey/input, survey/output, or an explicitly allowed fixture root. Received: $candidate"
    }
    return $candidate
}

function Normalize-UncRoot {
    param([string]$Path)
    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') { throw "Software share root must be UNC: $Path" }
    return ($normalized.TrimEnd('\') + '\')
}

function Resolve-ValidatedInstallerPath {
    param($Request)
    $manifestPath = Join-Path $repoRoot 'harness/api/sas-harness-api.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $approvedRoots = @($manifest.posture.approved_software_sources | ForEach-Object { Normalize-UncRoot ([string]$_) } | Sort-Object -Unique)
    $root = Normalize-UncRoot ([string]$Request.software_share_root)
    if (@($approvedRoots | Where-Object { $_.Equals($root, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        throw "Software share root is not approved by the harness API: $root"
    }
    $relative = ([string]$Request.installer_relative_path).Trim().Replace('/', '\')
    if ([IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('\') -or $relative -match '(^|\\)\.\.(\\|$)') {
        throw 'Installer relative path is invalid.'
    }
    return "$root$relative"
}

function Write-SasValidatedDeploymentEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$RunId,
        [hashtable]$Data = @{}
    )
    $payload = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        event = $Name
        run_id = $RunId
    }
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }
    $payload | ConvertTo-Json -Depth 12 -Compress | Add-Content -LiteralPath $Path -Encoding UTF8
}

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing validated deployment without -AllowTargetMutation. Use -WhatIf for request-only planning.'
}

$RequestPath = Resolve-ApprovedRequestPath -Path $RequestPath
if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) { throw "Validated deployment request not found: $RequestPath" }
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$requestErrors = @(Test-SasValidatedDeploymentRequest -Request $request)
if ($requestErrors.Count -gt 0) { throw "Validated deployment request failed closed: $($requestErrors -join ', ')" }

$targets = @($request.targets | ForEach-Object { [string]$_ })
$preflightPaths = @($TransportPreflightPath | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
    Resolve-ApprovedRequestPath -Path ([string]$_)
})
if ($Transport -eq 'Auto' -and $targets.Count -ne 1) {
    throw 'Auto transport is intentionally limited to one-target pilot runs because each identifier-free P02 result covers exactly one target.'
}
if ($Transport -in @('Auto','SmbScheduledTask') -and $preflightPaths.Count -ne $targets.Count) {
    throw "$Transport requires one fresh P02 result path per target, in the same order as the validated request targets."
}
if ($Transport -eq 'WinRM' -and $preflightPaths.Count -notin @(0, $targets.Count)) {
    throw 'WinRM preflight paths must be omitted or supplied once per target.'
}

$transportDecisions = @()
for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++) {
    $selectionParameters = @{
        Transport = $Transport
        PreflightMaxAgeMinutes = $PreflightMaxAgeMinutes
        AllowFixturePreflight = $AllowFixtures
    }
    if ($preflightPaths.Count -gt 0) { $selectionParameters.PreflightResultPath = $preflightPaths[$targetIndex] }
    $decision = Resolve-SasSoftwareDeploymentTransport @selectionParameters
    if ([string]$decision.selected_transport -eq 'SmbScheduledTask' -and -not (Test-SasDeploymentFqdn -ComputerName $targets[$targetIndex])) {
        throw "SmbScheduledTask target must be the exact authorized FQDN: $($targets[$targetIndex])"
    }
    $transportDecisions += $decision
}
$selectedTransports = @($transportDecisions | ForEach-Object { [string]$_.selected_transport } | Sort-Object -Unique)
if ($selectedTransports.Count -ne 1) { throw 'One validated deployment run cannot mix transports; split the target set by selected transport.' }
$selectedTransport = $selectedTransports[0]

$mutationTarget = @($request.targets) -join ', '
$mutationAction = "Install '$($request.package_name)' with $selectedTransport and finalize SysAdminSuite teardown"
if (-not $WhatIfPreference -and -not $PSCmdlet.ShouldProcess($mutationTarget, $mutationAction)) {
    Write-Verbose 'Validated deployment cancelled before installer or target contact.'
    return
}

$installerPath = Resolve-ValidatedInstallerPath -Request $request
$signatureStatus = 'not_checked_whatif'
$observedSignerThumbprint = $null
$observedInstallerHash = $null
if (-not $WhatIfPreference) {
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "Pinned installer not found: $installerPath" }
    $observedInstallerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($observedInstallerHash -ne ([string]$request.installer_sha256).ToLowerInvariant()) {
        throw "Installer SHA-256 mismatch. Expected $($request.installer_sha256); observed $observedInstallerHash"
    }
    $requireValidSignature = ($request.PSObject.Properties.Name -contains 'require_valid_signature' -and [bool]$request.require_valid_signature)
    if ($requireValidSignature -or $request.PSObject.Properties.Name -contains 'expected_signer_thumbprint') {
        $signature = Get-AuthenticodeSignature -FilePath $installerPath
        $signatureStatus = [string]$signature.Status
        $observedSignerThumbprint = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { $null }
        if ($requireValidSignature -and $signature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
            throw "Installer Authenticode signature is not valid: $($signature.Status)"
        }
        if ($request.PSObject.Properties.Name -contains 'expected_signer_thumbprint' -and -not [string]::IsNullOrWhiteSpace([string]$request.expected_signer_thumbprint)) {
            if (-not $observedSignerThumbprint -or $observedSignerThumbprint -ne ([string]$request.expected_signer_thumbprint).ToUpperInvariant()) {
                throw 'Installer signer thumbprint does not match the approved request.'
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'survey/output/software_install' }
if ($WhatIfPreference -or $selectedTransport -eq 'WinRM') {
    $installParameters = @{
        ComputerName = @($request.targets)
        PackageName = [string]$request.package_name
        InstallerRelativePath = [string]$request.installer_relative_path
        SoftwareShareRoot = [string]$request.software_share_root
        InstallerArguments = @($request.installer_arguments)
        InstallMode = [string]$request.install_mode
        OutputRoot = $OutputRoot
        MaxTargets = 25
    }
    if ($AllowTargetMutation) { $installParameters.AllowTargetMutation = $true }
    if ($WhatIfPreference) { $installParameters.WhatIf = $true }
    else { $installParameters.Confirm = $false }

    $summary = & $installerScript @installParameters
    $runRoot = Split-Path -Parent ([string]$summary.event_path)
    $summaryPath = Join-Path $runRoot 'software_install_summary.json'
    $summary | Add-Member -NotePropertyName transport -NotePropertyValue $selectedTransport -Force
    $summary | Add-Member -NotePropertyName transport_requested -NotePropertyValue $Transport -Force
    $summary | Add-Member -NotePropertyName transport_selected_before_mutation -NotePropertyValue $true -Force
    $summary | Add-Member -NotePropertyName transport_fallback_attempted -NotePropertyValue $false -Force
    $summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
}
else {
    $runId = 'software-install-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $OutputRoot $runId
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $summaryPath = Join-Path $runRoot 'software_install_summary.json'
    $eventPath = Join-Path $runRoot 'software_install_events.jsonl'
    $handoffPath = Join-Path $runRoot 'operator_handoff.txt'
    $adapterResults = @()
    Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'run_started' -RunId $runId -Data @{
        package_name = [string]$request.package_name
        target_count = $targets.Count
        transport = 'SmbScheduledTask'
    }

    for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++) {
        $target = $targets[$targetIndex]
        Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'target_started' -RunId $runId -Data @{
            computer_name = $target
            transport = 'SmbScheduledTask'
        }

        $adapter = Invoke-SasSmbScheduledTaskDeployment `
            -ComputerName $target `
            -InstallerPath $installerPath `
            -ExpectedSourceSha256 ([string]$request.installer_sha256) `
            -PackageName ([string]$request.package_name) `
            -InstallerArguments @($request.installer_arguments) `
            -ValidationChecks @($request.validation.checks) `
            -RunId $runId `
            -LocalRunRoot $runRoot `
            -ResultTimeoutSeconds $ResultTimeoutSeconds
        $adapterPath = Join-Path $runRoot ("smb_task_transport_result_{0}.json" -f ($targetIndex + 1))
        $adapter | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $adapterPath -Encoding UTF8
        $adapter | Add-Member -NotePropertyName controller_result_path -NotePropertyValue $adapterPath -Force
        $adapterResults += $adapter

        Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'target_completed' -RunId $runId -Data @{
            computer_name = $target
            transport = 'SmbScheduledTask'
            status = [string]$adapter.status
            cleanup_verified = (-not [bool]$adapter.cleanup.task_remaining -and -not [bool]$adapter.cleanup.run_root_remaining)
        }
    }

    $installRows = @($adapterResults | ForEach-Object {
        [pscustomobject][ordered]@{
            computer_name = [string]$_.target
            package_name = [string]$request.package_name
            install_mode = [string]$request.install_mode
            transport = 'SmbScheduledTask'
            status = $(if ([string]$_.status -in @('completed','completed_reboot_required')) { 'completed' } else { [string]$_.status })
            exit_code = $_.execution.installer_exit_code
            reboot_required = [bool]$_.execution.reboot_required
            source_sha256 = [string]$_.source_sha256
            target_sha256 = [string]$_.target_sha256
            worker_source_sha256 = [string]$_.worker_source_sha256
            worker_target_sha256 = [string]$_.worker_target_sha256
            task_created = [bool]$_.task.created
            task_started = [bool]$_.task.started
            execution_as_system = [bool]$_.execution.as_system
            result_retrieved = [bool]$_.result_retrieval.succeeded
            cleanup_attempted = [bool]$_.cleanup.attempted
            cleanup_succeeded = ([bool]$_.cleanup.task_deletion_succeeded -and [bool]$_.cleanup.run_root_deletion_succeeded -and -not [bool]$_.cleanup.task_remaining -and -not [bool]$_.cleanup.run_root_remaining)
            repo_artifact_remaining = ([bool]$_.cleanup.task_remaining -or [bool]$_.cleanup.run_root_remaining)
            pruned_empty_parent_dirs = @()
            transport_result_path = [string]$_.controller_result_path
            error = $_.error
        }
    })
    $summary = [pscustomobject][ordered]@{
        schema_version = 'sas-software-install-summary/v1'
        run_id = $runId
        package_name = [string]$request.package_name
        installer_path = $installerPath
        install_mode = [string]$request.install_mode
        transport = 'SmbScheduledTask'
        transport_requested = $Transport
        transport_selected_before_mutation = $true
        transport_fallback_attempted = $false
        target_count = $targets.Count
        completed_count = @($installRows | Where-Object { $_.status -eq 'completed' }).Count
        planned_count = 0
        failed_count = @($installRows | Where-Object { $_.status -ne 'completed' }).Count
        cleanup_failure_count = @($installRows | Where-Object { -not $_.cleanup_succeeded }).Count
        repo_artifact_remaining_count = @($installRows | Where-Object { $_.repo_artifact_remaining }).Count
        reboot_required_count = @($installRows | Where-Object { $_.reboot_required }).Count
        target_repo_artifact_policy = 'Only the unique scheduled task and ProgramData run root are transient; requested software and vendor-owned artifacts are preserved.'
        event_path = $eventPath
        operator_handoff_path = $handoffPath
        results = $installRows
        guardrails = @('current_windows_token_only','no_credentials','source_and_target_sha256','execute_once_as_system','no_mid_run_fallback','run_scoped_teardown_required','no_automatic_reboot')
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    @(
        'SysAdminSuite canonical software deployment handoff',
        "Run ID: $runId",
        'Transport: SmbScheduledTask',
        "Targets: $($summary.target_count)",
        "Completed: $($summary.completed_count)",
        "Failed: $($summary.failed_count)",
        "Cleanup failures: $($summary.cleanup_failure_count)",
        "Repo-owned remnants: $($summary.repo_artifact_remaining_count)",
        "Reboot required (not performed): $($summary.reboot_required_count)",
        "Summary: $summaryPath"
    ) | Set-Content -LiteralPath $handoffPath -Encoding UTF8
}

$orchestrationPath = Join-Path $runRoot 'validated_deployment_result.json'

if ($WhatIfPreference) {
    $planResult = [ordered]@{
        schema_version = 'sas-validated-software-deployment-result/v1'
        request_id = [string]$request.request_id
        run_id = [string]$summary.run_id
        package_name = [string]$request.package_name
        transport_requested = $Transport
        transport = $selectedTransport
        transport_preflight_consumed = @($transportDecisions | Where-Object { $_.preflight_consumed }).Count -eq $transportDecisions.Count
        transport_selected_before_mutation = $true
        transport_fallback_attempted = $false
        classification = 'PLAN_ONLY_NO_INSTALL'
        deployment_complete = $false
        installer_hash_verified = $false
        installer_signature_status = $signatureStatus
        finalization_performed = $false
        network_activity_performed = $false
        target_mutation_performed = $false
        cleanup_policy = 'repo_owned_run_scoped_only'
        install_summary_path = $summaryPath
        finalization_path = $null
    }
    $planResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $orchestrationPath -Encoding UTF8
    Write-Output ([pscustomobject]$planResult)
    return
}

if ($selectedTransport -eq 'WinRM') {
    $finalization = & $finalizerScript `
        -InstallSummaryPath $summaryPath `
        -RequestPath $RequestPath `
        -AllowTargetMutation `
        -AllowFixtures:$AllowFixtures `
        -Confirm:$false
}
else {
    Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'finalization_started' -RunId ([string]$summary.run_id) -Data @{
        request_id = [string]$request.request_id
        target_count = $adapterResults.Count
        transport = 'SmbScheduledTask'
    }
    $finalizationRows = @($adapterResults | ForEach-Object {
        $cleanupSucceeded = ([bool]$_.cleanup.task_deletion_succeeded -and [bool]$_.cleanup.run_root_deletion_succeeded -and
            -not [bool]$_.cleanup.task_remaining -and -not [bool]$_.cleanup.run_root_remaining)
        $finalStatus = Resolve-SasSmbDeploymentFinalizationStatus -Result $_
        $row = [pscustomobject][ordered]@{
            computer_name = [string]$_.target
            transport = 'SmbScheduledTask'
            install_status = [string]$_.execution.installer_status
            source_sha256 = [string]$_.source_sha256
            target_sha256 = [string]$_.target_sha256
            task_created = [bool]$_.task.created
            task_started = [bool]$_.task.started
            execution_as_system = [bool]$_.execution.as_system
            result_retrieved = [bool]$_.result_retrieval.succeeded
            validation_before_cleanup_succeeded = [bool]$_.validation.before_payload_cleanup_succeeded
            validation_after_cleanup_succeeded = [bool]$_.validation.after_payload_cleanup_succeeded
            cleanup_attempted = [bool]$_.cleanup.attempted
            cleanup_succeeded = $cleanupSucceeded
            repo_artifact_remaining = ([bool]$_.cleanup.task_remaining -or [bool]$_.cleanup.run_root_remaining)
            requested_software_preserved_after_teardown = ($finalStatus -eq 'COMPLETED_VALIDATED_FINALIZED')
            reboot_required = [bool]$_.execution.reboot_required
            finalization_status = $finalStatus
            error = $_.error
        }
        Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'target_finalization_completed' -RunId ([string]$summary.run_id) -Data @{
            computer_name = [string]$_.target
            finalization_status = $finalStatus
            validation_before_cleanup_succeeded = [bool]$row.validation_before_cleanup_succeeded
            cleanup_succeeded = [bool]$row.cleanup_succeeded
            repo_artifact_remaining = [bool]$row.repo_artifact_remaining
            requested_software_preserved_after_teardown = [bool]$row.requested_software_preserved_after_teardown
        }
        $row
    })
    $completedCount = @($finalizationRows | Where-Object { $_.finalization_status -eq 'COMPLETED_VALIDATED_FINALIZED' }).Count
    $installFailureCount = @($finalizationRows | Where-Object { $_.finalization_status -eq 'INSTALL_FAILED_TOOLS_REMOVED' }).Count
    $validationFailureCount = @($finalizationRows | Where-Object { $_.finalization_status -eq 'VALIDATION_FAILED_TOOLS_REMOVED' }).Count
    $teardownFailureCount = @($finalizationRows | Where-Object { $_.finalization_status -eq 'TEARDOWN_FAILED' }).Count
    $preservationFailureCount = @($finalizationRows | Where-Object { $_.finalization_status -eq 'REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN' }).Count
    $deploymentComplete = ($finalizationRows.Count -gt 0 -and $completedCount -eq $finalizationRows.Count)
    $classification = if ($deploymentComplete) { 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED' }
    elseif ($teardownFailureCount -gt 0) { 'TEARDOWN_FAILED' }
    elseif ($preservationFailureCount -gt 0) { 'REQUESTED_SOFTWARE_NOT_PRESERVED' }
    elseif ($validationFailureCount -gt 0) { 'POST_INSTALL_VALIDATION_FAILED_TOOLS_REMOVED' }
    else { 'INSTALL_FAILED_TOOLS_REMOVED' }
    $finalization = [pscustomobject][ordered]@{
        schema_version = 'sas-software-install-finalization/v1'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        run_id = [string]$summary.run_id
        request_id = [string]$request.request_id
        package_name = [string]$request.package_name
        transport = 'SmbScheduledTask'
        classification = $classification
        deployment_complete = $deploymentComplete
        target_count = $finalizationRows.Count
        completed_validated_finalized_count = $completedCount
        install_failure_count = $installFailureCount
        validation_failure_count = $validationFailureCount
        teardown_failure_count = $teardownFailureCount
        preservation_failure_count = $preservationFailureCount
        cleanup_policy = 'repo_owned_run_scoped_only'
        requested_software_uninstall_performed = $false
        management_transport_used = $true
        network_activity_performed = $true
        target_mutation_performed = $true
        proof_level = 'source_and_target_hash_system_execution_result_retrieval_package_validation_and_run_scoped_teardown'
        results = $finalizationRows
    }
    $finalizationPath = Join-Path $runRoot 'software_install_finalization.json'
    $finalization | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $finalizationPath -Encoding UTF8
    $summary | Add-Member -NotePropertyName finalization_path -NotePropertyValue $finalizationPath -Force
    $summary | Add-Member -NotePropertyName deployment_complete -NotePropertyValue $deploymentComplete -Force
    $summary | Add-Member -NotePropertyName finalization_classification -NotePropertyValue $classification -Force
    $summary | Add-Member -NotePropertyName completed_validated_finalized_count -NotePropertyValue $completedCount -Force
    $summary | Add-Member -NotePropertyName validation_failure_count -NotePropertyValue $validationFailureCount -Force
    $summary | Add-Member -NotePropertyName teardown_failure_count -NotePropertyValue $teardownFailureCount -Force
    $summary | Add-Member -NotePropertyName preservation_failure_count -NotePropertyValue $preservationFailureCount -Force
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'finalization_completed' -RunId ([string]$summary.run_id) -Data @{
        classification = $classification
        deployment_complete = $deploymentComplete
        finalization_path = $finalizationPath
        completed_validated_finalized_count = $completedCount
        validation_failure_count = $validationFailureCount
        teardown_failure_count = $teardownFailureCount
        preservation_failure_count = $preservationFailureCount
    }
}
$result = [ordered]@{
    schema_version = 'sas-validated-software-deployment-result/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    request_id = [string]$request.request_id
    run_id = [string]$summary.run_id
    package_name = [string]$request.package_name
    transport_requested = $Transport
    transport = $selectedTransport
    transport_preflight_consumed = @($transportDecisions | Where-Object { $_.preflight_consumed }).Count -eq $transportDecisions.Count
    transport_selected_before_mutation = $true
    transport_fallback_attempted = $false
    classification = [string]$finalization.classification
    deployment_complete = [bool]$finalization.deployment_complete
    installer_path = $installerPath
    installer_hash_verified = ($observedInstallerHash -eq ([string]$request.installer_sha256).ToLowerInvariant())
    observed_installer_sha256 = $observedInstallerHash
    installer_signature_status = $signatureStatus
    observed_signer_thumbprint = $observedSignerThumbprint
    installer_arguments_reference = [string]$request.installer_arguments_reference
    authorization = [ordered]@{
        authorized_by = [string]$request.authorization.authorized_by
        request_reference = [string]$request.authorization.request_reference
        change_reference = [string]$request.authorization.change_reference
        ticket_reference = [string]$request.authorization.ticket_reference
    }
    finalization_performed = $true
    cleanup_policy = 'repo_owned_run_scoped_only'
    requested_software_uninstall_performed = $false
    management_transport_used = $true
    network_activity_performed = $true
    target_mutation_performed = $true
    reboot_required_count = $(if ($summary.PSObject.Properties.Name -contains 'reboot_required_count') { [int]$summary.reboot_required_count } else { 0 })
    install_summary_path = $summaryPath
    finalization_path = Join-Path $runRoot 'software_install_finalization.json'
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $orchestrationPath -Encoding UTF8
if ($selectedTransport -eq 'SmbScheduledTask') {
    Write-SasValidatedDeploymentEvent -Path $eventPath -Name 'run_completed' -RunId ([string]$summary.run_id) -Data @{
        classification = [string]$result.classification
        deployment_complete = [bool]$result.deployment_complete
        completed_count = [int]$summary.completed_count
        failed_count = [int]$summary.failed_count
        cleanup_failure_count = [int]$summary.cleanup_failure_count
        repo_artifact_remaining_count = [int]$summary.repo_artifact_remaining_count
    }
}

Write-Host "Validated deployment classification: $($result.classification)"
Write-Host "Deployment complete: $($result.deployment_complete)"
Write-Host "Result artifact: $orchestrationPath"
Write-Output ([pscustomobject]$result)
if (-not $result.deployment_complete) { throw "Validated deployment did not complete: $($result.classification)" }
