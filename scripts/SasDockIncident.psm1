function Resolve-SasDockIncidentWindow {
    param([string]$Start, [string]$End, [DateTimeOffset]$Now)

    if (-not $Start -and -not $End) {
        return @{ Start = $Now.AddMinutes(-10).UtcDateTime; End = $Now.UtcDateTime }
    }
    if (-not $Start -or -not $End) { throw 'Specify both Start and End, or omit both for the last 10 minutes.' }
    $parsed = foreach ($value in @($Start, $End)) {
        if ($value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
            throw 'Use ISO 8601 timestamps with an explicit offset or Z.'
        }
        [DateTimeOffset]::Parse($value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
    }
    if ($parsed[0] -ge $parsed[1] -or ($parsed[1] - $parsed[0]).TotalHours -gt 2 -or $parsed[1] -gt $Now.UtcDateTime) {
        throw 'Use a completed, increasing event window of at most two hours.'
    }
    return @{ Start = $parsed[0]; End = $parsed[1] }
}

function Select-SasDockIncidentEvents {
    param([object[]]$Records, [hashtable]$Window, [string]$ProviderPattern)

    foreach ($record in $Records) {
        if ($null -eq $record.TimeCreated) { continue }
        $utc = $record.TimeCreated.ToUniversalTime()
        if ($utc -lt $Window.Start -or $utc -ge $Window.End) { continue }
        if ($ProviderPattern -and $record.ProviderName -notmatch $ProviderPattern) { continue }
        [pscustomobject]@{
            TimeUtc = $utc.ToString('o')
            Channel = $record.LogName
            Provider = $record.ProviderName
            EventId = $record.Id
            RecordId = $record.RecordId
            Message = try { $record.Message } catch { $null }
        }
    }
}

function Get-SasDockEventEvidence {
    param([string]$Channel, [hashtable]$Window, [string]$ProviderPattern)

    $source = [ordered]@{
        Channel = $Channel; Status = 'READ'; Detail = $null; Events = @()
        Enabled = $null; RetainedRecordCount = $null; OldestRetainedUtc = $null
    }
    $records = @()
    $oldest = $null
    try {
        $log = Get-WinEvent -ListLog $Channel -ErrorAction Stop
        $source.Enabled = $log.IsEnabled
        $source.RetainedRecordCount = $log.RecordCount
        if (-not $log.IsEnabled) {
            $source.Status = 'DISABLED'
            return [pscustomobject]$source
        }
        if ($log.RecordCount -gt 0) {
            $oldest = Get-WinEvent -LogName $Channel -Oldest -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($oldest -and $oldest.TimeCreated) {
                $source.OldestRetainedUtc = $oldest.TimeCreated.ToUniversalTime().ToString('o')
            }
        }
        # Explicit UTC strings survive Get-WinEvent's local-culture DateTime parse.
        # Widen the native end by one millisecond and enforce exact bounds below.
        $filter = @{
            LogName = $Channel
            StartTime = $Window.Start.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
            EndTime = $Window.End.AddMilliseconds(1).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        }
        $queryErrors = @()
        $records = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 4097 -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
        $source.Events = @(Select-SasDockIncidentEvents -Records ($records | Select-Object -First 4096) -Window $Window -ProviderPattern $ProviderPattern)
        $failures = @($queryErrors | Where-Object FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*')
        if ($failures.Count) {
            $source.Status = if ($records.Count) { 'QUERY_PARTIAL' } else { 'QUERY_FAILED' }
            $source.Detail = $failures[0].Exception.Message
        }
        if ($records.Count -gt 4096) { $source.Status = 'TRUNCATED' }
    } catch {
        $id = $_.FullyQualifiedErrorId
        if ($id -like 'NoMatchingEventsFound,*') {
            $source.Status = 'READ'
        } elseif ($id -like 'NoMatchingLogsFound,*') {
            $source.Status = 'UNAVAILABLE'
        } else {
            $source.Status = 'QUERY_FAILED'
            $source.Detail = $_.Exception.Message
        }
    } finally {
        if ($oldest -is [IDisposable]) { $oldest.Dispose() }
        foreach ($record in $records) {
            if ($record -is [IDisposable]) { $record.Dispose() }
        }
    }
    return [pscustomobject]$source
}

function Get-SasDockSetupEvidence {
    param([string]$Path, [hashtable]$Window, [TimeZoneInfo]$Zone)

    $result = [ordered]@{ Status = 'READ'; Detail = $null; AmbiguousSections = 0; Sections = @() }
    $stream = $null
    $reader = $null
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $reader = [IO.StreamReader]::new($stream, $true)
        $heading = $null
        $section = $null
        $result.Sections = @(while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -match '^>>>  \[(?<header>.+)\]') {
                if ($section) { [pscustomobject]$section }
                $heading = $Matches.header
                $section = $null
                continue
            }
            if ($heading -and $line -match '^>>>  Section start (?<stamp>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{3})?)') {
                $local = [datetime]::ParseExact($Matches.stamp, [string[]]@('yyyy/MM/dd HH:mm:ss.fff', 'yyyy/MM/dd HH:mm:ss'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None)
                if ($Zone.IsAmbiguousTime($local)) {
                    foreach ($offset in $Zone.GetAmbiguousTimeOffsets($local)) {
                        $candidate = ([DateTimeOffset]::new($local, $offset)).UtcDateTime
                        if ($candidate -ge $Window.Start -and $candidate -lt $Window.End) {
                            $result.AmbiguousSections++
                            break
                        }
                    }
                    continue
                }
                if ($Zone.IsInvalidTime($local)) { continue }
                $utc = [TimeZoneInfo]::ConvertTimeToUtc($local, $Zone)
                if ($utc -ge $Window.Start -and $utc -lt $Window.End) {
                    $section = [ordered]@{ TimeUtc = $utc.ToString('o'); Header = $heading; ExitStatus = $null }
                }
                continue
            }
            if ($section -and $line -match '^<<<  \[Exit status: (?<status>.+)\]') {
                $section.ExitStatus = $Matches.status
                [pscustomobject]$section
                $section = $null
                $heading = $null
            }
        }; if ($section) { [pscustomobject]$section })
        if ($result.AmbiguousSections) { $result.Status = 'AMBIGUOUS_LOCAL_TIME' }
    } catch {
        $result.Status = 'UNAVAILABLE'
        $result.Detail = $_.Exception.Message
    } finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
    return [pscustomobject]$result
}

function Get-SasDockSnapshotSection {
    param([scriptblock]$Read)
    try {
        [pscustomobject]@{ Status = 'READ'; Items = @(& $Read); Detail = $null }
    } catch {
        [pscustomobject]@{ Status = 'QUERY_FAILED'; Items = @(); Detail = $_.Exception.Message }
    }
}

function Compare-SasDockSnapshot {
    param($Before, $After)

    foreach ($area in @('Devices', 'Drivers', 'Services', 'NetworkAdapters')) {
        $previous = $Before.$area
        $current = $After.$area
        if ($previous.Status -ne 'READ' -or $current.Status -ne 'READ') {
            [pscustomobject]@{ Section = $area; Status = 'NOT_COMPARABLE'; Changes = @() }
            continue
        }
        $old = @{}
        $new = @{}
        foreach ($row in $previous.Items) { $old[[string]$row.Key] = $row }
        foreach ($row in $current.Items) { $new[[string]$row.Key] = $row }
        $changes = foreach ($key in (@($old.Keys) + @($new.Keys) | Sort-Object -Unique)) {
            if (-not $old.ContainsKey($key)) { $state = 'APPEARED' }
            elseif (-not $new.ContainsKey($key)) { $state = 'DISAPPEARED' }
            elseif (($old[$key] | ConvertTo-Json -Compress) -cne ($new[$key] | ConvertTo-Json -Compress)) { $state = 'CHANGED' }
            else { continue }
            [pscustomobject]@{ Key = $key; State = $state; Before = $old[$key]; After = $new[$key] }
        }
        [pscustomobject]@{ Section = $area; Status = 'COMPARED'; Changes = @($changes) }
    }
}

function Write-SasDockIncidentReceipt {
    param([string]$Root, [System.Collections.IDictionary]$Receipt)

    [void][IO.Directory]::CreateDirectory($Root)
    $path = Join-Path $Root ('dock-{0}-{1}.json' -f [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [guid]::NewGuid().ToString('N'))
    $temp = "$path.tmp"
    try {
        [IO.File]::WriteAllText($temp, ($Receipt | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temp, $path)
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
    return $path
}

Export-ModuleMember -Function Resolve-SasDockIncidentWindow, Select-SasDockIncidentEvents, Get-SasDockEventEvidence, Get-SasDockSetupEvidence, Get-SasDockSnapshotSection, Compare-SasDockSnapshot, Write-SasDockIncidentReceipt
