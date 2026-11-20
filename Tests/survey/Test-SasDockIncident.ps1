#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $base 'scripts/SasDockIncident.psm1') -Force

function Assert-Dock([bool]$Pass, [string]$Case) {
    if (-not $Pass) { throw $Case }
    Write-Output "PASS: $Case"
}

$now = [DateTimeOffset]::Parse('2026-01-15T19:00:00Z')
$window = Resolve-SasDockIncidentWindow -Start '2026-01-15T13:00:00-05:00' -End '2026-01-15T13:03:00-05:00' -Now $now
Assert-Dock ($window.Start.ToString('o') -eq '2026-01-15T18:00:00.0000000Z' -and $window.End.Minute -eq 3) 'Eastern timestamp resolves to the full incident minutes in UTC'
$rolling = Resolve-SasDockIncidentWindow -Now $now
Assert-Dock (($rolling.End - $rolling.Start).TotalMinutes -eq 10 -and $rolling.End -eq $now.UtcDateTime) 'Default lookback is ten minutes'
$invalid = @(
    @{ Start = '2026-01-15T13:00:00'; End = '2026-01-15T13:03:00-05:00' },
    @{ Start = '2026-01-15T13:00:00-05:00'; End = '2026-01-15T12:59:00-05:00' },
    @{ Start = '2026-01-15T10:00:00-05:00'; End = '2026-01-15T13:00:00-05:00' },
    @{ Start = '2026-01-15T13:00:00-05:00'; End = '2026-01-15T14:01:00-05:00' },
    @{ Start = '2026-01-15T13:00:00-05:00' }
)
foreach ($argsForWindow in $invalid) {
    $rejected = $false
    try { $null = Resolve-SasDockIncidentWindow -Now $now @argsForWindow }
    catch { $rejected = $true }
    Assert-Dock $rejected "Invalid window rejected: $($argsForWindow.Start) to $($argsForWindow.End)"
}

function Get-WinEvent {
    [CmdletBinding()]
    param($ListLog, $LogName, [switch]$Oldest, $FilterHashtable, $MaxEvents)
    if ($ListLog) {
        if ($ListLog -eq 'Missing') {
            $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new([Exception]::new('missing'), 'NoMatchingLogsFound', 'ObjectNotFound', $null))
        }
        return @{ IsEnabled = $ListLog -ne 'Disabled'; RecordCount = 50 }
    }
    if ($Oldest) { return @{ TimeCreated = $window.Start.AddDays(-1) } }
    $script:queriedWindow = $FilterHashtable
    if ($FilterHashtable.LogName -eq 'Empty') {
        $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new([Exception]::new('empty'), 'NoMatchingEventsFound', 'ObjectNotFound', $null))
        return
    }
    if ($FilterHashtable.LogName -eq 'Partial') {
        $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new([Exception]::new('message formatting failed'), 'EventLogException', 'ReadError', $null))
    }
    foreach ($record in $fixtureRecords) { $record }
}
$fixtureRecords = @(
    @{ TimeCreated = $window.Start.AddTicks(-1); ProviderName = 'Display'; Id = 4101 },
    @{ TimeCreated = $window.Start; ProviderName = 'Display'; Id = 4101 },
    @{ TimeCreated = $window.Start.AddMinutes(1); ProviderName = 'FixtureUnrelated'; Id = 5 },
    @{ TimeCreated = $window.End.AddTicks(-1); ProviderName = 'BTHUSB'; Id = 17 },
    @{ TimeCreated = $window.End; ProviderName = 'Display'; Id = 4101 }
)
$observed = Get-SasDockEventEvidence -Channel System -Window $window -ProviderPattern 'Display|BTHUSB'
Assert-Dock ($queriedWindow.StartTime -ceq '2026-01-15T18:00:00.0000000Z' -and $queriedWindow.EndTime -ceq '2026-01-15T18:03:00.0010000Z') 'Native event query receives explicit UTC bounds'
Assert-Dock ($observed.Events.Count -eq 2 -and $observed.Events[1].Provider -eq 'BTHUSB') 'Timeline keeps relevant records and excludes the exact end'
Assert-Dock ($observed.OldestRetainedUtc -eq '2026-01-14T18:00:00.0000000Z') 'Oldest retained event is reported independently'
Assert-Dock ((Get-SasDockEventEvidence -Channel Disabled -Window $window).Status -eq 'DISABLED') 'Disabled source is reported'
Assert-Dock ((Get-SasDockEventEvidence -Channel Missing -Window $window).Status -eq 'UNAVAILABLE') 'Missing source is reported'
$empty = Get-SasDockEventEvidence -Channel Empty -Window $window
Assert-Dock ($empty.Status -eq 'READ' -and $empty.Events.Count -eq 0) 'Zero matches retain successful read status'
$partial = Get-SasDockEventEvidence -Channel Partial -Window $window
Assert-Dock ($partial.Status -eq 'QUERY_PARTIAL' -and $partial.Events.Count -gt 0) 'A provider error retains readable event records'

$before = @{ Devices = @{ Status = 'READ'; Items = @([pscustomobject]@{ Key = 'same'; Problem = 'OK' }, [pscustomobject]@{ Key = 'old' }) } }
$after = @{ Devices = @{ Status = 'READ'; Items = @([pscustomobject]@{ Key = 'same'; Problem = 'failed' }, [pscustomobject]@{ Key = 'new' }) } }
$diff = @(Compare-SasDockSnapshot -Before $before -After $after)
Assert-Dock (($diff[0].Changes.State -join ',') -eq 'APPEARED,DISAPPEARED,CHANGED') 'Baseline comparison reports all three changes'
$after.Devices.Status = 'QUERY_FAILED'
$diff = @(Compare-SasDockSnapshot -Before $before -After $after)
Assert-Dock ($diff[0].Status -eq 'NOT_COMPARABLE' -and $diff[0].Changes.Count -eq 0) 'Failed snapshot cannot imply disappearance'

$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -Path $temp -ItemType Directory
    $setupLog = Join-Path $temp 'setupapi.dev.log'
    @'
>>>  [Device Install (Hardware initiated) - USB\FIXTURE]
>>>  Section start 2026/01/15 13:02:30.125
     dvi: fixture
<<<  Section end 2026/01/15 13:02:31.010
<<<  [Exit status: SUCCESS]
>>>  [Device Install - OUTSIDE]
>>>  Section start 2026/01/15 13:03:00.000
<<<  [Exit status: FAILURE]
'@ | Set-Content -LiteralPath $setupLog -Encoding Unicode
    $zone = [TimeZoneInfo]::CreateCustomTimeZone('Fixture Eastern', [timespan]::FromHours(-5), 'fixture', 'fixture')
    $install = Get-SasDockSetupEvidence -Path $setupLog -Window $window -Zone $zone
    Assert-Dock ($install.Sections.Count -eq 1 -and $install.Sections[0].ExitStatus -eq 'SUCCESS' -and $install.Sections[0].TimeUtc -eq '2026-01-15T18:02:30.1250000Z') 'SetupAPI handles native section shape, BOM, and local-zone timestamps'
    $receipt = [ordered]@{ OperatorReport = @{ Observation = 'Fixture LED off' }; Timeline = @($observed.Events) }
    $one = Write-SasDockIncidentReceipt -Root $temp -Receipt $receipt
    $two = Write-SasDockIncidentReceipt -Root $temp -Receipt $receipt
    $loaded = Get-Content -LiteralPath $one -Raw | ConvertFrom-Json
    Assert-Dock ($one -ne $two -and $loaded.OperatorReport.Observation -eq 'Fixture LED off' -and $loaded.Timeline.Count -eq 2 -and -not @(Get-ChildItem $temp -Filter '*.tmp').Count) 'Receipt preserves separate operator observations and has unique atomic output'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

# Exercise the actual admission script with synthetic path, Git, network and collector boundaries.
$admission = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
$env:SAS_DOCK_TEST_TRACE = Join-Path $admission 'trace'
$fixtureScripts = Join-Path $admission 'scripts'
try {
    $null = New-Item -Path $fixtureScripts -ItemType Directory -Force
    Copy-Item (Join-Path $base 'scripts/Open-SasDockIncident.ps1') $fixtureScripts
    @'
if ($env:SAS_DOCK_TEST_CASE -eq 'copied') {
    '{"candidate_classification":"UNREGISTERED_CHECKOUT"}'
} else {
    '{"candidate_classification":"CANONICAL_DEVELOPMENT"}'
}
exit 0
'@ | Set-Content (Join-Path $fixtureScripts 'Resolve-SasCanonicalDevelopmentPath.ps1')
    @'
function Get-SasNetworkIntentState {
    @{ classification = 'GUEST_INTERNET'; label = 'fixture' }
}
function Enter-SasNetworkIntent {
    param([string] $Intent)
    Add-Content $env:SAS_DOCK_TEST_TRACE $Intent
    if ($env:SAS_DOCK_TEST_CASE -eq 'offline') { throw 'offline fixture' }
    @{ restore_required = $false }
}
function Restore-SasNetworkIntent {
    Add-Content $env:SAS_DOCK_TEST_TRACE 'restored'
}
'@ | Set-Content (Join-Path $fixtureScripts 'SasNetworkIntent.psm1')
    @'
param([string]$Start,[string]$End)
if (-not $Start -or -not $End) { exit 1 }
Add-Content $env:SAS_DOCK_TEST_TRACE 'collected'
exit 2
'@ | Set-Content (Join-Path $fixtureScripts 'Get-SasDockIncident.ps1')

    function git {
        $global:LASTEXITCODE = 0
        $sha = 'a' * 40
        switch ($args[2]) {
            'branch' { 'main' }
            'fetch' { Add-Content $env:SAS_DOCK_TEST_TRACE 'fetch' }
            'ls-remote' { 'ref: refs/heads/main  HEAD'; "$sha  HEAD" }
            'rev-parse' { $sha }
        }
    }

    $entry = Join-Path $fixtureScripts 'Open-SasDockIncident.ps1'
    $env:SAS_DOCK_TEST_CASE = 'online'
    $null = & $entry
    $result = $LASTEXITCODE
    $trace = (Get-Content $env:SAS_DOCK_TEST_TRACE) -join ','
    Assert-Dock ($result -eq 2 -and $trace -eq 'InternetSync,fetch,restored,LocalOnly,collected') 'Admitted launcher forwards a bounded window and preserves capture exit status'

    Remove-Item $env:SAS_DOCK_TEST_TRACE
    $env:SAS_DOCK_TEST_CASE = 'copied'
    $null = & $entry 2>$null
    $result = $LASTEXITCODE
    Assert-Dock ($result -eq 1 -and -not (Test-Path $env:SAS_DOCK_TEST_TRACE)) 'Copied launcher fails before any Git or collector activity'

    $env:SAS_DOCK_TEST_CASE = 'offline'
    $null = & $entry 2>$null
    $result = $LASTEXITCODE
    Assert-Dock ($result -eq 1 -and (Get-Content $env:SAS_DOCK_TEST_TRACE) -eq 'InternetSync') 'Internet admission failure prevents Git and collector activity'
} finally {
    Remove-Item Env:SAS_DOCK_TEST_CASE, Env:SAS_DOCK_TEST_TRACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $admission -Recurse -Force
}
