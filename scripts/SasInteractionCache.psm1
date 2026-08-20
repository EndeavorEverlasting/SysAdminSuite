Set-StrictMode -Version Latest

$script:SchemaVersion = 'sas-interaction-cache/v1'
$script:DefaultTtlDays = 90
$script:DefaultMaxEntries = 200
$script:DefaultMaxEntriesPerKind = 75
$script:DefaultLockTimeoutMilliseconds = 1500
$script:MetricMaxBytes = 262144

function Get-SasInteractionCacheDefaultPath {
    [CmdletBinding()]
    param()

    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = [string]$env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw 'LOCALAPPDATA is unavailable; SysAdminSuite interaction history cannot resolve a per-user cache path.'
    }
    return (Join-Path $localAppData 'SysAdminSuite\Cache\interactions.v1.json')
}

function New-SasInteractionCacheDocument {
    [CmdletBinding()]
    param([datetime]$NowUtc = [datetime]::UtcNow)

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:SchemaVersion
        UpdatedUtc = $NowUtc.ToUniversalTime().ToString('o')
        Entries = @()
    }
}

function Assert-SasInteractionCacheIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][ValidateSet('Host','Printer','Server')][string]$Kind,
        [Parameter(Mandatory)][string]$Value
    )

    $cleanScope = $Scope.Trim().ToLowerInvariant()
    if ($cleanScope -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$') {
        throw "Cache scope '$Scope' is invalid. Use a short organization/profile namespace containing letters, digits, dot, underscore, or hyphen."
    }

    $cleanValue = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanValue)) { throw 'Cache value cannot be blank.' }
    if ($cleanValue.Length -gt 512) { throw 'Cache value exceeds the 512-character safety limit.' }
    if ($cleanValue -match '[\x00-\x1F\x7F]') { throw 'Cache value contains control characters and was rejected.' }

    return [pscustomobject]@{
        Scope = $cleanScope
        Kind = $Kind
        DisplayValue = $cleanValue
        NormalizedValue = $cleanValue.ToLowerInvariant()
    }
}

function Write-SasInteractionCacheMetric {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Kind,
        [int]$Count = 0,
        [int]$LatencyMs = 0
    )

    try {
        $directory = Split-Path -Parent $CachePath
        if ([string]::IsNullOrWhiteSpace($directory)) { return }
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        $metricsPath = Join-Path $directory 'cache-metrics.v1.jsonl'
        if ((Test-Path -LiteralPath $metricsPath -PathType Leaf) -and (Get-Item -LiteralPath $metricsPath).Length -ge $script:MetricMaxBytes) {
            $archive = Join-Path $directory 'cache-metrics.v1.previous.jsonl'
            Move-Item -LiteralPath $metricsPath -Destination $archive -Force -ErrorAction SilentlyContinue
        }
        $record = [ordered]@{
            SchemaVersion = 'sas-interaction-cache-metric/v1'
            TimestampUtc = [datetime]::UtcNow.ToString('o')
            Event = $Event
            Scope = $Scope
            Kind = $Kind
            Count = $Count
            LatencyMs = $LatencyMs
        }
        Add-Content -LiteralPath $metricsPath -Value ($record | ConvertTo-Json -Compress) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Observability is best-effort and must never break the owning field workflow.
    }
}

function Move-SasMalformedInteractionCacheAside {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CachePath)

    try {
        if (-not (Test-Path -LiteralPath $CachePath -PathType Leaf)) { return }
        $directory = Split-Path -Parent $CachePath
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($CachePath)
        $extension = [System.IO.Path]::GetExtension($CachePath)
        $stamp = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
        $quarantine = Join-Path $directory ("{0}.corrupt-{1}{2}" -f $leaf, $stamp, $extension)
        Move-Item -LiteralPath $CachePath -Destination $quarantine -Force -ErrorAction Stop
    }
    catch {
        # A malformed cache must fail open. If quarantine itself fails, ignore the cache.
    }
}

function Read-SasInteractionCacheDocument {
    [CmdletBinding()]
    param(
        [string]$CachePath = (Get-SasInteractionCacheDefaultPath),
        [datetime]$NowUtc = [datetime]::UtcNow,
        [ValidateRange(1,3650)][int]$TtlDays = $script:DefaultTtlDays,
        [switch]$QuarantineMalformed
    )

    if (-not (Test-Path -LiteralPath $CachePath -PathType Leaf)) {
        return [pscustomobject]@{ Document = (New-SasInteractionCacheDocument -NowUtc $NowUtc); ExpiredCount = 0; Malformed = $false }
    }

    try {
        $document = Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([string]$document.SchemaVersion -ne $script:SchemaVersion) {
            throw "Unsupported interaction-cache schema '$($document.SchemaVersion)'."
        }
        $entries = @($document.Entries)
        $cutoff = $NowUtc.ToUniversalTime().AddDays(-1 * $TtlDays)
        $fresh = New-Object System.Collections.Generic.List[object]
        $expired = 0
        foreach ($entry in $entries) {
            $lastSuccess = [datetime]::MinValue
            if (-not [datetime]::TryParse([string]$entry.LastSuccessUtc, [ref]$lastSuccess)) {
                $expired++
                continue
            }
            if ($lastSuccess.ToUniversalTime() -lt $cutoff) {
                $expired++
                continue
            }
            $fresh.Add($entry)
        }
        $document.Entries = $fresh.ToArray()
        return [pscustomobject]@{ Document = $document; ExpiredCount = $expired; Malformed = $false }
    }
    catch {
        if ($QuarantineMalformed) { Move-SasMalformedInteractionCacheAside -CachePath $CachePath }
        return [pscustomobject]@{ Document = (New-SasInteractionCacheDocument -NowUtc $NowUtc); ExpiredCount = 0; Malformed = $true }
    }
}

function Enter-SasInteractionCacheWriteLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [ValidateRange(1,30000)][int]$LockTimeoutMilliseconds = $script:DefaultLockTimeoutMilliseconds
    )

    $directory = Split-Path -Parent $CachePath
    if ([string]::IsNullOrWhiteSpace($directory)) { throw "Cache path must include a directory: $CachePath" }
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $lockPath = "$CachePath.lock"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.ElapsedMilliseconds -lt $LockTimeoutMilliseconds) {
        try {
            return New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 25
        }
    }
    return $null
}

function Write-SasInteractionCacheDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$CachePath
    )

    $directory = Split-Path -Parent $CachePath
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $temporary = Join-Path $directory (([System.IO.Path]::GetFileName($CachePath)) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $Document | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
        if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
            [System.IO.File]::Replace($temporary, $CachePath, $null, $true)
        }
        else {
            Move-Item -LiteralPath $temporary -Destination $CachePath -Force -ErrorAction Stop
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Get-SasInteractionCacheEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][ValidateSet('Host','Printer','Server')][string]$Kind,
        [ValidateRange(1,50)][int]$Top = 10,
        [string]$CachePath = (Get-SasInteractionCacheDefaultPath),
        [datetime]$NowUtc = [datetime]::UtcNow,
        [ValidateRange(1,3650)][int]$TtlDays = $script:DefaultTtlDays
    )

    $identity = Assert-SasInteractionCacheIdentity -Scope $Scope -Kind $Kind -Value '_probe_'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $read = Read-SasInteractionCacheDocument -CachePath $CachePath -NowUtc $NowUtc -TtlDays $TtlDays -QuarantineMalformed
    $matches = @(
        @($read.Document.Entries) |
            Where-Object { ([string]$_.Scope).Equals($identity.Scope, [System.StringComparison]::OrdinalIgnoreCase) -and ([string]$_.Kind).Equals($Kind, [System.StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object @{ Expression = { [datetime]$_.LastSuccessUtc }; Descending = $true }, @{ Expression = { [int]$_.UseCount }; Descending = $true } |
            Select-Object -First $Top
    )
    $event = if ($matches.Count -gt 0) { 'hit' } else { 'miss' }
    if ($read.Malformed) { $event = 'malformed_fail_open' }
    elseif ($read.ExpiredCount -gt 0 -and $matches.Count -eq 0) { $event = 'stale_miss' }
    Write-SasInteractionCacheMetric -CachePath $CachePath -Event $event -Scope $identity.Scope -Kind $Kind -Count $matches.Count -LatencyMs ([int]$stopwatch.ElapsedMilliseconds)
    return $matches
}

function Add-SasInteractionCacheEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][ValidateSet('Host','Printer','Server')][string]$Kind,
        [Parameter(Mandatory)][string]$Value,
        [string]$CachePath = (Get-SasInteractionCacheDefaultPath),
        [datetime]$NowUtc = [datetime]::UtcNow,
        [ValidateRange(1,3650)][int]$TtlDays = $script:DefaultTtlDays,
        [ValidateRange(10,2000)][int]$MaxEntries = $script:DefaultMaxEntries,
        [ValidateRange(5,1000)][int]$MaxEntriesPerKind = $script:DefaultMaxEntriesPerKind,
        [ValidateRange(1,30000)][int]$LockTimeoutMilliseconds = $script:DefaultLockTimeoutMilliseconds
    )

    $identity = Assert-SasInteractionCacheIdentity -Scope $Scope -Kind $Kind -Value $Value
    $lock = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $lock = Enter-SasInteractionCacheWriteLock -CachePath $CachePath -LockTimeoutMilliseconds $LockTimeoutMilliseconds
        if ($null -eq $lock) {
            Write-SasInteractionCacheMetric -CachePath $CachePath -Event 'lock_timeout_fail_open' -Scope $identity.Scope -Kind $Kind -LatencyMs ([int]$stopwatch.ElapsedMilliseconds)
            return $false
        }

        $read = Read-SasInteractionCacheDocument -CachePath $CachePath -NowUtc $NowUtc -TtlDays $TtlDays -QuarantineMalformed
        $entries = New-Object System.Collections.Generic.List[object]
        $existing = $null
        foreach ($entry in @($read.Document.Entries)) {
            $same = ([string]$entry.Scope).Equals($identity.Scope, [System.StringComparison]::OrdinalIgnoreCase) -and
                ([string]$entry.Kind).Equals($Kind, [System.StringComparison]::OrdinalIgnoreCase) -and
                ([string]$entry.NormalizedValue).Equals($identity.NormalizedValue, [System.StringComparison]::OrdinalIgnoreCase)
            if ($same) { $existing = $entry; continue }
            $entries.Add($entry)
        }

        $nowText = $NowUtc.ToUniversalTime().ToString('o')
        $useCount = if ($null -eq $existing) { 1 } else { [int]$existing.UseCount + 1 }
        $firstSuccess = if ($null -eq $existing -or [string]::IsNullOrWhiteSpace([string]$existing.FirstSuccessUtc)) { $nowText } else { [string]$existing.FirstSuccessUtc }
        $entries.Add([pscustomobject][ordered]@{
            Scope = $identity.Scope
            Kind = $Kind
            NormalizedValue = $identity.NormalizedValue
            DisplayValue = $identity.DisplayValue
            FirstSuccessUtc = $firstSuccess
            LastSuccessUtc = $nowText
            UseCount = $useCount
        })

        $bounded = New-Object System.Collections.Generic.List[object]
        foreach ($kindName in @('Host','Printer','Server')) {
            @($entries | Where-Object { ([string]$_.Kind).Equals($kindName, [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object @{ Expression = { [datetime]$_.LastSuccessUtc }; Descending = $true } | Select-Object -First $MaxEntriesPerKind) |
                ForEach-Object { $bounded.Add($_) }
        }
        $finalEntries = @($bounded | Sort-Object @{ Expression = { [datetime]$_.LastSuccessUtc }; Descending = $true } | Select-Object -First $MaxEntries)
        $document = [pscustomobject][ordered]@{
            SchemaVersion = $script:SchemaVersion
            UpdatedUtc = $nowText
            Entries = $finalEntries
        }
        Write-SasInteractionCacheDocument -Document $document -CachePath $CachePath
        Write-SasInteractionCacheMetric -CachePath $CachePath -Event 'write' -Scope $identity.Scope -Kind $Kind -Count $finalEntries.Count -LatencyMs ([int]$stopwatch.ElapsedMilliseconds)
        return $true
    }
    catch {
        Write-SasInteractionCacheMetric -CachePath $CachePath -Event 'write_fail_open' -Scope $identity.Scope -Kind $Kind -LatencyMs ([int]$stopwatch.ElapsedMilliseconds)
        return $false
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

function Get-SasInteractionCacheSnapshot {
    [CmdletBinding()]
    param(
        [string]$CachePath = (Get-SasInteractionCacheDefaultPath),
        [datetime]$NowUtc = [datetime]::UtcNow,
        [ValidateRange(1,3650)][int]$TtlDays = $script:DefaultTtlDays
    )

    $read = Read-SasInteractionCacheDocument -CachePath $CachePath -NowUtc $NowUtc -TtlDays $TtlDays -QuarantineMalformed
    $entries = @($read.Document.Entries)
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:SchemaVersion
        CachePath = $CachePath
        ItemCount = $entries.Count
        ExpiredPrunedOnRead = $read.ExpiredCount
        MalformedFailOpen = [bool]$read.Malformed
        Hosts = @($entries | Where-Object Kind -eq 'Host').Count
        Printers = @($entries | Where-Object Kind -eq 'Printer').Count
        Servers = @($entries | Where-Object Kind -eq 'Server').Count
    }
}

Export-ModuleMember -Function @(
    'Get-SasInteractionCacheDefaultPath',
    'Get-SasInteractionCacheEntries',
    'Add-SasInteractionCacheEntry',
    'Get-SasInteractionCacheSnapshot'
)
