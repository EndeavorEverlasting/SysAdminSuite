#Requires -Modules Pester
<#
.SYNOPSIS
    Offline unit tests for Mapping\ scripts.
    Tests validate parameter contracts, CSV parsing, and dry-run safety.
    No real printers, no AD, no network required.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:workerPath = Join-Path $script:repoRoot 'Mapping\Workers\Map-MachineWide.NoWinRM.ps1'
    $script:machineWideWorkerPath = Join-Path $script:repoRoot 'Mapping\Workers\Map-MachineWide.ps1'
    $script:controllerPath = Join-Path $script:repoRoot 'Mapping\Controllers\Map-Run-Controller.ps1'
    $script:reconPath  = Join-Path $script:repoRoot 'Mapping\Controllers\RPM-Recon.ps1'
}

Describe 'Mapping\Config CSV files' {
    It 'host-mappings.csv loads without error and exposes the expected columns' {
        $csvPath = Join-Path $script:repoRoot 'Mapping\Config\host-mappings.csv'
        $rows = Import-Csv -Path $csvPath -ErrorAction Stop
        $rows | Should -Not -BeNullOrEmpty

        $cols = $rows[0].PSObject.Properties.Name |
                ForEach-Object { ($_ -replace '^\xEF\xBB\xBF','').TrimStart([char]0xFEFF).Trim() }

        ($cols | Where-Object { $_ -match 'Host$' }).Count | Should -BeGreaterThan 0
        (@($cols) -contains 'UNC') | Should -Be $true
        (@($cols) -contains 'FriendlyName') | Should -Be $true
    }

    It 'wcc_printers.csv loads with at least one row' {
        $csvPath = Join-Path $script:repoRoot 'Mapping\Config\wcc_printers.csv'
        $printers = @(Import-Csv -Path $csvPath -ErrorAction Stop)
        $printers | Should -Not -BeNullOrEmpty
        $printers.Count | Should -BeGreaterThan 0
    }

    It 'hosts.txt contains non-comment host entries and no blanks' {
        $hostsPath = Join-Path $script:repoRoot 'Mapping\Config\hosts.txt'
        $hosts = Get-Content -Path $hostsPath | Where-Object { $_ -and $_.Trim() -notlike '#*' }
        $hosts.Count | Should -BeGreaterThan 0
        ($hosts | Where-Object { -not $_.Trim() }) | Should -BeNullOrEmpty
    }
}

Describe 'Map-MachineWide.NoWinRM.ps1 -- script-level checks' {
    It 'Script file exists' {
        $script:workerPath | Should -Exist
    }

    It 'Contains SupportsShouldProcess or -WhatIf support' {
        $content = Get-Content -Path $script:workerPath -Raw
        $content | Should -Match 'SupportsShouldProcess|WhatIf'
    }

    It 'Does not use $Host as a variable name (Bug-Log fix)' {
        $content = Get-Content -Path $script:workerPath -Raw
        $content | Should -Not -Match '\$Host\b(?!Name|List|Path|File|Entry|s\b)'
    }

    It 'Uses $PSScriptRoot only inside script body (not in param block)' {
        $lines = Get-Content -Path $script:workerPath
        $paramBlock = $false
        $foundInParamBlock = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*param\s*\(') { $paramBlock = $true }
            if ($paramBlock -and $line -match '\$PSScriptRoot') { $foundInParamBlock = $true }
            if ($paramBlock -and $line -match '^\s*\)') { $paramBlock = $false }
        }
        $foundInParamBlock | Should -Be $false
    }
}

Describe 'RPM-Recon.ps1 -- script-level checks' {
    It 'Script file exists' {
        $script:reconPath | Should -Exist
    }

    It 'Requires -HostsPath parameter and resolves worker paths without hard-coding' {
        $content = Get-Content -Path $script:reconPath -Raw
        $content | Should -Match '\$HostsPath'
        $content | Should -Match 'Workers'
    }
}

Describe 'Map-MachineWide.ps1 -- HTML report output' {
    It 'Generates HTML report via ConvertTo-SuiteHtml' {
        $content = Get-Content -Path $script:machineWideWorkerPath -Raw
        $content | Should -Match 'ConvertTo-SuiteHtml'
    }
}

Describe 'Undo/redo integration plumbing' {
    It 'Machine-wide worker exposes undo/redo switches' {
        $content = Get-Content -Path $script:machineWideWorkerPath -Raw
        $content | Should -Match '\$EnableUndoRedo'
        $content | Should -Match '\$UndoRedoLogPath'
        $content | Should -Match 'Export-UndoRedoSessionSummary'
    }

    It 'Machine-wide worker exposes GUI stop and status hooks' {
        $content = Get-Content -Path $script:machineWideWorkerPath -Raw
        $content | Should -Match '\$StopSignalPath'
        $content | Should -Match '\$StatusPath'
        $content | Should -Match 'Export-WorkerStatus'
        $content | Should -Match 'Test-WorkerStopRequested'
    }

    It 'Controller exposes undo/redo switches, task wrapping hooks, and launcher-based worker argument passthrough' {
        $content = Get-Content -Path $script:controllerPath -Raw
        $content | Should -Match '\$EnableUndoRedo'
        $content | Should -Match 'New-ControllerTaskAction'
        $content | Should -Match 'UndoRedo\.Controller\.json'
        $content | Should -Match '\$WorkerArgumentLine'
        $content | Should -Match 'Write-WorkerLauncherScript'
        $content | Should -Match 'Start-Worker\.ps1'
    }

    It 'Controller exposes GUI stop and status hooks' {
        $content = Get-Content -Path $script:controllerPath -Raw
        $content | Should -Match '\$StopSignalPath'
        $content | Should -Match '\$StatusPath'
        $content | Should -Match 'Export-ControllerStatus'
        $content | Should -Match 'Test-ControllerStopRequested'
    }

    It 'Controller keeps session-scoped artifacts together for GUI-driven runs' {
        $content = Get-Content -Path $script:controllerPath -Raw
        $content | Should -Match '\$SessionRoot'
        $content | Should -Match 'Controller\.Status\.json'
        $content | Should -Match 'Stop\.json'
        $content | Should -Match 'Join-Path \$SessionRoot \$Computer'
        $content | Should -Match 'Worker\.Status\.json'
    }

    It 'Machine-wide worker defaults to an output root and emits lifecycle status for the GUI' {
        $content = Get-Content -Path $script:machineWideWorkerPath -Raw
        $content | Should -Match '\$OutputRoot = ''C:\\ProgramData\\SysAdminSuite\\Mapping'''
        $content | Should -Match 'Export-WorkerStatus -State ''Running'' -Stage ''Startup'''
        $content | Should -Match 'Export-WorkerStatus -State ''Completed'' -Stage ''ListOnly'''
        $content | Should -Match 'Export-WorkerStatus -State .* -Stage ''Complete'''
        $content | Should -Match '\$script:stopRequested'
        $content | Should -Match '''Stopped'''
        $content | Should -Match '''Completed'''
    }
}