#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-SasValidatedDeploymentRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Request)

    $errors = @()
    $required = @(
        'schema_version','request_id','package_name','software_share_root','installer_relative_path',
        'installer_sha256','installer_arguments','installer_arguments_reference','install_mode','targets',
        'authorization','validation','cleanup_policy'
    )
    foreach ($name in $required) {
        if ($Request.PSObject.Properties.Name -notcontains $name) { $errors += "REQUEST_FIELD_MISSING:$name" }
    }
    if ($errors.Count -gt 0) { return @($errors) }

    if ([string]$Request.schema_version -ne 'sas-validated-software-deployment-request/v1') { $errors += 'REQUEST_SCHEMA_UNSUPPORTED' }
    if ([string]$Request.request_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,96}$') { $errors += 'REQUEST_ID_INVALID' }
    if ([string]::IsNullOrWhiteSpace([string]$Request.package_name)) { $errors += 'PACKAGE_NAME_MISSING' }
    if ([string]$Request.software_share_root -notmatch '^\\\\[^\\]+\\?$') { $errors += 'SOFTWARE_SHARE_ROOT_INVALID' }
    $relative = ([string]$Request.installer_relative_path).Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('\') -or $relative -match '(^|\\)\.\.(\\|$)') {
        $errors += 'INSTALLER_RELATIVE_PATH_INVALID'
    }
    if ([string]$Request.installer_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $errors += 'INSTALLER_SHA256_INVALID' }
    $arguments = @($Request.installer_arguments)
    if ($arguments.Count -lt 1 -or $arguments.Count -gt 32 -or @($arguments | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        $errors += 'INSTALLER_ARGUMENTS_INVALID'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Request.installer_arguments_reference)) { $errors += 'INSTALLER_ARGUMENTS_REFERENCE_MISSING' }
    if ([string]$Request.install_mode -notin @('UncDirect','CopyThenInstall')) { $errors += 'INSTALL_MODE_INVALID' }
    $targets = @($Request.targets | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($targets.Count -lt 1 -or $targets.Count -gt 25 -or @($targets | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$' }).Count -gt 0) {
        $errors += 'TARGETS_INVALID'
    }
    foreach ($name in @('authorized_by','request_reference','change_reference','ticket_reference')) {
        if ($null -eq $Request.authorization -or $Request.authorization.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$Request.authorization.$name)) {
            $errors += "AUTHORIZATION_FIELD_MISSING:$name"
        }
    }
    if ([string]$Request.cleanup_policy -ne 'repo_owned_run_scoped_only') { $errors += 'CLEANUP_POLICY_INVALID' }
    if ($Request.PSObject.Properties.Name -contains 'require_valid_signature' -and [bool]$Request.require_valid_signature) {
        if ($Request.PSObject.Properties.Name -notcontains 'expected_signer_thumbprint' -or [string]$Request.expected_signer_thumbprint -notmatch '^[A-Fa-f0-9]{40,64}$') {
            $errors += 'EXPECTED_SIGNER_THUMBPRINT_REQUIRED'
        }
    }

    $checks = @($Request.validation.checks)
    if ($checks.Count -lt 1 -or $checks.Count -gt 16) { $errors += 'VALIDATION_CHECK_COUNT_INVALID' }
    $ids = @{}
    foreach ($check in $checks) {
        $id = [string]$check.id
        $type = [string]$check.type
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$') { $errors += 'VALIDATION_CHECK_ID_INVALID' }
        elseif ($ids.ContainsKey($id)) { $errors += "VALIDATION_CHECK_ID_DUPLICATE:$id" }
        else { $ids[$id] = $true }
        if ($type -notin @('FileExists','FileSha256Equals','FileVersionEquals','JsonPropertyEquals','RegistryValueEquals','UninstallEntry','ServiceExists')) {
            $errors += "VALIDATION_CHECK_TYPE_INVALID:$id"
            continue
        }
        if ($check.PSObject.Properties.Name -notcontains 'required' -or $check.required -isnot [bool]) { $errors += "VALIDATION_REQUIRED_FLAG_INVALID:$id" }
        if ($type -like 'File*' -or $type -eq 'JsonPropertyEquals') {
            if ([string]::IsNullOrWhiteSpace([string]$check.path) -or [string]$check.path -match '[*?]') { $errors += "VALIDATION_PATH_INVALID:$id" }
        }
        if ($type -eq 'FileSha256Equals' -and [string]$check.expected_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $errors += "VALIDATION_SHA256_INVALID:$id" }
        if ($type -eq 'FileVersionEquals' -and [string]::IsNullOrWhiteSpace([string]$check.expected_version)) { $errors += "VALIDATION_VERSION_MISSING:$id" }
        if ($type -eq 'JsonPropertyEquals') {
            if ([string]$check.property_path -notmatch '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$') { $errors += "VALIDATION_PROPERTY_PATH_INVALID:$id" }
            if ($check.PSObject.Properties.Name -notcontains 'expected_value') { $errors += "VALIDATION_EXPECTED_VALUE_MISSING:$id" }
        }
        if ($type -eq 'RegistryValueEquals') {
            if ([string]$check.registry_path -notmatch '^HKLM:\\[^*?]+$') { $errors += "VALIDATION_REGISTRY_PATH_INVALID:$id" }
            if ([string]::IsNullOrWhiteSpace([string]$check.value_name) -or [string]$check.value_name -match '(?i)password|secret|token|credential|private.?key') {
                $errors += "VALIDATION_REGISTRY_VALUE_NAME_FORBIDDEN:$id"
            }
            if ($check.PSObject.Properties.Name -notcontains 'expected_value') { $errors += "VALIDATION_EXPECTED_VALUE_MISSING:$id" }
        }
        if ($type -eq 'UninstallEntry' -and [string]::IsNullOrWhiteSpace([string]$check.display_name)) { $errors += "VALIDATION_DISPLAY_NAME_MISSING:$id" }
        if ($type -eq 'ServiceExists' -and [string]$check.service_name -notmatch '^[A-Za-z0-9_.-]{1,256}$') { $errors += "VALIDATION_SERVICE_NAME_INVALID:$id" }
    }
    return @($errors)
}

function Get-SasSoftwareValidationScriptBlock {
    [CmdletBinding()]
    param()

    return {
        param([string]$ChecksJson)
        $ErrorActionPreference = 'Stop'
        $checks = @($ChecksJson | ConvertFrom-Json)
        $results = @()

        function Resolve-ExactPath {
            param([string]$Path)
            $expanded = [Environment]::ExpandEnvironmentVariables($Path)
            if ([string]::IsNullOrWhiteSpace($expanded) -or $expanded -match '[*?]' -or -not [IO.Path]::IsPathRooted($expanded)) {
                throw "Validation path must be an exact absolute path: $Path"
            }
            return [IO.Path]::GetFullPath($expanded)
        }

        foreach ($check in $checks) {
            $passed = $false
            $observed = $null
            $errorMessage = $null
            try {
                switch ([string]$check.type) {
                    'FileExists' {
                        $path = Resolve-ExactPath ([string]$check.path)
                        $passed = Test-Path -LiteralPath $path -PathType Leaf
                        $observed = if ($passed) { 'present' } else { 'missing' }
                    }
                    'FileSha256Equals' {
                        $path = Resolve-ExactPath ([string]$check.path)
                        if (Test-Path -LiteralPath $path -PathType Leaf) {
                            $observed = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                            $passed = $observed -eq ([string]$check.expected_sha256).ToLowerInvariant()
                        } else { $observed = 'missing' }
                    }
                    'FileVersionEquals' {
                        $path = Resolve-ExactPath ([string]$check.path)
                        if (Test-Path -LiteralPath $path -PathType Leaf) {
                            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
                            $observed = if ($versionInfo.ProductVersion) { [string]$versionInfo.ProductVersion } else { [string]$versionInfo.FileVersion }
                            $passed = $observed -eq [string]$check.expected_version
                        } else { $observed = 'missing' }
                    }
                    'JsonPropertyEquals' {
                        $path = Resolve-ExactPath ([string]$check.path)
                        if (Test-Path -LiteralPath $path -PathType Leaf) {
                            $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                            foreach ($segment in ([string]$check.property_path -split '\.')) {
                                if ($null -eq $value -or $value.PSObject.Properties.Name -notcontains $segment) { throw "JSON property segment not found: $segment" }
                                $value = $value.$segment
                            }
                            $observed = [string]$value
                            $passed = $observed -eq [string]$check.expected_value
                        } else { $observed = 'missing' }
                    }
                    'RegistryValueEquals' {
                        $registryPath = [string]$check.registry_path
                        $valueName = [string]$check.value_name
                        if ($registryPath -notmatch '^HKLM:\\[^*?]+$' -or $valueName -match '(?i)password|secret|token|credential|private.?key') {
                            throw 'Registry validation is restricted to exact non-secret HKLM values.'
                        }
                        $value = Get-ItemPropertyValue -LiteralPath $registryPath -Name $valueName -ErrorAction Stop
                        $observed = [string]$value
                        $passed = $observed -eq [string]$check.expected_value
                    }
                    'UninstallEntry' {
                        $roots = @(
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                        )
                        $entries = @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue | Where-Object { [string]$_.DisplayName -eq [string]$check.display_name })
                        $observed = if ($entries.Count -gt 0) { @($entries | ForEach-Object { [string]$_.DisplayVersion } | Sort-Object -Unique) -join ';' } else { 'missing' }
                        $passed = $entries.Count -gt 0
                        if ($passed -and $check.PSObject.Properties.Name -contains 'expected_version' -and -not [string]::IsNullOrWhiteSpace([string]$check.expected_version)) {
                            $passed = @($entries | Where-Object { [string]$_.DisplayVersion -eq [string]$check.expected_version }).Count -gt 0
                        }
                    }
                    'ServiceExists' {
                        $service = Get-Service -Name ([string]$check.service_name) -ErrorAction Stop
                        $observed = [string]$service.Status
                        $passed = $true
                        if ($check.PSObject.Properties.Name -contains 'expected_status' -and -not [string]::IsNullOrWhiteSpace([string]$check.expected_status)) {
                            $passed = $observed -eq [string]$check.expected_status
                        }
                    }
                    default { throw "Unsupported validation check type: $($check.type)" }
                }
            }
            catch {
                $passed = $false
                $errorMessage = $_.Exception.Message
            }
            $results += [pscustomobject][ordered]@{
                id = [string]$check.id
                type = [string]$check.type
                required = [bool]$check.required
                passed = [bool]$passed
                observed = $observed
                error = $errorMessage
            }
        }
        $requiredFailures = @($results | Where-Object { $_.required -and -not $_.passed })
        return [pscustomobject][ordered]@{
            succeeded = ($requiredFailures.Count -eq 0)
            required_check_count = @($results | Where-Object { $_.required }).Count
            failed_required_check_count = $requiredFailures.Count
            checks = @($results)
            network_activity_performed = $false
            target_mutation_performed = $false
        }
    }
}

function Get-SasSoftwareCleanupScriptBlock {
    [CmdletBinding()]
    param()

    return {
        param([string]$RunId)
        $ErrorActionPreference = 'Stop'
        $stageRoot = Join-Path -Path $env:ProgramData -ChildPath ("SysAdminSuite\SoftwareInstall\{0}" -f $RunId)
        $softwareInstallRoot = Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite\SoftwareInstall'
        $suiteRoot = Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite'
        $expectedBase = [IO.Path]::GetFullPath($softwareInstallRoot)
        $expectedStageRoot = [IO.Path]::GetFullPath((Join-Path $expectedBase $RunId))
        if ($RunId -notmatch '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$' -or
            -not [IO.Path]::GetFullPath($stageRoot).Equals($expectedStageRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup because the run-scoped staging path failed validation.'
        }
        $removed = @()
        $pruned = @()
        $errorMessage = $null
        try {
            if (Test-Path -LiteralPath $stageRoot) {
                Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction Stop
                $removed += $stageRoot
            }
            foreach ($parent in @($softwareInstallRoot, $suiteRoot)) {
                if (Test-Path -LiteralPath $parent) {
                    $children = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop)
                    if ($children.Count -eq 0) {
                        Remove-Item -LiteralPath $parent -Force -ErrorAction Stop
                        $pruned += $parent
                    }
                }
            }
        }
        catch { $errorMessage = $_.Exception.Message }
        $remaining = Test-Path -LiteralPath $stageRoot
        return [pscustomobject][ordered]@{
            cleanup_attempted = $true
            cleanup_succeeded = (-not $remaining -and [string]::IsNullOrWhiteSpace($errorMessage))
            repo_owned_stage_root = $stageRoot
            repo_artifact_remaining = [bool]$remaining
            removed_paths = @($removed)
            pruned_empty_parent_dirs = @($pruned)
            error = $errorMessage
        }
    }
}

Export-ModuleMember -Function Test-SasValidatedDeploymentRequest, Get-SasSoftwareValidationScriptBlock, Get-SasSoftwareCleanupScriptBlock
