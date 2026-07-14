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
            (Test-Path -LiteralPath (Join-Path $cursor 'targets/README.md'))) { return $cursor }
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
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { throw "Missing network survey artifact adapter registry: $RegistryPath" }
    Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SasSurveyArtifactSchema {
    [CmdletBinding()]
    param([string]$RepoRoot, [string]$SchemaPath)
    if (-not $RepoRoot) { $RepoRoot = Get-SasSurveyArtifactRepoRoot }
    if (-not $SchemaPath) { $SchemaPath = Join-Path $RepoRoot $script:DefaultSchemaRelative }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "Missing network survey denominator schema: $SchemaPath" }
    Get-Content -LiteralPath $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SasSurveyArtifactFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
    if ($extension -notin @('csv', 'txt', 'json', 'jsonl')) {
        throw "Unsupported survey artifact format '$extension'. Supported formats: csv, txt, json, jsonl."
    }
    $extension
}

function ConvertTo-SasSurveyNormalizedSerial {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    (([string]$Value).Trim().ToUpperInvariant() -replace '[^A-Z0-9]', '')
}

function ConvertTo-SasSurveyNormalizedTarget {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    ([string]$Value).Trim().TrimEnd('.').ToLowerInvariant()
}

function ConvertTo-SasSurveyBoolean {
    [CmdletBinding()]
    param([object]$Value)
    if ($Value -is [bool]) { return [bool]$Value }
    if ($null -eq $Value) { return $false }
    ([string]$Value).Trim() -match '^(1|true|yes|y|confirmed)$'
}

function ConvertTo-SasSurveyTimestamp {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse(([string]$Value).Trim(), [ref]$parsed)) { return $parsed }
    $null
}

function ConvertTo-SasSurveyStringList {
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    $raw = if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { @($Value) } else { @(([string]$Value) -split '[,;|]') }
    @($raw | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
}

function ConvertTo-SasSurveyPortList {
    [CmdletBinding()]
    param([object]$OpenPorts, [object]$Port, [object]$PortStatus)
    $ports = @()
    foreach ($value in @(ConvertTo-SasSurveyStringList -Value $OpenPorts)) {
        $parsed = 0
        if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 65535) { $ports += $parsed }
    }
    if (([string]$PortStatus).Trim().ToLowerInvariant() -eq 'open') {
        $parsed = 0
        if ([int]::TryParse(([string]$Port), [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 65535) { $ports += $parsed }
    }
    @($ports | Sort-Object -Unique)
}

function Get-SasSurveyMappedValue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Row, [Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string]$CanonicalField)
    $mapping = $Adapter.mappings.PSObject.Properties | Where-Object Name -eq $CanonicalField | Select-Object -First 1
    if ($null -eq $mapping) { return $null }
    foreach ($alias in @($mapping.Value)) {
        $property = $Row.PSObject.Properties | Where-Object { $_.Name -ieq [string]$alias } | Select-Object -First 1
        if ($null -ne $property -and $null -ne $property.Value) {
            if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace($property.Value)) { continue }
            return $property.Value
        }
    }
    $null
}

function Read-SasSurveyArtifactRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Format)
    switch ($Format) {
        'csv' { return @(Import-Csv -LiteralPath $Path) }
        'txt' { return @(Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object { $v = ([string]$_).Trim(); if ($v -and -not $v.StartsWith('#')) { [pscustomobject]@{ Target = $v } } }) }
        'json' { $parsed = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json; if ($parsed.PSObject.Properties.Match('rows').Count) { return @($parsed.rows) }; return @($parsed) }
        'jsonl' { return @(Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object { $line = ([string]$_).Trim(); if ($line) { $line | ConvertFrom-Json } }) }
    }
}

function Get-SasSurveyArtifactHeaders {
    [CmdletBinding()]
    param([object[]]$Rows)
    @($Rows | Select-Object -First 20 | ForEach-Object { $_.PSObject.Properties.Name } | Sort-Object -Unique)
}

function Test-SasSurveyAdapterDetection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string[]]$Headers)
    foreach ($group in @($Adapter.detection.required_any)) {
        if (@($group | Where-Object { $Headers -contains [string]$_ }).Count -eq 0) { return $false }
    }
    $true
}

function Select-SasSurveyArtifactAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Registry, [Parameter(Mandatory = $true)][ValidateSet('requested_population', 'evidence_snapshot')][string]$Role, [Parameter(Mandatory = $true)][string]$Format, [Parameter(Mandatory = $true)][string[]]$Headers)
    $matches = @($Registry.adapters | Where-Object { $_.role -eq $Role -and @($_.formats) -contains $Format -and (Test-SasSurveyAdapterDetection -Adapter $_ -Headers $Headers) } | Sort-Object { [int]$_.priority } -Descending)
    if ($matches.Count -eq 0) { throw "No registered network survey adapter accepted role '$Role', format '$Format', and headers: $($Headers -join ', ')." }
    $topPriority = [int]$matches[0].priority
    $top = @($matches | Where-Object { [int]$_.priority -eq $topPriority })
    if ($top.Count -ne 1) { throw "Ambiguous network survey adapters at priority ${topPriority}: $(@($top.id) -join ', ')." }
    $top[0]
}

function Get-SasSurveyReachabilityStatus {
    [CmdletBinding()]
    param([object]$Value, [int[]]$OpenPorts)
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -match 'reachable|success|online|^up$') { return 'reachable' }
    if ($text -match 'noping|silent|unreachable|offline|failed|timeout|^down$') { return 'silent' }
    if (@($OpenPorts).Count -gt 0) { return 'reachable' }
    'unknown'
}

function Get-SasSurveyEvidenceType {
    [CmdletBinding()]
    param([string]$Role, [object]$ExplicitType, [bool]$IdentityConfirmed, [string]$Serial, [string]$MacAddress, [string]$ResolvedAddress, [string]$ReachabilityStatus, [int[]]$OpenPorts, [string]$AdStatus, [string]$ExplicitTier)
    if ($Role -eq 'requested_population') { return 'population' }
    $explicit = ([string]$ExplicitType).Trim().ToLowerInvariant(); $tier = ([string]$ExplicitTier).Trim().ToUpperInvariant()
    if ($IdentityConfirmed -or $explicit -match 'identity|wmi|cim|sccm|mdm|vendor' -or $tier -eq 'IDENTITY_CONFIRMED') { return 'identity' }
    if ($Serial -and $MacAddress -and $ResolvedAddress) { return 'device_location' }
    if ($explicit -match 'tracker|workbook|population|manifest' -or $tier -eq 'POPULATION_ONLY') { return 'population' }
    if ($AdStatus -match 'exact|registered' -or $explicit -match 'ad_exact|registered_ad' -or $tier -eq 'REGISTERED_AD_TARGET') { return 'ad_registered' }
    if ($AdStatus -match 'candidate|variant' -or $explicit -match 'ad_variant|candidate' -or $tier -eq 'AD_VARIANT_REVIEW') { return 'ad_candidate' }
    if ($explicit -match 'dns|subnet' -or $tier -eq 'DNS_OR_SUBNET_ONLY') { return 'dns_subnet' }
    if ($ReachabilityStatus -eq 'reachable') { return 'reachability' }
    if (@($OpenPorts).Count -gt 0) { return 'packet_service' }
    if ($ReachabilityStatus -eq 'silent') { return 'negative_silent' }
    if ($explicit -match 'fixture|test' -or $tier -eq 'TEST_ONLY') { return 'test_fixture' }
    ''
}

function Get-SasSurveyEvidenceTier {
    [CmdletBinding()]
    param([string]$EvidenceType, [object]$ExplicitTier)
    $explicit = ([string]$ExplicitTier).Trim().ToUpperInvariant()
    $allowed = @('IDENTITY_CONFIRMED','PROBABLE_DEVICE_LOCATION','POPULATION_ONLY','REGISTERED_AD_TARGET','AD_VARIANT_REVIEW','DNS_OR_SUBNET_ONLY','REACHABILITY_ONLY','PACKET_SERVICE_ONLY','NEGATIVE_OR_SILENT','TEST_ONLY')
    if ($allowed -contains $explicit) { return $explicit }
    switch ($EvidenceType) {
        identity { 'IDENTITY_CONFIRMED' }; device_location { 'PROBABLE_DEVICE_LOCATION' }; population { 'POPULATION_ONLY' }; ad_registered { 'REGISTERED_AD_TARGET' }; ad_candidate { 'AD_VARIANT_REVIEW' }; dns_subnet { 'DNS_OR_SUBNET_ONLY' }; reachability { 'REACHABILITY_ONLY' }; packet_service { 'PACKET_SERVICE_ONLY' }; negative_silent { 'NEGATIVE_OR_SILENT' }; test_fixture { 'TEST_ONLY' }; default { '' }
    }
}

function Get-SasSurveySourceValues {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Row)
    $values = [ordered]@{}; foreach ($property in $Row.PSObject.Properties) { $values[$property.Name] = $property.Value }; $values
}

function Get-SasSurveyArtifactId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Role)
    $safeBase = [System.IO.Path]::GetFileNameWithoutExtension($Path) -replace '[^A-Za-z0-9._-]', '-'
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToLowerInvariant()); $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant().Substring(0,8) } finally { $sha.Dispose() }
    "$Role-$safeBase-$hash"
}

function Test-SasSurveyDenominatorPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Package, [Parameter(Mandatory = $true)]$Schema)
    $errors = @()
    foreach ($field in @($Schema.required)) { if (-not $Package.PSObject.Properties.Match([string]$field).Count) { $errors += "PACKAGE_FIELD_MISSING:$field" } }
    $index = 0
    foreach ($row in @($Package.rows)) {
        $index++
        foreach ($field in @($Schema.'$defs'.row.required)) { if (-not $row.PSObject.Properties.Match([string]$field).Count) { $errors += "ROW_${index}_FIELD_MISSING:$field" } }
        if (-not $row.normalized_serial -and -not $row.normalized_target -and @($row.candidate_targets).Count -eq 0) { $errors += "ROW_${index}_DENOMINATOR_KEY_MISSING" }
        if ($row.record_role -ne $Package.artifact_role) { $errors += "ROW_${index}_ROLE_MISMATCH" }
        if ($row.record_role -eq 'evidence_snapshot' -and -not $row.evidence_type) { $errors += "ROW_${index}_EVIDENCE_TYPE_MISSING" }
        if ($row.evidence_type -eq 'identity' -and (-not $row.normalized_serial -or -not $row.serial_identity_confirmed -or -not $row.observed_at)) { $errors += "ROW_${index}_IDENTITY_REQUIREMENTS_MISSING" }
        if ($row.evidence_type -in @('device_location','reachability','packet_service','negative_silent') -and -not $row.observed_at) { $errors += "ROW_${index}_TIMESTAMP_REQUIRED_FOR_FRESHNESS" }
    }
    if ([int]$Package.row_count -ne @($Package.rows).Count) { $errors += 'PACKAGE_ROW_COUNT_MISMATCH' }
    @($errors)
}

function Invoke-SasSurveyArtifactNormalization {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][ValidateSet('requested_population','evidence_snapshot')][string]$Role, [Parameter(Mandatory = $true)][string]$OutputDirectory, [string]$RepoRoot, [string]$RegistryPath, [string]$SchemaPath, [datetimeoffset]$NormalizedAt = [datetimeoffset]::Now)
    if (-not $RepoRoot) { $RepoRoot = Get-SasSurveyArtifactRepoRoot }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Survey artifact not found: $Path" }
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path; $format = Get-SasSurveyArtifactFormat $resolvedPath
    $registry = Get-SasSurveyArtifactRegistry -RepoRoot $RepoRoot -RegistryPath $RegistryPath; $schema = Get-SasSurveyArtifactSchema -RepoRoot $RepoRoot -SchemaPath $SchemaPath
    if ($registry.denominator_contract_version -ne $schema.properties.contract_version.const) { throw 'Adapter registry and denominator schema contract versions differ.' }
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $artifactId = Get-SasSurveyArtifactId -Path $resolvedPath -Role $Role
    $packagePath = Join-Path $OutputDirectory "$artifactId.normalized.json"; $validationPath = Join-Path $OutputDirectory "$artifactId.validation.json"; $rejectionPath = Join-Path $OutputDirectory "$artifactId.rejections.csv"

    $parsedJson = if ($format -eq 'json') { Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    if ($parsedJson -and $parsedJson.PSObject.Properties.Match('contract_version').Count -and $parsedJson.PSObject.Properties.Match('rows').Count) {
        if ($parsedJson.artifact_role -ne $Role) { throw "Canonical package role '$($parsedJson.artifact_role)' does not match '$Role'." }
        $errors = @(Test-SasSurveyDenominatorPackage $parsedJson $schema)
        $validation = [ordered]@{ contract_version='1.0.0'; status=if($errors.Count){'invalid'}else{'valid'}; source_path=$resolvedPath; artifact_id=$parsedJson.artifact_id; artifact_role=$Role; adapter_id='canonical-denominator-package/v1'; source_format=$format; source_row_count=@($parsedJson.rows).Count; accepted_row_count=if($errors.Count){0}else{@($parsedJson.rows).Count}; rejected_row_count=if($errors.Count){@($parsedJson.rows).Count}else{0}; errors=$errors; network_activity_performed=$false; target_mutation_performed=$false }
        $validation | ConvertTo-Json -Depth 8 | Set-Content $validationPath -Encoding UTF8
        if ($errors.Count) { throw "Canonical denominator package failed validation. See: $validationPath" }
        $parsedJson | ConvertTo-Json -Depth 12 | Set-Content $packagePath -Encoding UTF8
        return [pscustomobject]@{ Package=$parsedJson; PackagePath=$packagePath; ValidationPath=$validationPath; RejectionPath=''; AdapterId='canonical-denominator-package/v1' }
    }

    $rows = @(Read-SasSurveyArtifactRows -Path $resolvedPath -Format $format); if (-not $rows.Count) { throw "Survey artifact contained no rows: $resolvedPath" }
    $adapter = Select-SasSurveyArtifactAdapter -Registry $registry -Role $Role -Format $format -Headers @(Get-SasSurveyArtifactHeaders $rows)
    $normalizedRows = @(); $rejections = @(); $rowNumber = 0
    foreach ($row in $rows) {
        $rowNumber++
        $serial = ([string](Get-SasSurveyMappedValue $row $adapter serial)).Trim(); $target = ([string](Get-SasSurveyMappedValue $row $adapter target)).Trim()
        $candidates = @(ConvertTo-SasSurveyStringList (Get-SasSurveyMappedValue $row $adapter candidate_targets)); if ($target) { $candidates = @($target) + $candidates | Sort-Object -Unique }
        $identity = ConvertTo-SasSurveyBoolean (Get-SasSurveyMappedValue $row $adapter serial_identity_confirmed); $observed = ConvertTo-SasSurveyTimestamp (Get-SasSurveyMappedValue $row $adapter observed_at)
        $portValue = Get-SasSurveyMappedValue $row $adapter port; $portStatus = Get-SasSurveyMappedValue $row $adapter port_status
        $normalizedPort = $null; $parsedPort = 0; if ([int]::TryParse(([string]$portValue),[ref]$parsedPort) -and $parsedPort -ge 1 -and $parsedPort -le 65535) { $normalizedPort = $parsedPort }
        $openPorts = @(ConvertTo-SasSurveyPortList (Get-SasSurveyMappedValue $row $adapter open_ports) $portValue $portStatus)
        $reachability = Get-SasSurveyReachabilityStatus (Get-SasSurveyMappedValue $row $adapter reachability_status) $openPorts
        $resolvedAddress = ([string](Get-SasSurveyMappedValue $row $adapter resolved_address)).Trim(); $adStatus = ([string](Get-SasSurveyMappedValue $row $adapter ad_candidate_status)).Trim(); $mac = ([string](Get-SasSurveyMappedValue $row $adapter mac_address)).Trim()
        $explicitType = Get-SasSurveyMappedValue $row $adapter evidence_type; $explicitTier = Get-SasSurveyMappedValue $row $adapter evidence_strength_tier
        $evidenceType = Get-SasSurveyEvidenceType $Role $explicitType $identity $serial $mac $resolvedAddress $reachability $openPorts $adStatus ([string]$explicitTier); $tier = Get-SasSurveyEvidenceTier $evidenceType $explicitTier
        $normalized = [pscustomobject][ordered]@{ row_id="${artifactId}:$rowNumber"; record_role=$Role; serial=$serial; normalized_serial=ConvertTo-SasSurveyNormalizedSerial $serial; target=$target; normalized_target=ConvertTo-SasSurveyNormalizedTarget $target; candidate_targets=@($candidates); device_type=([string](Get-SasSurveyMappedValue $row $adapter device_type)).Trim(); site=([string](Get-SasSurveyMappedValue $row $adapter site)).Trim(); expected_prefix=([string](Get-SasSurveyMappedValue $row $adapter expected_prefix)).Trim(); observed_at=if($observed){$observed.ToString('o')}else{$null}; evidence_type=$evidenceType; evidence_strength_tier=$tier; serial_identity_confirmed=[bool]$identity; reachability_status=$reachability; open_ports=@($openPorts); resolved_address=$resolvedAddress; mac_address=$mac; port=$normalizedPort; port_status=([string]$portStatus).Trim(); ad_candidate_status=$adStatus; tracker_status=([string](Get-SasSurveyMappedValue $row $adapter tracker_status)).Trim(); source_file=$resolvedPath; source_adapter=$adapter.id; source_values=Get-SasSurveySourceValues $row }
        $rowPackage = [pscustomobject]@{ contract_version='1.0.0'; artifact_id=$artifactId; artifact_role=$Role; adapter_id=$adapter.id; source_format=$format; source_path=$resolvedPath; normalized_at=$NormalizedAt.ToString('o'); row_count=1; rows=@($normalized) }
        $rowErrors = @(Test-SasSurveyDenominatorPackage $rowPackage $schema)
        if ($rowErrors.Count) { $rejections += [pscustomobject]@{ RowNumber=$rowNumber; RowId=$normalized.row_id; Errors=$rowErrors -join ';'; SourceFile=$resolvedPath; AdapterId=$adapter.id } } else { $normalizedRows += $normalized }
    }
    $package = [pscustomobject][ordered]@{ contract_version='1.0.0'; artifact_id=$artifactId; artifact_role=$Role; adapter_id=$adapter.id; source_format=$format; source_path=$resolvedPath; normalized_at=$NormalizedAt.ToString('o'); row_count=@($normalizedRows).Count; rows=@($normalizedRows) }
    $packageErrors = if ($normalizedRows.Count) { @(Test-SasSurveyDenominatorPackage $package $schema) } else { @('PACKAGE_HAS_NO_VALID_ROWS') }
    if ($rejections.Count) { $rejections | Export-Csv $rejectionPath -NoTypeInformation -Encoding UTF8 }
    $allErrors = @($packageErrors); if ($rejections.Count) { $allErrors += 'ARTIFACT_ROWS_REJECTED' }
    $validation = [ordered]@{ contract_version='1.0.0'; status=if($allErrors.Count){'invalid'}else{'valid'}; source_path=$resolvedPath; artifact_id=$artifactId; artifact_role=$Role; adapter_id=$adapter.id; source_format=$format; source_row_count=$rows.Count; accepted_row_count=$normalizedRows.Count; rejected_row_count=$rejections.Count; denominator_schema=$registry.denominator_schema; errors=$allErrors; rejection_path=if($rejections.Count){$rejectionPath}else{''}; network_activity_performed=$false; target_mutation_performed=$false }
    $validation | ConvertTo-Json -Depth 8 | Set-Content $validationPath -Encoding UTF8
    if ($allErrors.Count) { throw "Survey artifact failed denominator normalization. See validation: $validationPath" }
    $package | ConvertTo-Json -Depth 12 | Set-Content $packagePath -Encoding UTF8
    [pscustomobject]@{ Package=$package; PackagePath=$packagePath; ValidationPath=$validationPath; RejectionPath=''; AdapterId=$adapter.id }
}

Export-ModuleMember -Function Get-SasSurveyArtifactRepoRoot, Get-SasSurveyArtifactRegistry, Get-SasSurveyArtifactSchema, Get-SasSurveyArtifactFormat, ConvertTo-SasSurveyNormalizedSerial, ConvertTo-SasSurveyNormalizedTarget, ConvertTo-SasSurveyBoolean, ConvertTo-SasSurveyTimestamp, Invoke-SasSurveyArtifactNormalization, Test-SasSurveyDenominatorPackage
