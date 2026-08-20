#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:modulePath = Join-Path $script:repoRoot 'scripts\SasInteractionCache.psm1'
    Import-Module $script:modulePath -Force
}

Describe 'SysAdminSuite interaction cache consistency contract' {
    BeforeEach {
        $script:cacheRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:cachePath = Join-Path $script:cacheRoot 'interactions.v1.json'
    }

    It 'uses a per-user LOCALAPPDATA namespace rather than repository or machine-global state' {
        $path = Get-SasInteractionCacheDefaultPath
        $path | Should -Match 'SysAdminSuite[\\/]Cache[\\/]interactions\.v1\.json$'
        $path | Should -Not -Match '(?i)ProgramData'
        $path | Should -Not -Match '(?i)mapping[\\/]Logs'
    }

    It 'deduplicates a successful interaction and advances recency/use count' {
        $first = [datetime]'2026-08-01T12:00:00Z'
        Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value 'WPJ001OPR001' -CachePath $script:cachePath -NowUtc $first | Should -BeTrue
        Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value 'wpj001opr001' -CachePath $script:cachePath -NowUtc $first.AddHours(2) | Should -BeTrue
        $items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath -NowUtc $first.AddHours(3))
        $items.Count | Should -Be 1
        $items[0].UseCount | Should -Be 2
        $items[0].DisplayValue | Should -Be 'wpj001opr001'
        $items[0].NormalizedValue | Should -Be 'wpj001opr001'
    }

    It 'isolates organization/profile scopes so one environment cannot inherit another cache' {
        $now = [datetime]'2026-08-01T12:00:00Z'
        Add-SasInteractionCacheEntry -Scope northwell -Kind Server -Value 'PRINTSRV01' -CachePath $script:cachePath -NowUtc $now | Should -BeTrue
        Add-SasInteractionCacheEntry -Scope health-hospitals -Kind Server -Value 'HHSRV01' -CachePath $script:cachePath -NowUtc $now | Should -BeTrue
        (@(Get-SasInteractionCacheEntries -Scope northwell -Kind Server -CachePath $script:cachePath -NowUtc $now)[0].DisplayValue) | Should -Be 'PRINTSRV01'
        (@(Get-SasInteractionCacheEntries -Scope health-hospitals -Kind Server -CachePath $script:cachePath -NowUtc $now)[0].DisplayValue) | Should -Be 'HHSRV01'
    }

    It 'caps each scope so one environment cannot exhaust the shared local cache' {
        $base = [datetime]'2026-08-01T00:00:00Z'
        foreach ($index in 1..8) {
            Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value ('NW{0:D2}' -f $index) -CachePath $script:cachePath -NowUtc $base.AddMinutes($index) -MaxEntries 20 -MaxEntriesPerScope 5 -MaxEntriesPerKind 20 | Should -BeTrue
        }
        foreach ($index in 1..3) {
            Add-SasInteractionCacheEntry -Scope health-hospitals -Kind Host -Value ('HH{0:D2}' -f $index) -CachePath $script:cachePath -NowUtc $base.AddHours(1).AddMinutes($index) -MaxEntries 20 -MaxEntriesPerScope 5 -MaxEntriesPerKind 20 | Should -BeTrue
        }
        @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -Top 20 -CachePath $script:cachePath -NowUtc $base.AddHours(2)).Count | Should -Be 5
        @(Get-SasInteractionCacheEntries -Scope health-hospitals -Kind Host -Top 20 -CachePath $script:cachePath -NowUtc $base.AddHours(2)).Count | Should -Be 3
        (Get-SasInteractionCacheSnapshot -CachePath $script:cachePath -NowUtc $base.AddHours(2)).ItemCount | Should -Be 8
    }

    It 'expires stale suggestions without treating expiration as an authoritative failure' {
        $old = [datetime]'2026-01-01T00:00:00Z'
        Add-SasInteractionCacheEntry -Scope northwell -Kind Printer -Value '\\PRINTSRV01\QUEUE01' -CachePath $script:cachePath -NowUtc $old | Should -BeTrue
        $items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Printer -CachePath $script:cachePath -NowUtc $old.AddDays(91) -TtlDays 90)
        $items.Count | Should -Be 0
        $snapshot = Get-SasInteractionCacheSnapshot -CachePath $script:cachePath -NowUtc $old.AddDays(91) -TtlDays 90
        $snapshot.ItemCount | Should -Be 0
    }

    It 'drops a same-window batch expiry without reviving stale suggestions' {
        $old = [datetime]'2026-01-01T00:00:00Z'
        foreach ($index in 1..8) {
            Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value ('EXP{0:D2}' -f $index) -CachePath $script:cachePath -NowUtc $old.AddSeconds($index) | Should -BeTrue
        }
        $now = $old.AddDays(91)
        @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -Top 20 -CachePath $script:cachePath -NowUtc $now -TtlDays 90).Count | Should -Be 0
        (Get-SasInteractionCacheSnapshot -CachePath $script:cachePath -NowUtc $now -TtlDays 90).ItemCount | Should -Be 0
    }

    It 'quarantines malformed state and fails open to an empty suggestion set' {
        New-Item -ItemType Directory -Path $script:cacheRoot -Force | Out-Null
        Set-Content -LiteralPath $script:cachePath -Value '{ definitely-not-json' -Encoding UTF8
        { $script:items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath) } | Should -Not -Throw
        $script:items.Count | Should -Be 0
        Test-Path -LiteralPath $script:cachePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:cacheRoot -Filter 'interactions.v1.corrupt-*.json').Count | Should -Be 1
    }

    It 'invalidates an unsupported cache generation by schema rollover' {
        New-Item -ItemType Directory -Path $script:cacheRoot -Force | Out-Null
        [ordered]@{
            SchemaVersion = 'sas-interaction-cache/v0'
            UpdatedUtc = '2026-08-01T00:00:00Z'
            Entries = @(
                [ordered]@{
                    Scope = 'northwell'
                    Kind = 'Host'
                    NormalizedValue = 'legacy01'
                    DisplayValue = 'LEGACY01'
                    FirstSuccessUtc = '2026-08-01T00:00:00Z'
                    LastSuccessUtc = '2026-08-01T00:00:00Z'
                    UseCount = 99
                }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:cachePath -Encoding UTF8

        $items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath -NowUtc ([datetime]'2026-08-01T01:00:00Z'))
        $items.Count | Should -Be 0
        Test-Path -LiteralPath $script:cachePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:cacheRoot -Filter 'interactions.v1.corrupt-*.json').Count | Should -Be 1
    }

    It 'recovers from cache loss without blocking origin work or future history writes' {
        $now = [datetime]'2026-08-01T00:00:00Z'
        Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value 'BEFORELOSS' -CachePath $script:cachePath -NowUtc $now | Should -BeTrue
        Remove-Item -LiteralPath $script:cachePath -Force
        { $script:afterLoss = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath -NowUtc $now.AddMinutes(1)) } | Should -Not -Throw
        $script:afterLoss.Count | Should -Be 0
        Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value 'AFTERLOSS' -CachePath $script:cachePath -NowUtc $now.AddMinutes(2) | Should -BeTrue
        $recovered = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath -NowUtc $now.AddMinutes(3))
        $recovered.Count | Should -Be 1
        $recovered[0].DisplayValue | Should -Be 'AFTERLOSS'
    }

    It 'fails open when another writer holds the bounded cache lock' {
        New-Item -ItemType Directory -Path $script:cacheRoot -Force | Out-Null
        $lockPath = "$script:cachePath.lock"
        $held = New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value 'WPJ001OPR002' -CachePath $script:cachePath -LockTimeoutMilliseconds 50
            $sw.Stop()
            $result | Should -BeFalse
            $sw.ElapsedMilliseconds | Should -BeLessThan 1000
        }
        finally {
            $held.Dispose()
        }
    }

    It 'caps each key class so one dimension cannot exhaust local cache capacity' {
        $base = [datetime]'2026-08-01T00:00:00Z'
        foreach ($index in 1..12) {
            Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value ('PC{0:D3}' -f $index) -CachePath $script:cachePath -NowUtc $base.AddMinutes($index) -MaxEntries 20 -MaxEntriesPerScope 20 -MaxEntriesPerKind 5 | Should -BeTrue
        }
        $snapshot = Get-SasInteractionCacheSnapshot -CachePath $script:cachePath -NowUtc $base.AddHours(1)
        $snapshot.Hosts | Should -Be 5
        $snapshot.ItemCount | Should -Be 5
        $recent = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -Top 10 -CachePath $script:cachePath -NowUtc $base.AddHours(1))
        $recent[0].DisplayValue | Should -Be 'PC012'
        $recent[-1].DisplayValue | Should -Be 'PC008'
    }

    It 'rejects control characters and oversized untrusted cache keys' {
        { Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value "PC001`nPC002" -CachePath $script:cachePath } | Should -Throw '*control characters*'
        { Add-SasInteractionCacheEntry -Scope northwell -Kind Printer -Value ('X' * 513) -CachePath $script:cachePath } | Should -Throw '*512-character*'
        { Add-SasInteractionCacheEntry -Scope '../northwell' -Kind Server -Value 'PRINTSRV01' -CachePath $script:cachePath } | Should -Throw '*scope*invalid*'
    }

    It 'records bounded metrics without logging cached hostnames, printers, or servers' {
        $secretValue = 'WPJ999OPR999'
        Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value $secretValue -CachePath $script:cachePath | Should -BeTrue
        $null = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath)
        $metrics = Get-Content -LiteralPath (Join-Path $script:cacheRoot 'cache-metrics.v1.jsonl') -Raw
        $metrics | Should -Not -Match [regex]::Escape($secretValue)
        $metrics | Should -Match '"Event"'
        $metrics | Should -Match '"LatencyMs"'
    }

    It 'provides bounded p50 p95 and p99 local read benchmark evidence' {
        $now = [datetime]'2026-08-01T00:00:00Z'
        foreach ($index in 1..20) {
            Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value ('BENCH{0:D3}' -f $index) -CachePath $script:cachePath -NowUtc $now.AddMinutes($index) | Should -BeTrue
        }
        $samples = New-Object System.Collections.Generic.List[double]
        $total = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($iteration in 1..50) {
            $single = [System.Diagnostics.Stopwatch]::StartNew()
            $items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -Top 10 -CachePath $script:cachePath -NowUtc $now.AddHours(1))
            $single.Stop()
            $items.Count | Should -Be 10
            $samples.Add($single.Elapsed.TotalMilliseconds)
        }
        $total.Stop()
        $sorted = @($samples | Sort-Object)
        $p50 = $sorted[[math]::Ceiling($sorted.Count * 0.50) - 1]
        $p95 = $sorted[[math]::Ceiling($sorted.Count * 0.95) - 1]
        $p99 = $sorted[[math]::Ceiling($sorted.Count * 0.99) - 1]
        Write-Host ("CACHE_BENCHMARK local_json_reads=50 elapsed_ms={0} average_ms={1:N3} p50_ms={2:N3} p95_ms={3:N3} p99_ms={4:N3}" -f $total.ElapsedMilliseconds, ($total.Elapsed.TotalMilliseconds / 50.0), $p50, $p95, $p99)
        $total.ElapsedMilliseconds | Should -BeLessThan 5000
        $p99 | Should -BeLessThan 250
    }
}

Describe 'Interaction cache remains advisory, never authoritative' {
    It 'contains no remote mutation or printer proof implementation' {
        $content = Get-Content -LiteralPath $script:modulePath -Raw
        $content | Should -Not -Match '(?i)PrintUIEntry'
        $content | Should -Not -Match '(?i)HKEY_LOCAL_MACHINE'
        $content | Should -Not -Match '(?i)Invoke-Command'
        $content | Should -Not -Match '(?i)New-PSSession'
        $content | Should -Not -Match '(?i)Password|Credential|Secret|Token'
    }
}
