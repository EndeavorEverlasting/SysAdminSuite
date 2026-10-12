#Requires -Version 5.1
Describe 'Canonical path reparse safety' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:resolver = Join-Path $repoRoot 'scripts\Resolve-SasCanonicalDevelopmentPath.ps1'
        $script:module = Join-Path $repoRoot 'scripts\SasReparseInspection.psm1'
        Import-Module $module -Force
    }

    Context 'Pure reparse tag classification' {
        It 'classifies the full OneDrive cloud placeholder family as inspectable' {
            foreach ($hex in @('9000001A', '9000101A', '9000501A', '9000601A', '9000701A', '9000F01A')) {
                $tag = [uint32][Convert]::ToUInt32($hex, 16)
                Resolve-SasReparseTagClassification -Tag $tag | Should -Be 'ONEDRIVE_CLOUD_PLACEHOLDER'
            }
        }

        It 'rejects junctions, symlinks, legacy OneDrive tags, and near-miss cloud tags' {
            foreach ($hex in @('A0000003', 'A000000C', '80000013', '8000001C', '9000001B', '8000001A', '00000000', 'E0000006')) {
                $tag = [uint32][Convert]::ToUInt32($hex, 16)
                Resolve-SasReparseTagClassification -Tag $tag | Should -Be 'UNSAFE'
            }
        }
    }

    Context 'Reparse tag reader against real filesystem objects' {
        It 'reads the junction reparse tag 0xa0000003 from a real junction' {
            $target = Join-Path $TestDrive ('reader-target-' + [guid]::NewGuid().ToString('N'))
            $junction = Join-Path $TestDrive ('reader-junction-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
            $tag = Get-SasFileSystemReparseTag -Path $junction
            $tag | Should -Not -BeNullOrEmpty
            [uint32]$tag | Should -Be ([uint32][Convert]::ToUInt32('A0000003', 16))
        }

        It 'returns no tag for a normal directory' {
            $normal = Join-Path $TestDrive ('normal-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $normal -Force | Out-Null
            Get-SasFileSystemReparseTag -Path $normal | Should -BeNullOrEmpty
        }
    }

    Context 'Resolver admission against fixture checkouts' {
        BeforeEach {
            $script:gitFixture = {
                param([string]$path)
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                git -C $path init -q
                git -C $path config user.name 'SysAdminSuite Pester'
                git -C $path config user.email 'sysadminsuite-pester@example.invalid'
                git -C $path remote add origin https://github.com/EndeavorEverlasting/SysAdminSuite.git
                Set-Content -LiteralPath (Join-Path $path 'fixture.txt') -Value 'reparse fixture' -Encoding ASCII
                git -C $path add fixture.txt
                git -C $path commit -q -m 'reparse fixture'
                if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
            }
        }

        It 'admits a normal canonical checkout with healthy Git I/O (positive control)' {
            $devRoot = Join-Path $TestDrive ('pos-dev-' + [guid]::NewGuid().ToString('N'))
            & $gitFixture (Join-Path $devRoot 'SysAdminSuite')
            $raw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $resolver -DesktopDevRoot $devRoot -RequireCheckout -AsJson
            $code = $LASTEXITCODE
            $global:LASTEXITCODE = 0
            $receipt = $raw | ConvertFrom-Json
            $code | Should -Be 0
            $receipt.canonical_checkout_status | Should -Be 'CANONICAL_PROVED'
            $receipt.canonical_checkout_reparse_classification | Should -Be 'NONE'
            $receipt.canonical_git_io_health | Should -Be 'HEALTHY'
        }

        It 'fails closed when the canonical checkout itself is a junction escape' {
            $devRoot = Join-Path $TestDrive ('jx-dev-' + [guid]::NewGuid().ToString('N'))
            $elsewhere = Join-Path $TestDrive ('jx-target-' + [guid]::NewGuid().ToString('N'))
            & $gitFixture $elsewhere
            New-Item -ItemType Directory -Path $devRoot -Force | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $devRoot 'SysAdminSuite') -Target $elsewhere | Out-Null
            $raw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $resolver -DesktopDevRoot $devRoot -RequireCheckout -AsJson
            $code = $LASTEXITCODE
            $global:LASTEXITCODE = 0
            $receipt = $raw | ConvertFrom-Json
            $code | Should -Not -Be 0
            $receipt.canonical_checkout_status | Should -Be 'CONFLICT_UNSAFE_REPARSE_TAG'
            $receipt.canonical_checkout_reparse_classification | Should -Be 'UNSAFE'
            $receipt.canonical_reparse_observed_tags | Should -Contain '0xa0000003'
            $receipt.path_disposition | Should -Be 'CONFLICT'
            $receipt.canonical_git_io_health | Should -Be 'NOT_RUN'
        }

        It 'fails closed when an ancestor of the canonical checkout is a junction' {
            $anchor = Join-Path $TestDrive ('anc-anchor-' + [guid]::NewGuid().ToString('N'))
            $devRoot = Join-Path $TestDrive ('anc-dev-' + [guid]::NewGuid().ToString('N'))
            & $gitFixture (Join-Path $anchor 'SysAdminSuite')
            New-Item -ItemType Junction -Path $devRoot -Target $anchor | Out-Null
            $raw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $resolver -DesktopDevRoot $devRoot -RequireCheckout -AsJson
            $code = $LASTEXITCODE
            $global:LASTEXITCODE = 0
            $receipt = $raw | ConvertFrom-Json
            $code | Should -Not -Be 0
            $receipt.canonical_checkout_status | Should -Be 'CONFLICT_UNSAFE_REPARSE_TAG'
            $receipt.canonical_checkout_reparse_classification | Should -Be 'UNSAFE'
        }

        It 'classifies a healthy path with no reparse points as NONE with an empty tag list' {
            $devRoot = Join-Path $TestDrive ('none-dev-' + [guid]::NewGuid().ToString('N'))
            $fixture = Join-Path $devRoot 'SysAdminSuite'
            & $gitFixture $fixture
            $safety = Test-SasCanonicalReparseSafety -Path $fixture
            $safety.classification | Should -Be 'NONE'
            @($safety.observed_tags).Count | Should -Be 0
        }
    }
}
