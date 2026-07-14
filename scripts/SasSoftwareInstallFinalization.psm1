#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-SasValidatedDeploymentRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Request)

    function Test-SasClosedObject {
        param($Value)
        return ($null -ne $Value -and $Value -is [pscustomobject])
    }

    function Test-SasStringRange {
        param($Value, [int]$Minimum, [int]$Maximum)
        return ($Value -is [string] -and $Value.Length -ge $Minimum -and $Value.Length -le $Maximum)
    }

    function Test-SasJsonPrimitive {
        param($Value)
        return (
            $Value -is [string] -or $Value -is [bool] -or
            $Value -is [byte] -or $Value -is [sbyte] -or
            $Value -is [int16] -or $Value -is [uint16] -or
            $Value -is [int32] -or $Value -is [uint32] -or
            $Value -is [int64] -or $Value -is [uint64] -or
            $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
        )
    }

    function Get-SasUnknownPropertyErrors {
        param($Value, [string[]]$Allowed, [string]$Prefix)
        if (-not (Test-SasClosedObject -Value $Value)) { return @() }
        return @(
            $Value.PSObject.Properties.Name |
                Where-Object { $Allowed -notcontains $_ } |
                ForEach-Object { "${Prefix}:$_" }
        )
    }

    $errors = @()
    if (-not (Test-SasClosedObject -Value $Request)) { return @('REQUEST_OBJECT_INVALID') }

    $required = @(
        'schema_version','request_id','package_name','software_share_root','installer_relative_path',
        'installer_sha256','installer_arguments','installer_arguments_reference','install_mode','targets',
        'authorization','validation','cleanup_policy'
    )
    $optional = @('require_valid_signature','expected_signer_thumbprint')
    $errors += @(Get-SasUnknownPropertyErrors -Value $Request -Allowed @($required + $optional) -Prefix 'REQUEST_FIELD_UNKNOWN')
    foreach ($name in $required) {
        if ($Request.PSObject.Properties.Name -notcontains $name) { $errors += "REQUEST_FIELD_MISSING:$name" }
    }
    if (@($errors | Where-Object { $_ -like 'REQUEST_FIELD_MISSING:*' }).Count -gt 0) { return @($errors) }

    if ($Request.schema_version -isnot [string] -or [string]$Request.schema_version -ne 'sas-validated-software-deployment-request/v1') { $errors += 'REQUEST_SCHEMA_UNSUPPORTED' }
    if ($Request.request_id -isnot [string] -or [string]$Request.request_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,96}$') { $errors += 'REQUEST_ID_INVALID' }
    if (-not (Test-SasStringRange -Value $Request.package_name -Minimum 1 -Maximum 160)) { $errors += 'PACKAGE_NAME_INVALID' }
    if ($Request.software_share_root -isnot [string] -or [string]$Request.software_share_root -notmatch '^\\\\[^\\]+\\?$') { $errors += 'SOFTWARE_SHARE_ROOT_INVALID' }

    $relative = if ($Request.installer_relative_path -is [string]) { $Request.installer_relative_path.Trim().Replace('/', '\') } else { '' }
    if (-not (Test-SasStringRange -Value $Request.installer_relative_path -Minimum 1 -Maximum 512) -or
        [IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('\') -or $relative -match '(^|\\)\.\.(\\|$)') {
        $errors += 'INSTALLER_RELATIVE_PATH_INVALID'
    }
    if ($Request.installer_sha256 -isnot [string] -or [string]$Request.installer_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $errors += 'INSTALLER_SHA256_INVALID' }

    if ($Request.installer_arguments -isnot [System.Array]) { $errors += 'INSTALLER_ARGUMENTS_NOT_ARRAY' }
    $arguments = @($Request.installer_arguments)
    if ($arguments.Count -lt 1 -or $arguments.Count -gt 32 -or
        @($arguments | Where-Object { -not (Test-SasStringRange -Value $_ -Minimum 1 -Maximum 1024) }).Count -gt 0) {
        $errors += 'INSTALLER_ARGUMENTS_INVALID'
    }
    if (-not (Test-SasStringRange -Value $Request.installer_arguments_reference -Minimum 3 -Maximum 512)) { $errors += 'INSTALLER_ARGUMENTS_REFERENCE_INVALID' }
    if ($Request.install_mode -isnot [string] -or [string]$Request.install_mode -notin @('UncDirect','CopyThenInstall')) { $errors += 'INSTALL_MODE_INVALID' }

    if ($Request.targets -isnot [System.Array]) { $errors += 'TARGETS_NOT_ARRAY' }
    $targets = @($Request.targets)
    if ($targets.Count -lt 1 -or $targets.Count -gt 25 -or
        @($targets | Where-Object { $_ -isnot [string] -or $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$' }).Count -gt 0) {
        $errors += 'TARGETS_INVALID'
    }
    $seenTargets = @{}
    foreach ($target in $targets) {
        if ($target -isnot [string]) { continue }
        if ($seenTargets.ContainsKey($target)) { $errors += "TARGET_DUPLICATE:$target" }
        else { $seenTargets[$target] = $true }
    }

    $authorizationFields = @('authorized_by','request_reference','change_reference','ticket_reference')
    if (-not (Test-SasClosedObject -Value $Request.authorization)) {
        $errors += 'AUTHORIZATION_OBJECT_INVALID'
    }
    else {
        $errors += @(Get-SasUnknownPropertyErrors -Value $Request.authorization -Allowed $authorizationFields -Prefix 'AUTHORIZATION_FIELD_UNKNOWN')
        foreach ($name in $authorizationFields) {
            if ($Request.authorization.PSObject.Properties.Name -notcontains $name -or
                -not (Test-SasStringRange -Value $Request.authorization.$name -Minimum 2 -Maximum 160)) {
                $errors += "AUTHORIZATION_FIELD_INVALID:$name"
            }
        }
    }

    if ($Request.cleanup_policy -isnot [string] -or [string]$Request.cleanup_policy -ne 'repo_owned_run_scoped_only') { $errors += 'CLEANUP_POLICY_INVALID' }
    if ($Request.PSObject.Properties.Name -contains 'require_valid_signature' -and $Request.require_valid_signature -isnot [bool]) {
        $errors += 'REQUIRE_VALID_SIGNATURE_TYPE_INVALID'
    }
    if ($Request.PSObject.Properties.Name -contains 'expected_signer_thumbprint' -and
        ($Request.expected_signer_thumbprint -isnot [string] -or [string]$Request.expected_signer_thumbprint -notmatch '^[A-Fa-f0-9]{40,64}$')) {
        $errors += 'EXPECTED_SIGNER_THUMBPRINT_INVALID'
    }
    if ($Request.PSObject.Properties.Name -contains 'require_valid_signature' -and
        $Request.require_valid_signature -is [bool] -and [bool]$Request.require_valid_signature -and
        $Request.PSObject.Properties.Name -notcontains 'expected_signer_thumbprint') {
        $errors += 'EXPECTED_SIGNER_THUMBPRINT_REQUIRED'
    }

    if (-not (Test-SasClosedObject -Value $Request.validation)) {
        $errors += 'VALIDATION_OBJECT_INVALID'
        return @($errors)
    }
    $errors += @(Get-SasUnknownPropertyErrors -Value $Request.validation -Allowed @('checks') -Prefix 'VALIDATION_FIELD_UNKNOWN')
    if ($Request.validation.PSObject.Properties.Name -notcontains 'checks') {
        $errors += 'VALIDATION_CHECKS_MISSING'
        return @($errors)
    }
    if ($Request.validation.checks -isnot [System.Array]) { $errors += 'VALIDATION_CHECKS_NOT_ARRAY' }
    $checks = @($Request.validation.checks)
    if ($checks.Count -lt 1 -or $checks.Count -gt 16) { $errors += 'VALIDATION_CHECK_COUNT_INVALID' }

    $checkFields = @(
        'id','type','required','path','expected_sha256','expected_version','property_path','expected_value',
        'registry_path','value_name','display_name','service_name','expected_status'
    )
    $checkTypes = @('FileExists','FileSha256Equals','FileVersionEquals','JsonPropertyEquals','RegistryValueEquals','UninstallEntry','ServiceExists')
    $ids = @{}
    foreach ($check in $checks) {
        if (-not (Test-SasClosedObject -Value $check)) {
            $errors += 'VALIDATION_CHECK_OBJECT_INVALID'
            continue
        }
        $errors += @(Get-SasUnknownPropertyErrors -Value $check -Allowed $checkFields -Prefix 'VALIDATION_CHECK_FIELD_UNKNOWN')

        $id = if ($check.PSObject.Properties.Name -contains 'id') { [string]$check.id } else { '<missing>' }
        $type = if ($check.PSObject.Properties.Name -contains 'type') { [string]$check.type } else { '<missing>' }
        if ($check.PSObject.Properties.Name -notcontains 'id' -or $check.id -isnot [string] -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$') {
            $errors += 'VALIDATION_CHECK_ID_INVALID'
        }
        elseif ($ids.ContainsKey($id)) { $errors += "VALIDATION_CHECK_ID_DUPLICATE:$id" }
        else { $ids[$id] = $true }

        if ($check.PSObject.Properties.Name -notcontains 'type' -or $check.type -isnot [string] -or $type -notin $checkTypes) {
            $errors += "VALIDATION_CHECK_TYPE_INVALID:$id"
            continue
        }
        if ($check.PSObject.Properties.Name -notcontains 'required' -or $check.required -isnot [bool]) { $errors += "VALIDATION_REQUIRED_FLAG_INVALID:$id" }

        if ($check.PSObject.Properties.Name -contains 'path' -and
            (-not (Test-SasStringRange -Value $check.path -Minimum 3 -Maximum 1024) -or [string]$check.path -match '[*?]')) {
            $errors += "VALIDATION_PATH_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'expected_sha256' -and
            ($check.expected_sha256 -isnot [string] -or [string]$check.expected_sha256 -notmatch '^[A-Fa-f0-9]{64}$')) {
            $errors += "VALIDATION_SHA256_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'expected_version' -and
            -not (Test-SasStringRange -Value $check.expected_version -Minimum 1 -Maximum 160)) {
            $errors += "VALIDATION_VERSION_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'property_path' -and
            ($check.property_path -isnot [string] -or [string]$check.property_path -notmatch '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$')) {
            $errors += "VALIDATION_PROPERTY_PATH_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'expected_value' -and -not (Test-SasJsonPrimitive -Value $check.expected_value)) {
            $errors += "VALIDATION_EXPECTED_VALUE_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'registry_path' -and
            ($check.registry_path -isnot [string] -or [string]$check.registry_path -notmatch '^HKLM:\\[^*?]+$')) {
            $errors += "VALIDATION_REGISTRY_PATH_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'value_name' -and
            (-not (Test-SasStringRange -Value $check.value_name -Minimum 1 -Maximum 160) -or [string]$check.value_name -match '(?i)password|secret|token|credential|private.?key')) {
            $errors += "VALIDATION_REGISTRY_VALUE_NAME_FORBIDDEN:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'display_name' -and -not (Test-SasStringRange -Value $check.display_name -Minimum 1 -Maximum 260)) {
            $errors += "VALIDATION_DISPLAY_NAME_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'service_name' -and
            ($check.service_name -isnot [string] -or [string]$check.service_name -notmatch '^[A-Za-z0-9_.-]{1,256}$')) {
            $errors += "VALIDATION_SERVICE_NAME_INVALID:$id"
        }
        if ($check.PSObject.Properties.Name -contains 'expected_status' -and
            ($check.expected_status -isnot [string] -or [string]$check.expected_status -notin @('Running','Stopped','Paused'))) {
            $errors += "VALIDATION_SERVICE_STATUS_INVALID:$id"
        }

        if ($type -in @('FileExists','FileSha256Equals','FileVersionEquals','JsonPropertyEquals') -and
            ($check.PSObject.Properties.Name -notcontains 'path' -or -not (Test-SasStringRange -Value $check.path -Minimum 3 -Maximum 1024) -or [string]$check.path -match '[*?]')) {
            $errors += "VALIDATION_PATH_INVALID:$id"
        }
        if ($type -eq 'FileSha256Equals' -and
            ($check.PSObject.Properties.Name -notcontains 'expected_sha256' -or $check.expected_sha256 -isnot [string] -or [string]$check.expected_sha256 -notmatch '^[A-Fa-f0-9]{64}$')) {
            $errors += "VALIDATION_SHA256_INVALID:$id"
        }
        if ($type -eq 'FileVersionEquals' -and
            ($check.PSObject.Properties.Name -notcontains 'expected_version' -or -not (Test-SasStringRange -Value $check.expected_version -Minimum 1 -Maximum 160))) {
            $errors += "VALIDATION_VERSION_MISSING:$id"
        }
        if ($type -eq 'JsonPropertyEquals') {
            if ($check.PSObject.Properties.Name -notcontains 'property_path' -or $check.property_path -isnot [string] -or [string]$check.property_path -notmatch '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$') { $errors += "VALIDATION_PROPERTY_PATH_INVALID:$id" }
            if ($check.PSObject.Properties.Name -notcontains 'expected_value' -or -not (Test-SasJsonPrimitive -Value $check.expected_value)) { $errors += "VALIDATION_EXPECTED_VALUE_MISSING:$id" }
        }
        if ($type -eq 'RegistryValueEquals') {
            if ($check.PSObject.Properties.Name -notcontains 'registry_path' -or $check.registry_path -isnot [string] -or [string]$check.registry_path -notmatch '^HKLM:\\[^*?]+$') { $errors += "VALIDATION_REGISTRY_PATH_INVALID:$id" }
            if ($check.PSObject.Properties.Name -notcontains 'value_name' -or -not (Test-SasStringRange -Value $check.value_name -Minimum 1 -Maximum 160) -or [string]$check.value_name -match '(?i)password|secret|token|credential|private.?key') { $errors += "VALIDATION_REGISTRY_VALUE_NAME_FORBIDDEN:$id" }
            if ($check.PSObject.Properties.Name -notcontains 'expected_value' -or -not (Test-SasJsonPrimitive -Value $check.expected_value)) { $errors += "VALIDATION_EXPECTED_VALUE_MISSING:$id" }
        }
        if ($type -eq 'UninstallEntry' -and
            ($check.PSObject.Properties.Name -notcontains 'display_name' -or -not (Test-SasStringRange -Value $check.display_name -Minimum 1 -Maximum 260))) {
            $errors += "VALIDATION_DISPLAY_NAME_MISSING:$id"
        }
        if ($type -eq 'ServiceExists' -and
            ($check.PSObject.Properties.Name -notcontains 'service_name' -or $check.service_name -isnot [string] -or [string]$check.service_name -notmatch '^[A-Za-z0-9_.-]{1,256}$')) {
            $errors += "VALIDATION_SERVICE_NAME_INVALID:$id"
        }
    }
    return @($errors | Select-Object -Unique)
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
