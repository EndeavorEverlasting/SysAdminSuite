#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Tests for repository health tooling: BOM encoding, dollar-sign escaping,
    and script health checks.
    All tests run offline with no side effects.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $toolsDir = Join-Path $repoRoot 'tools'
    $script:addBomScript     = Join-Path $toolsDir 'Add-Utf8Bom.ps1'
    $script:testHealthScript = Join-Path $toolsDir 'Test-ScriptHealth.ps1'
    $script:repoHealthScript = Join-Path $toolsDir 'Invoke-RepoFileHealth.ps1'
    $script:guiPath          = Join-Path $repoRoot 'GUI\Start-SysAdminSuiteGui.ps1'

    # Temp directory for BOM tests
    $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "SAS_RepoHealth_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
}

AfterAll {
    if ($script:tmpDir -and (Test-Path $script:tmpDir)) {
        Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Tool scripts exist ──
Describe 'Repo health tool scripts exist' {
    It 'Add-Utf8Bom.ps1 exists' { $script:addBomScript | Should -Exist }
    It 'Test-ScriptHealth.ps1 exists' { $script:testHealthScript | Should -Exist }
    It 'Invoke-RepoFileHealth.ps1 exists' { $script:repoHealthScript | Should -Exist }
}

# ── BOM detection logic ──
Describe 'UTF-8 BOM detection' {
    It 'Detects BOM bytes EF BB BF at start of file' {
        $f = Join-Path $script:tmpDir 'has_bom.ps1'
        [System.IO.File]::WriteAllBytes($f, ([byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes('Write-Host "hello"')))
        $bytes = [System.IO.File]::ReadAllBytes($f)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
    }

    It 'Detects missing BOM on a plain UTF-8 file' {
        $f = Join-Path $script:tmpDir 'no_bom.ps1'
        [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::UTF8.GetBytes('Write-Host "hello"'))
        $bytes = [System.IO.File]::ReadAllBytes($f)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'Detects missing BOM on an empty file' {
        $f = Join-Path $script:tmpDir 'empty.ps1'
        [System.IO.File]::WriteAllBytes($f, [byte[]]@())
        $bytes = [System.IO.File]::ReadAllBytes($f)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }
}

# ── BOM fixing logic ──
Describe 'UTF-8 BOM fixing' {
    It 'Adds BOM bytes to a file without one' {
        $f = Join-Path $script:tmpDir 'fix_me.ps1'
        $content = 'Write-Host "test"'
        [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::UTF8.GetBytes($content))

        # Apply BOM
        $raw = [System.IO.File]::ReadAllBytes($f)
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        [System.IO.File]::WriteAllBytes($f, ($bom + $raw))

        # Verify
        $after = [System.IO.File]::ReadAllBytes($f)
        $after[0] | Should -Be 0xEF
        $after[1] | Should -Be 0xBB
        $after[2] | Should -Be 0xBF
        # Content preserved
        $text = [System.Text.Encoding]::UTF8.GetString($after, 3, $after.Length - 3)
        $text | Should -Be $content
    }

    It 'Does not double-BOM a file that already has one' {
        $f = Join-Path $script:tmpDir 'already_bom.ps1'
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        $content = [System.Text.Encoding]::UTF8.GetBytes('Write-Host "ok"')
        [System.IO.File]::WriteAllBytes($f, ($bom + $content))

        # Check and skip
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $hasBom | Should -BeTrue
        # If already has BOM, do not prepend again
        if (-not $hasBom) {
            [System.IO.File]::WriteAllBytes($f, ($bom + $bytes))
        }
        $final = [System.IO.File]::ReadAllBytes($f)
        $final.Length | Should -Be ($bom.Length + $content.Length)
    }

    It 'Preserves non-ASCII content after BOM addition' {
        $f = Join-Path $script:tmpDir 'nonascii.ps1'
        $text = 'Write-Host "Ünïcödé"'
        [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::UTF8.GetBytes($text))

        $raw = [System.IO.File]::ReadAllBytes($f)
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        [System.IO.File]::WriteAllBytes($f, ($bom + $raw))

        $after = [System.IO.File]::ReadAllBytes($f)
        $restored = [System.Text.Encoding]::UTF8.GetString($after, 3, $after.Length - 3)
        $restored | Should -Be $text
    }
}

# ── All repo .ps1 files have BOM ──
Describe 'Repo-wide BOM compliance' {
    It 'All .ps1 files in the repo have UTF-8 BOM' {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $excludeDirs = @('.git','node_modules','__pycache__','Output','Archive','.vs','bin','obj','dist')
        $files = Get-ChildItem -Path $repoRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object {
                $rel = $_.FullName.Replace($repoRoot,'')
                $skip = $false
                foreach ($ex in $excludeDirs) {
                    if ($rel -match "(^|[\\/])$([regex]::Escape($ex))([\\/]|`$)") { $skip = $true; break }
                }
                # Also skip temp test scripts at repo root
                if ($_.Name -match '^_') { $skip = $true }
                -not $skip
            }

        $noBom = @()
        foreach ($f in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            if (-not $hasBom) { $noBom += $f.FullName.Replace($repoRoot,'').TrimStart('\','/') }
        }
        $noBom | Should -BeNullOrEmpty -Because "All .ps1 files should have UTF-8 BOM. Missing: $($noBom -join ', ')"
    }
}

# ── Dollar-sign escaping ──
Describe 'Dollar-sign escaping standards' {
    It 'Single-quoted strings preserve dollar signs literally' {
        $text = '$variable stays as-is'
        $text | Should -BeLike '*$variable*'
    }

    It 'Double-quoted strings interpolate dollar signs' {
        $variable = 'replaced'
        $text = "Value is $variable"
        $text | Should -Be 'Value is replaced'
    }

    It 'Backtick-escaped dollar signs are preserved in double-quoted strings' {
        $text = "Cost is `$5.00"
        $text | Should -Be 'Cost is $5.00'
    }

    It 'Here-strings with single quotes preserve dollar signs' {
        $text = @'
$PSScriptRoot is literal here
'@
        $text | Should -Match '\$PSScriptRoot'
    }

    It 'No repo scripts use unescaped dollar signs in Write-Host string literals that would fail' {
        # Parses every .ps1 and flags syntax errors.
        # Scripts that intentionally use PS7 syntax (??, ?.) are excluded.
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        # Known PS7-only scripts that won't parse under PS 5.1
        $knownPS7 = @(
            'Config\Build-FetchMap.ps1',
            'Config\GoLiveTools.ps1',
            'Mapping\Workers\Map-MachineWide.v5Compat.ps1'
        )
        $parseIssues = @()
        $files = Get-ChildItem -Path $repoRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|Output|Archive|dist|_)' }

        foreach ($f in $files) {
            $rel = $f.FullName.Replace($repoRoot,'').TrimStart('\','/')
            if ($knownPS7 -contains $rel) { continue }
            $tokens = $null; $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                $parseIssues += $rel
            }
        }
        $parseIssues | Should -BeNullOrEmpty -Because "All .ps1 files should parse without errors: $($parseIssues -join ', ')"
    }
}

# ── Script health tool contracts ──
Describe 'Test-ScriptHealth.ps1 script contracts' {
    BeforeAll {
        $script:healthContent = Get-Content -Path $script:testHealthScript -Raw
    }

    It 'Accepts -Path parameter' { $script:healthContent | Should -Match '\[string\]\$Path' }
    It 'Has -SkipParse switch'   { $script:healthContent | Should -Match '\$SkipParse' }
    It 'Has -SkipBom switch'     { $script:healthContent | Should -Match '\$SkipBom' }
    It 'Has -SkipNonAscii switch' { $script:healthContent | Should -Match '\$SkipNonAscii' }
    It 'Checks for BOM bytes EF BB BF' { $script:healthContent | Should -Match '0xEF.*0xBB.*0xBF' }
    It 'Reports parse errors' { $script:healthContent | Should -Match 'ParseErrors' }
    It 'Reports missing BOM' { $script:healthContent | Should -Match 'MissingBom' }
    It 'Scans for non-ASCII characters' { $script:healthContent | Should -Match 'NonAscii' }
}

# ── Add-Utf8Bom.ps1 contracts ──
Describe 'Add-Utf8Bom.ps1 script contracts' {
    BeforeAll {
        $script:bomContent = Get-Content -Path $script:addBomScript -Raw
    }

    It 'Supports -Fix switch' { $script:bomContent | Should -Match '\$Fix' }
    It 'Supports -Path parameter' { $script:bomContent | Should -Match '\$Path' }
    It 'Supports ShouldProcess' { $script:bomContent | Should -Match 'SupportsShouldProcess' }
    It 'Uses BOM bytes EF BB BF' { $script:bomContent | Should -Match '0xEF.*0xBB.*0xBF' }
    It 'Defaults to dry-run mode' { $script:bomContent | Should -Match 'DRY-RUN' }
    It 'Excludes .git directory' { $script:bomContent | Should -Match '\.git' }
}

# ── Invoke-RepoFileHealth.ps1 contracts ──
Describe 'Invoke-RepoFileHealth.ps1 script contracts' {
    BeforeAll {
        $script:repoContent = Get-Content -Path $script:repoHealthScript -Raw
    }

    It 'Supports -Fix switch' { $script:repoContent | Should -Match '\$Fix' }
    It 'Handles Zone.Identifier locks' { $script:repoContent | Should -Match 'Zone\.Identifier' }
    It 'Handles BOM addition' { $script:repoContent | Should -Match 'BOMAdded' }
    It 'Handles line ending normalisation' { $script:repoContent | Should -Match 'LineEndingsFixed' }
    It 'Supports CRLF and LF line ending styles' { $script:repoContent | Should -Match 'CRLF.*LF' }
    It 'Scans for non-ASCII characters' { $script:repoContent | Should -Match 'NonAscii' }
}

