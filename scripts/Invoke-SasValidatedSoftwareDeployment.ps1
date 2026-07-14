#Requires -Version 5.1
<#
.SYNOPSIS
Executes an authorized software installation, validates the requested package, and finalizes SysAdminSuite teardown.

.DESCRIPTION
This is the canonical deployment entrypoint when client-requested software must be installed and the workstation
must be left without SysAdminSuite tooling or staging. It validates a closed JSON request, pins the installer by
SHA-256, delegates installation to Invoke-SasSoftwareInstall.ps1, invokes package-specific read-only checks,
performs idempotent run-scoped cleanup, and confirms the package evidence remains after cleanup.
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
    [switch]$AllowFixtures
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path $PSScriptRoot 'SasSoftwareInstallFinalization.psm1'
$installerScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstall.ps1'
$finalizerScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstallFinalization.ps1'
foreach ($requiredPath in @($modulePath, $installerScript, $finalizerScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Missing required validated deployment surface: $requiredPath" }
}
Import-Module $modulePath -Force

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

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing validated deployment without -AllowTargetMutation. Use -WhatIf for request-only planning.'
}

$RequestPath = Resolve-ApprovedRequestPath -Path $RequestPath
if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) { throw "Validated deployment request not found: $RequestPath" }
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$requestErrors = @(Test-SasValidatedDeploymentRequest -Request $request)
if ($requestErrors.Count -gt 0) { throw "Validated deployment request failed closed: $($requestErrors -join ', ')" }

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
$orchestrationPath = Join-Path $runRoot 'validated_deployment_result.json'
$summaryPath = Join-Path $runRoot 'software_install_summary.json'

if ($WhatIfPreference) {
    $planResult = [ordered]@{
        schema_version = 'sas-validated-software-deployment-result/v1'
        request_id = [string]$request.request_id
        run_id = [string]$summary.run_id
        package_name = [string]$request.package_name
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

$finalization = & $finalizerScript `
    -InstallSummaryPath $summaryPath `
    -RequestPath $RequestPath `
    -AllowTargetMutation `
    -AllowFixtures:$AllowFixtures `
    -Confirm:$false
$result = [ordered]@{
    schema_version = 'sas-validated-software-deployment-result/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    request_id = [string]$request.request_id
    run_id = [string]$summary.run_id
    package_name = [string]$request.package_name
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
    install_summary_path = $summaryPath
    finalization_path = Join-Path $runRoot 'software_install_finalization.json'
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $orchestrationPath -Encoding UTF8

Write-Host "Validated deployment classification: $($result.classification)"
Write-Host "Deployment complete: $($result.deployment_complete)"
Write-Host "Result artifact: $orchestrationPath"
Write-Output ([pscustomobject]$result)
if (-not $result.deployment_complete) { throw "Validated deployment did not complete: $($result.classification)" }
