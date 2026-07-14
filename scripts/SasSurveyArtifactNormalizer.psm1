#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:DefaultRegistryRelative = 'survey/network_survey_artifact_adapters.json'
$script:DefaultSchemaRelative = 'schemas/survey/network-survey-artifact-denominator.schema.json'

function Get-SasSurveyArtifactRepoRoot {
    [CmdletBinding()]
    param([string]$StartPath = $PSScriptRoot)

    $cursor = [System.IO.Path]::GetFullPath($StartPath)
    while ($cursor) {
        if ((Test-Path -LiteralPath (Join-Path $cursor 'survey')) -and
            (Test-Path -LiteralPath (Join-Path $cursor 'targets/README.md'))) {
            return $cursor
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    throw 'Unable to resolve SysAdminSuite repo root for survey artifact normalization.'
}

function Get-SasSurveyArtifactRegistry {
    [CmdletBinding()]
    param([string]$RepoRoot, [string]$RegistryPath)

    if (-not $RepoRoot) { $RepoRoot = Get-SasSurveyArtifactRepoRoot }
    if (-not $RegistryPath) { $RegistryPath = Join-Path $RepoRoot $script:DefaultRegistryRelative }
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        throw "Missing network survey artifact adapter registry: $RegistryPath"
    }
    return Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SasSurveyArtifactSchema {
    [CmdletBinding()]
    param([string]$RepoRoot, [string]$SchemaPath)

    if (-not $RepoRoot) { $RepoRoot = Get-SasSurveyArtifactRepoRoot }
    if (-not $SchemaPath) { $SchemaPath = Join-Path $RepoRoot $script:DefaultSchemaRelative }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "Missing network survey denominator schema: $SchemaPath"
    }
    return Get-Content -LiteralPath $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SasSurveyArtifactFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
    if ($extension -notin @('csv', 'txt', 'json', 'jsonl')) {
        throw "Unsupported survey artifact format '$extension'. Supported formats: csv, txt, json, jsonl."
    }
    return $extension
}

function ConvertTo-SasSurveyNormalizedSerial {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    return (([string]$Value).Trim().ToUpperInvariant() -replace '[^A-Z0-9]', '')
}

function ConvertTo-SasSurveyNormalizedTarget {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    return ([string]$Value).Trim().TrimEnd('.').ToLowerInvariant()
}

function ConvertTo-SasSurveyBoolean {
    [CmdletBinding()]
    param([object]$Value)
    if ($Value -is [bool]) { return [bool]$Value }
    if ($null -eq $Value) { return $false }
    return ([string]$Value).Trim() -match '^(1|true|yes|y|confirmed)$'
}

function ConvertTo-SasSurveyTimestamp {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse(([string]$Value).Trim(), [ref]$parsed)) { return $parsed }
    return $null
}

function ConvertTo-SasSurveyStringList {
    [CmdletBinding()]
    param([object]$Value)

    $items = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return @() }
    $values = if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { @($Value) } else { @(([string]$Value) -split '[,;|]') }
    foreach ($item in $values) {
        $clean = ([string]$item).Trim()
        if ($clean -and -not $items.Contains($clean)) { $items.Add($clean) }
    }
    return @($items)
}

function ConvertTo-SasSurveyPortList {
    [CmdletBinding()]
    param([object]$OpenPorts, [object]$Port, [object]$PortStatus)

    $ports = New-Object System.Collections.Generic.List[int]
    foreach ($value in @(ConvertTo-SasSurveyStringList -Value $OpenPorts)) {
        $parsed = 0
        if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 65535 -and -not $ports.Contains($parsed)) {
            $ports.Add($parsed)
        }
    }
    if (([string]$PortStatus).Trim().ToLowerInvariant() -eq 'open') {
        $parsed = 0
        if ([int]::TryParse(([string]$Port), [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 65535 -and -not $ports.Contains($parsed)) {
            $ports.Add($parsed)
        }
    }
    return @($ports | Sort-Object)
}

function Get-SasSurveyMappedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$CanonicalField
    )

    $mappingProperty = $Adapter.mappings.PSObject.Properties | Where-Object { $_.Name -eq $CanonicalField } | Select-Object -First 1
    if ($null -eq $mappingProperty) { return $null }
    foreach ($alias in @($mappingProperty.Value)) {
        $property = $Row.PSObject.Properties | Where-Object { $_.Name -ieq [string]$alias } | Select-Object -First 1
        if ($null -ne $property -and $null -ne $property.Value) {
            if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace($property.Value)) { continue }
            return $property.Value
        }
    }
    return $null
}

function Read-SasSurveyArtifactRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Format)

    switch ($Format) {
        'csv' { return @(Import-Csv -LiteralPath $Path) }
        'txt' {
            return @(Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
                $value = ([string]$_).Trim()
                if ($value -and -not $value.StartsWith('#')) { [pscustomobject]@{ Target = $value } }
            })
        }
        'json' {
            $parsed = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $parsed.PSObject.Properties['rows']) { return @($parsed.rows) }
            return @($parsed)
        }
        'jsonl' {
            return @(Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
                $line = ([string]$_).Trim()
                if ($line) { $line | ConvertFrom-Json }
            })
        }
    }
}

function Get-SasSurveyArtifactHeaders {
    [CmdletBinding()]
    param([object[]]$Rows)

    $headers = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($Rows | Select-Object -First 20)) {
        foreach ($property in $row.PSObject.Properties) { [void]$headers.Add($property.Name) }
    }
    return @($headers | Sort-Object)
}

function Test-SasSurveyAdapterDetection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string[]]$Headers)

    foreach ($group in @($Adapter.detection.required_any)) {
        $matched = $false
        foreach ($alias in @($group)) {
            if ($Headers -contains ([string]$alias)) { $matched = $true; break }
        }
        if (-not $matched) { return $false }
    }
    return $true
}

function Select-SasSurveyArtifactAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][ValidateSet('requested_population', 'evidence_snapshot')][string]$Role,
        [Parameter(Mandatory = $true)][string]$Format,
        [Parameter(Mandatory = $true)][string[]]$Headers
    )

    $matches = @($Registry.adapters | Where-Object {
        ($_.role -eq $Role) -and (@($_.formats) -contains $Format) -and (Test-SasSurveyAdapterDetection -Adapter $_ -Headers $Headers)
    } | Sort-Object @{ Expression = { [int]$_.priority }; Descending = $true })
    if ($matches.Count -eq 0) {
        throw "No registered network survey adapter accepted role '$Role', format '$Format', and headers: $($Headers -join ', ')."
    }
    $topPriority = [int]$matches[0].priority
    $top = @($matches | Where-Object { [int]$_.priority -eq $topPriority })
    if ($top.Count -ne 1) { throw "Ambiguous network survey adapters at priority ${topPriority}: $(@($top.id) -join ', ')." }
    return $top[0]
}

function Get-SasSurveyEvidenceType {
    [CmdletBinding()]
    param(
        [string]$Role,
        [object]$ExplicitType,
        [bool]$IdentityConfirmed,
        [string]$Serial,
        [string]$MacAddress,
        [string]$ResolvedAddress,
        [string]$ReachabilityStatus,
        [int[]]$OpenPorts,
        [string]$AdStatus,
        [string]$ExplicitTier
    )

    if ($Role -eq 'requested_population') { return 'population' }
    $explicit = ([string]$ExplicitType).Trim().ToLowerInvariant()
    $tier = ([string]$ExplicitTier).Trim().ToUpperInvariant()
    if ($IdentityConfirmed -or $explicit -match 'identity|wmi|cim|sccm|mdm|vendor' -or $tier -eq 'IDENTITY_CONFIRMED') { return 'identity' }
    if ($Serial -and $MacAddress -and $ResolvedAddress) { return 'device_location' }
    if ($explicit -match 'tracker|workbook|population|manifest' -or $tier -eq 'POPULATION_ONLY') { return 'population' }
    if ($AdStatus -match 'exact|registered' -or $explicit -match 'ad_exact|registered_ad' -or $tier -eq 'REGISTERED_AD_TARGET') { return 'ad_registered' }
    if ($AdStatus -match 'candidate|variant' -or $explicit -match 'ad_variant|candidate' -or $tier -eq 'AD_VARIANT_REVIEW') { return 'ad_candidate' }
    if ($explicit -match 'dns|subnet' -or $tier -eq 'DNS_OR_SUBNET_ONLY') { return 'dns_subnet' }
    if ($ReachabilityStatus -eq 'reachable') { return 'reachability' }
    if ($OpenPorts.Count -gt 0) { return 'packet_service' }
    if ($ReachabilityStatus -eq 'silent') { return 'negative_silent' }
    if ($explicit -match 'fixture|test' -or $tier -eq 'TEST_ONLY') { return 'test_fixture' }
    return ''
}

function Get-SasSurveyEvidenceTier {
    [CmdletBinding()]
    param([string]$EvidenceType, [object]$ExplicitTier)

    $explicit = ([string]$ExplicitTier).Trim().ToUpperInvariant()
    $allowed = @('IDENTITY_CONFIRMED', 'PROBABLE_DEVICE_LOCATION', 'POPULATION_ONLY', 'REGISTERED_AD_TARGET', 'AD_VARIANT_REVIEW', 'DNS_OR_SUBNET_ONLY', 'REACHABILITY_ONLY', 'PACKET_SERVICE_ONLY', 'NEGATIVE_OR_SILENT', 'TEST_ONLY')
    if ($allowed -contains $explicit) { return $explicit }
    switch ($EvidenceType) {
        'identity' { return 'IDENTITY_CONFIRMED' }
        'device_location' { return 'PROBABLE_DEVICE_LOCATION' }
        'population' { return 'POPULATION_ONLY' }
        'ad_registered' { return 'REGISTERED_AD_TARGET' }
        'ad_candidate' { return 'AD_VARIANT_REVIEW' }
        'dns_subnet' { return 'DNS_OR_SUBNET_ONLY' }
        'reachability' { return 'REACHABILITY_ONLY' }
        'packet_service' { return 'PACKET_SERVICE_ONLY' }
        'negative_silent' { return 'NEGATIVE_OR_SILENT' }
        'test_fixture' { return 'TEST_ONLY' }
    }
    return ''
}

function Get-SasSurveyReachabilityStatus {
    [CmdletBinding()]
    param([object]$Value, [int[]]$OpenPorts)

    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -match 'reachable|success|online|^up$') { return 'reachable' }
    if ($text -match 'noping|silent|unreachable|offline|failed|timeout|^down$') { return 'silent' }
    if ($OpenPorts.Count -gt 0) { return 'reachable' }
    return 'unknown'
}

function Get-SasSurveySourceValues {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Row)
    $values = [ordered]@{}
    foreach ($property in $Row.PSObject.Properties) { $values[$property.Name] = $property.Value }
    return $values
}

function Get-SasSurveyArtifactId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Role)

    $safeBase = ([System.IO.Path]::GetFileNameWithoutExtension($Path) -replace '[^A-Za-z0-9._-]', '-')
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($Path).ToLowerInvariant())
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant().Substring(0, 8)
    } finally { $sha.Dispose() }
    return "$Role-$safeBase-$hash"
}

function Test-SasSurveyDenominatorPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Package, [Parameter(Mandatory = $true)]$Schema)

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($field in @($Schema.required)) {
        if ($null -eq $Package.PSObject.Properties[[string]$field]) { $errors.Add("PACKAGE_FIELD_MISSING:$field") }
    }
    $rowRequired = @($Schema.'$defs'.row.required)
    $index = 0
    foreach ($row in @($Package.rows)) {
        $index++
        foreach ($field in $rowRequired) {
            if ($null -eq $row.PSObject.Properties[[string]$field]) { $errors.Add("ROW_${index}_FIELD_MISSING:$field") }
        }
        if (-not $row.normalized_serial -and -not $row.normalized_target -and @($row.candidate_targets).Count -eq 0) { $errors.Add("ROW_${index}_DENOMINATOR_KEY_MISSING") }
        if ($row.record_role -ne $Package.artifact_role) { $errors.Add("ROW_${index}_ROLE_MISMATCH") }
        if ($row.record_role -eq 'evidence_snapshot' -and -not $row.evidence_type) { $errors.Add("ROW_${index}_EVIDENCE_TYPE_MISSING") }
        if ($row.evidence_type -eq 'identity' -and (-not $row.normalized_serial -or -not $row.serial_identity_confirmed -or -not $row.observed_at)) { $errors.Add("ROW_${index}_IDENTITY_REQUIREMENTS_MISSING") }
        if ($row.evidence_type -in @('device_location', 'reachability', 'packet_service', 'negative_silent') -and -not $row.observed_at) { $errors.Add("ROW_${index}_TIMESTAMP_REQUIRED_FOR_FRESHNESS") }
    }
    if ([int]$Package.row_count -ne @($Package.rows).Count) { $errors.Add('PACKAGE_ROW_COUNT_MISMATCH') }
    return @($errors)
}

function Invoke-SasSurveyArtifactNormalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('requested_population', 'evidence_snapshot')][string]$Role,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [string]$RepoRoot,
        [string]$RegistryPath,
        [string]$SchemaPath,
        [datetimeoffset]$NormalizedAt = [datetimeoffset]::Now
    )

    if (-not $RepoRoot) { $RepoRoot = Get-SasSurveyArtifactRepoRoot }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Survey artifact not found: $Path" }
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $format = Get-SasSurveyArtifactFormat -Path $resolvedPath
    $registry = Get-SasSurveyArtifactRegistry -RepoRoot $RepoRoot -RegistryPath $RegistryPath
    $schema = Get-SasSurveyArtifactSchema -RepoRoot $RepoRoot -SchemaPath $SchemaPath
    if ($registry.denominator_contract_version -ne $schema.properties.contract_version.const) {
        throw "Adapter registry contract version '$($registry.denominator_contract_version)' does not match denominator schema '$($schema.properties.contract_version.const)'."
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $artifactId = Get-SasSurveyArtifactId -Path $resolvedPath -Role $Role
    $packagePath = Join-Path $OutputDirectory "$artifactId.normalized.json"
    $validationPath = Join-Path $OutputDirectory "$artifactId.validation.json"
    $rejectionPath = Join-Path $OutputDirectory "$artifactId.rejections.csv"

    $parsedJson = $null
    if ($format -eq 'json') { $parsedJson = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    if ($null -ne $parsedJson -and $null -ne $parsedJson.PSObject.Properties['contract_version'] -and $null -ne $parsedJson.PSObject.Properties['rows']) {
        if ($parsedJson.artifact_role -ne $Role) { throw "Canonical package role '$($parsedJson.artifact_role)' does not match requested role '$Role'." }
        $errors = @(Test-SasSurveyDenominatorPackage -Package $parsedJson -Schema $schema)
        $validation = [ordered]@{
            contract_version = '1.0.0'; status = if ($errors.Count -eq 0) { 'valid' } else { 'invalid' }; source_path = $resolvedPath
            artifact_id = $parsedJson.artifact_id; artifact_role = $Role; adapter_id = 'canonical-denominator-package/v1'; source_format = $format
            source_row_count = @($parsedJson.rows).Count; accepted_row_count = if ($errors.Count -eq 0) { @($parsedJson.rows).Count } else { 0 }
            rejected_row_count = if ($errors.Count -eq 0) { 0 } else { @($parsedJson.rows).Count }; errors = $errors
            network_activity_performed = $false; target_mutation_performed = $false
        }
        $validation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validationPath -Encoding UTF8
        if ($errors.Count -gt 0) { throw "Canonical denominator package failed validation. See: $validationPath" }
        $parsedJson | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
        return [pscustomobject]@{ Package = $parsedJson; PackagePath = $packagePath; ValidationPath = $validationPath; RejectionPath = ''; AdapterId = 'canonical-denominator-package/v1' }
    }

    $rows = @(Read-SasSurveyArtifactRows -Path $resolvedPath -Format $format)
    if ($rows.Count -eq 0) { throw "Survey artifact contained no rows: $resolvedPath" }
    $headers = @(Get-SasSurveyArtifactHeaders -Rows $rows)
    $adapter = Select-SasSurveyArtifactAdapter -Registry $registry -Role $Role -Format $format -Headers $headers
    $normalizedRows = New-Object System.Collections.Generic.List[object]
    $rejections = New-Object System.Collections.Generic.List[object]
    $rowNumber = 0

    foreach ($row in $rows) {
        $rowNumber++
        $serial = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'serial')).Trim()
        $target = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'target')).Trim()
        $candidates = @(ConvertTo-SasSurveyStringList -Value (Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'candidate_targets'))
        if ($target -and $candidates -notcontains $target) { $candidates = @($target) + $candidates }
        $candidates = @($candidates | Where-Object { $_ } | Sort-Object -Unique)
        $identityConfirmed = ConvertTo-SasSurveyBoolean -Value (Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'serial_identity_confirmed')
        $observed = ConvertTo-SasSurveyTimestamp -Value (Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'observed_at')
        $portValue = Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'port'
        $normalizedPort = $null
        $parsedPort = 0
        if (-not [string]::IsNullOrWhiteSpace([string]$portValue) -and [int]::TryParse(([string]$portValue), [ref]$parsedPort) -and $parsedPort -ge 1 -and $parsedPort -le 65535) { $normalizedPort = $parsedPort }
        $portStatus = Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'port_status'
        $openPorts = @(ConvertTo-SasSurveyPortList -OpenPorts (Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'open_ports') -Port $portValue -PortStatus $portStatus)
        $reachability = Get-SasSurveyReachabilityStatus -Value (Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'reachability_status') -OpenPorts $openPorts
        $resolvedAddress = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'resolved_address')).Trim()
        $adStatus = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'ad_candidate_status')).Trim()
        $macAddress = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'mac_address')).Trim()
        $explicitType = Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'evidence_type'
        $explicitTier = Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'evidence_strength_tier'
        $evidenceType = Get-SasSurveyEvidenceType -Role $Role -ExplicitType $explicitType -IdentityConfirmed $identityConfirmed -Serial $serial -MacAddress $macAddress -ResolvedAddress $resolvedAddress -ReachabilityStatus $reachability -OpenPorts $openPorts -AdStatus $adStatus -ExplicitTier ([string]$explicitTier)
        $tier = Get-SasSurveyEvidenceTier -EvidenceType $evidenceType -ExplicitTier $explicitTier

        $normalized = [pscustomobject][ordered]@{
            row_id = "${artifactId}:$rowNumber"; record_role = $Role; serial = $serial; normalized_serial = ConvertTo-SasSurveyNormalizedSerial -Value $serial
            target = $target; normalized_target = ConvertTo-SasSurveyNormalizedTarget -Value $target; candidate_targets = $candidates
            device_type = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'device_type')).Trim()
            site = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'site')).Trim()
            expected_prefix = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'expected_prefix')).Trim()
            observed_at = if ($observed) { $observed.ToString('o') } else { $null }; evidence_type = $evidenceType; evidence_strength_tier = $tier
            serial_identity_confirmed = [bool]$identityConfirmed; reachability_status = $reachability; open_ports = $openPorts; resolved_address = $resolvedAddress
            mac_address = $macAddress; port = $normalizedPort; port_status = ([string]$portStatus).Trim(); ad_candidate_status = $adStatus
            tracker_status = ([string](Get-SasSurveyMappedValue -Row $row -Adapter $adapter -CanonicalField 'tracker_status')).Trim()
            source_file = $resolvedPath; source_adapter = $adapter.id; source_values = Get-SasSurveySourceValues -Row $row
        }
        $rowPackage = [pscustomobject]@{
            contract_version = '1.0.0'; artifact_id = $artifactId; artifact_role = $Role; adapter_id = $adapter.id
            source_format = $format; source_path = $resolvedPath; normalized_at = $NormalizedAt.ToString('o'); row_count = 1; rows = @($normalized)
        }
        $rowErrors = @(Test-SasSurveyDenominatorPackage -Package $rowPackage -Schema $schema)
        if ($rowErrors.Count -gt 0) {
            $rejections.Add([pscustomobject]@{ RowNumber = $rowNumber; RowId = $normalized.row_id; Errors = ($rowErrors -join ';'); SourceFile = $resolvedPath; AdapterId = $adapter.id })
        } else { $normalizedRows.Add($normalized) }
    }

    $package = [pscustomobject][ordered]@{
        contract_version = '1.0.0'; artifact_id = $artifactId; artifact_role = $Role; adapter_id = $adapter.id; source_format = $format
        source_path = $resolvedPath; normalized_at = $NormalizedAt.ToString('o'); row_count = $normalizedRows.Count; rows = @($normalizedRows)
    }
    $packageErrors = if ($normalizedRows.Count -gt 0) { @(Test-SasSurveyDenominatorPackage -Package $package -Schema $schema) } else { @('PACKAGE_HAS_NO_VALID_ROWS') }
    if ($rejections.Count -gt 0) { $rejections | Export-Csv -LiteralPath $rejectionPath -NoTypeInformation -Encoding UTF8 }
    $allErrors = @($packageErrors)
    if ($rejections.Count -gt 0) { $allErrors += 'ARTIFACT_ROWS_REJECTED' }
    $validation = [ordered]@{
        contract_version = '1.0.0'; status = if ($allErrors.Count -eq 0) { 'valid' } else { 'invalid' }; source_path = $resolvedPath
        artifact_id = $artifactId; artifact_role = $Role; adapter_id = $adapter.id; source_format = $format; source_row_count = $rows.Count
        accepted_row_count = $normalizedRows.Count; rejected_row_count = $rejections.Count; denominator_schema = $registry.denominator_schema
        errors = $allErrors; rejection_path = if ($rejections.Count -gt 0) { $rejectionPath } else { '' }
        network_activity_performed = $false; target_mutation_performed = $false
    }
    $validation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validationPath -Encoding UTF8
    if ($allErrors.Count -gt 0) { throw "Survey artifact failed denominator normalization. See validation: $validationPath" }
    $package | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
    return [pscustomobject]@{ Package = $package; PackagePath = $packagePath; ValidationPath = $validationPath; RejectionPath = ''; AdapterId = $adapter.id }
}

Export-ModuleMember -Function Get-SasSurveyArtifactRepoRoot, Get-SasSurveyArtifactRegistry, Get-SasSurveyArtifactSchema, Get-SasSurveyArtifactFormat, ConvertTo-SasSurveyNormalizedSerial, ConvertTo-SasSurveyNormalizedTarget, ConvertTo-SasSurveyBoolean, ConvertTo-SasSurveyTimestamp, Invoke-SasSurveyArtifactNormalization, Test-SasSurveyDenominatorPackage
