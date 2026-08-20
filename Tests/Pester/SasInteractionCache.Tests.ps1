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

    It 'expires stale suggestions without treating expiration as an authoritative failure' {
        $old = [datetime]'2026-01-01T00:00:00Z'
        Add-SasInteractionCacheEntry -Scope northwell -Kind Printer -Value '\\PRINTSRV01\QUEUE01' -CachePath $script:cachePath -NowUtc $old | Should -BeTrue
        $items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Printer -CachePath $script:cachePath -NowUtc $old.AddDays(91) -TtlDays 90)
        $items.Count | Should -Be 0
        $snapshot = Get-SasInteractionCacheSnapshot -CachePath $script:cachePath -NowUtc $old.AddDays(91) -TtlDays 90
        $snapshot.ItemCount | Should -Be 0
    }

    It 'quarantines malformed state and fails open to an empty suggestion set' {
        New-Item -ItemType Directory -Path $script:cacheRoot -Force | Out-Null
        Set-Content -LiteralPath $script:cachePath -Value '{ definitely-not-json' -Encoding UTF8
        { $script:items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -CachePath $script:cachePath) } | Should -Not -Throw
        $script:items.Count | Should -Be 0
        Test-Path -LiteralPath $script:cachePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:cacheRoot -Filter 'interactions.v1.corrupt-*.json').Count | Should -Be 1
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
            Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value ('PC{0:D3}' -f $index) -CachePath $script:cachePath -NowUtc $base.AddMinutes($index) -MaxEntries 20 -MaxEntriesPerKind 5 | Should -BeTrue
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

    It 'provides a bounded local read benchmark fixture for regression evidence' {
        $now = [datetime]'2026-08-01T00:00:00Z'
        foreach ($index in 1..20) {
            Add-SasInteractionCacheEntry -Scope northwell -Kind Host -Value ('BENCH{0:D3}' -f $index) -CachePath $script:cachePath -NowUtc $now.AddMinutes($index) | Should -BeTrue
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($iteration in 1..50) {
            $items = @(Get-SasInteractionCacheEntries -Scope northwell -Kind Host -Top 10 -CachePath $script:cachePath -NowUtc $now.AddHours(1))
            $items.Count | Should -Be 10
        }
        $sw.Stop()
        Write-Host ("CACHE_BENCHMARK local_json_reads=50 elapsed_ms={0} average_ms={1:N3}" -f $sw.ElapsedMilliseconds, ($sw.Elapsed.TotalMilliseconds / 50.0))
        $sw.ElapsedMilliseconds | Should -BeLessThan 5000
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
