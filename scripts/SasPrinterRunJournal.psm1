Set-StrictMode -Version Latest

$script:SchemaVersion = 'sas-printer-operator-event/v1'
$script:DefaultMaxJournalBytes = 524288

function Get-SasPrinterRunJournalPaths {
    [CmdletBinding()]
    param([string]$CacheRoot)

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [string]$env:LOCALAPPDATA }
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            throw 'LOCALAPPDATA is unavailable; the local printer operator trail cannot be resolved.'
        }
        $CacheRoot = Join-Path $localAppData 'SysAdminSuite\Cache\Printer'
    }

    $root = [IO.Path]::GetFullPath($CacheRoot)
    return [pscustomobject][ordered]@{
        Root = $root
        JournalPath = Join-Path $root 'runs.v1.jsonl'
        PreviousJournalPath = Join-Path $root 'runs.v1.previous.jsonl'
        LatestPath = Join-Path $root 'latest.v1.json'
    }
}

function Rotate-SasPrinterRunJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JournalPath,
        [Parameter(Mandatory)][string]$PreviousJournalPath,
        [ValidateRange(16384,10485760)][int]$MaxJournalBytes = $script:DefaultMaxJournalBytes
    )

    if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) { return }
    $item = Get-Item -LiteralPath $JournalPath -ErrorAction Stop
    if ($item.Length -lt $MaxJournalBytes) { return }
    Move-Item -LiteralPath $JournalPath -Destination $PreviousJournalPath -Force -ErrorAction Stop
}

function Get-SasPrinterMachineWideOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Summary,
        [ValidateSet('Map','Unmap')][string]$Action = 'Map'
    )

    if (-not [bool]$Summary.Success) { return 'FAILED' }
    $changed = @(
        @($Summary.Results) |
            ForEach-Object { @($_.ChangedPrinters) } |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $already = @(
        @($Summary.Results) |
            ForEach-Object { @($_.AlreadyDesiredPrinters) } |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    if ($Action -eq 'Map') {
        if ($changed.Count -gt 0) { return 'MAPPED_NOW' }
        if ($already.Count -gt 0) { return 'ALREADY_MAPPED' }
        return 'MACHINE_WIDE_READY'
    }
    if ($changed.Count -gt 0) { return 'UNMAPPED_NOW' }
    if ($already.Count -gt 0) { return 'ALREADY_UNMAPPED' }
    return 'MACHINE_WIDE_ABSENT'
}

function Get-SasPrinterFriendlyFailure {
    [CmdletBinding()]
    param([AllowNull()][string]$Message)

    $text = [string]$Message
    if ($text -match "Print server '([^']+)' did not resolve in DNS") {
        return [pscustomobject][ordered]@{
            Outcome = 'NOT_FOUND'
            Headline = "NOT FOUND: print server '$($Matches[1])' could not be resolved. No endpoint changes were made."
        }
    }
    if ($text -match '(?i)No valid shared printer queues|Printer queue cannot be blank|Unsafe/non-UNC queue') {
        return [pscustomobject][ordered]@{
            Outcome = 'INVALID_PRINTER'
            Headline = 'NOT FOUND: the requested shared printer queue was blank, invalid, or could not be resolved. No endpoint changes were made.'
        }
    }
    return [pscustomobject][ordered]@{
        Outcome = 'FAILED'
        Headline = if ([string]::IsNullOrWhiteSpace($text)) { 'FAILED: printer readiness was not proven.' } else { "FAILED: $text" }
    }
}

function Write-SasPrinterRunJournalEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$Outcome,
        [string]$Message = '',
        [AllowNull()][string]$EvidenceRoot,
        [AllowNull()]$Summary,
        [string]$CacheRoot,
        [datetime]$TimestampUtc = [datetime]::UtcNow,
        [ValidateRange(16384,10485760)][int]$MaxJournalBytes = $script:DefaultMaxJournalBytes
    )

    try {
        $paths = Get-SasPrinterRunJournalPaths -CacheRoot $CacheRoot
        New-Item -ItemType Directory -Path $paths.Root -Force -ErrorAction Stop | Out-Null
        Rotate-SasPrinterRunJournal -JournalPath $paths.JournalPath -PreviousJournalPath $paths.PreviousJournalPath -MaxJournalBytes $MaxJournalBytes

        $targets = @()
        $printers = @()
        if ($null -ne $Summary) {
            $targets = @($Summary.Computers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $printers = @($Summary.Printers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        $userName = [string]$env:USERNAME
        if (-not [string]::IsNullOrWhiteSpace([string]$env:USERDOMAIN)) { $userName = "$($env:USERDOMAIN)\$userName" }

        $record = [pscustomobject][ordered]@{
            SchemaVersion = $script:SchemaVersion
            TimestampUtc = $TimestampUtc.ToUniversalTime().ToString('o')
            SessionId = $SessionId
            AdminBox = [string]$env:COMPUTERNAME
            User = $userName
            StorageScope = 'LOCAL_USER_CACHE_ONLY'
            Sharing = 'OPERATOR_DECIDES'
            Event = $Event
            Outcome = $Outcome
            Message = $Message
            Targets = $targets
            Printers = $printers
            EvidenceRoot = if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { $null } else { [IO.Path]::GetFullPath($EvidenceRoot) }
        }
        $json = $record | ConvertTo-Json -Depth 8 -Compress
        Add-Content -LiteralPath $paths.JournalPath -Value $json -Encoding UTF8 -ErrorAction Stop
        $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $paths.LatestPath -Encoding UTF8 -ErrorAction Stop
        return [pscustomobject][ordered]@{
            JournalPath = $paths.JournalPath
            LatestPath = $paths.LatestPath
            Record = $record
        }
    }
    catch {
        # The operator trail is intentionally local and best-effort. A cache write failure must never mutate a target or downgrade authoritative printer proof.
        return $null
    }
}

Export-ModuleMember -Function Get-SasPrinterRunJournalPaths,Get-SasPrinterMachineWideOutcome,Get-SasPrinterFriendlyFailure,Write-SasPrinterRunJournalEvent
