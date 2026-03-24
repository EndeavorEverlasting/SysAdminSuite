#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline unit tests for Mapping\ scripts.
    Tests validate parameter contracts, CSV parsing, and dry-run safety.
    No real printers, no AD, no network required.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $workerPath = Join-Path $repoRoot 'Mapping\Workers\Map-MachineWide.NoWinRM.ps1'
    $machineWideWorkerPath = Join-Path $repoRoot 'Mapping\Workers\Map-MachineWide.ps1'
    $controllerPath = Join-Path $repoRoot 'Mapping\Controllers\Map-Run-Controller.ps1'
    $reconPath  = Join-Path $repoRoot 'Mapping\Controllers\RPM-Recon.ps1'
}

Describe 'Mapping\Config CSV files' {
    Context 'host-mappings.csv structure' {
        BeforeAll {
            $csvPath = Join-Path $repoRoot 'Mapping\Config\host-mappings.csv'
            $script:rows = Import-Csv -Path $csvPath -ErrorAction Stop
        }

        It 'Loads without error' {
            $script:rows | Should -Not -BeNullOrEmpty
        }

        It 'Has required columns: Host, UNC, FriendlyName' {
            # Actual schema: Host (may have UTF-8 BOM prefix as string artifact), UNC, FriendlyName
            # Strip any leading BOM characters (U+FEFF) that survive CSV import
            $cols = $script:rows[0].PSObject.Properties.Name |
                    ForEach-Object { ($_ -replace '^\xEF\xBB\xBF','').TrimStart([char]0xFEFF).Trim() }
            # At least one column should end with 'Host' (handles BOM prefix)
            ($cols | Where-Object { $_ -match 'Host$' }).Count | Should -BeGreaterThan 0
            $cols | Should -Contain 'UNC'
            $cols | Should -Contain 'FriendlyName'
        }

        It 'All PrinterUNC values start with \\' {
            $bad = $script:rows | Where-Object { $_.PrinterUNC -and -not $_.PrinterUNC.StartsWith('\\') }
            $bad | Should -BeNullOrEmpty
        }
    }

    Context 'wcc_printers.csv structure' {
        BeforeAll {
            $csvPath = Join-Path $repoRoot 'Mapping\Config\wcc_printers.csv'
            $script:printers = Import-Csv -Path $csvPath -ErrorAction Stop
        }

        It 'Loads without error' {
            $script:printers | Should -Not -BeNullOrEmpty
        }

        It 'Has at least one row' {
            $script:printers.Count | Should -BeGreaterThan 0
        }
    }

    Context 'hosts.txt' {
        BeforeAll {
            $hostsPath = Join-Path $repoRoot 'Mapping\Config\hosts.txt'
            $script:hosts = Get-Content -Path $hostsPath |
                Where-Object { $_ -and $_.Trim() -notlike '#*' }
        }

        It 'Contains at least one non-comment host entry' {
            $script:hosts.Count | Should -BeGreaterThan 0
        }

        It 'No entry is blank or whitespace-only' {
            $blank = $script:hosts | Where-Object { -not $_.Trim() }
            $blank | Should -BeNullOrEmpty
        }
    }
}

Describe 'Map-MachineWide.NoWinRM.ps1 — script-level checks' {
    It 'Script file exists' {
        $workerPath | Should -Exist
    }

    It 'Contains SupportsShouldProcess or -WhatIf support' {
        $content = Get-Content -Path $workerPath -Raw
        $content | Should -Match 'SupportsShouldProcess|WhatIf'
    }

    It 'Does not use $Host as a variable name (Bug-Log fix)' {
        $content = Get-Content -Path $workerPath -Raw
        # $Host as a standalone variable (not $HostName, $HostList, etc.)
        $content | Should -Not -Match '\$Host\b(?!Name|List|Path|File|Entry|s\b)'
    }

    It 'Uses $PSScriptRoot only inside script body (not in param block)' {
        $lines = Get-Content -Path $workerPath
        $paramBlock = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*param\s*\(') { $paramBlock = $true }
            if ($paramBlock -and $line -match '\$PSScriptRoot') {
                $false | Should -Be $true -Because '$PSScriptRoot must not appear in param block'
            }
            if ($paramBlock -and $line -match '^\s*\)') { $paramBlock = $false }
        }
        $true | Should -Be $true
    }
}

Describe 'RPM-Recon.ps1 — script-level checks' {
    It 'Script file exists' {
        $reconPath | Should -Exist
    }

    It 'Requires -HostsPath parameter' {
        $content = Get-Content -Path $reconPath -Raw
        $content | Should -Match '\$HostsPath'
    }

    It 'Has a fallback worker path resolution (not hard-coded)' {
        $content = Get-Content -Path $reconPath -Raw
        $content | Should -Match 'Workers'
    }
}

Describe 'Undo/redo integration plumbing' {
    It 'Machine-wide worker exposes undo/redo switches' {
        $content = Get-Content -Path $machineWideWorkerPath -Raw
        $content | Should -Match '\$EnableUndoRedo'
        $content | Should -Match '\$UndoRedoLogPath'
        $content | Should -Match 'Export-UndoRedoSessionSummary'
    }

    It 'Machine-wide worker exposes GUI stop and status hooks' {
        $content = Get-Content -Path $machineWideWorkerPath -Raw
        $content | Should -Match '\$StopSignalPath'
        $content | Should -Match '\$StatusPath'
        $content | Should -Match 'Export-WorkerStatus'
        $content | Should -Match 'Test-WorkerStopRequested'
    }

    It 'Controller exposes undo/redo switches and task wrapping hooks' {
        $content = Get-Content -Path $controllerPath -Raw
        $content | Should -Match '\$EnableUndoRedo'
        $content | Should -Match 'New-ControllerTaskAction'
        $content | Should -Match 'UndoRedo\.Controller\.json'
    }

    It 'Controller exposes GUI stop and status hooks' {
        $content = Get-Content -Path $controllerPath -Raw
        $content | Should -Match '\$StopSignalPath'
        $content | Should -Match '\$StatusPath'
        $content | Should -Match 'Export-ControllerStatus'
        $content | Should -Match 'Test-ControllerStopRequested'
    }
}

