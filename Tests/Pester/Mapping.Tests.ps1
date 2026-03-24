#Requires -Modules Pester
<#
.SYNOPSIS
    Offline unit tests for Mapping\ scripts.
    Tests validate parameter contracts, CSV parsing, and dry-run safety.
    No real printers, no AD, no network required.
#>

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workerPath = Join-Path $repoRoot 'Mapping\Workers\Map-MachineWide.NoWinRM.ps1'
$machineWideWorkerPath = Join-Path $repoRoot 'Mapping\Workers\Map-MachineWide.ps1'
$controllerPath = Join-Path $repoRoot 'Mapping\Controllers\Map-Run-Controller.ps1'
$reconPath  = Join-Path $repoRoot 'Mapping\Controllers\RPM-Recon.ps1'

Describe 'Mapping\Config CSV files' {
    It 'host-mappings.csv loads without error and exposes the expected columns' {
        $csvPath = Join-Path $repoRoot 'Mapping\Config\host-mappings.csv'
        $rows = Import-Csv -Path $csvPath -ErrorAction Stop
        $rows | Should Not BeNullOrEmpty

        $cols = $rows[0].PSObject.Properties.Name |
                ForEach-Object { ($_ -replace '^\xEF\xBB\xBF','').TrimStart([char]0xFEFF).Trim() }

        ($cols | Where-Object { $_ -match 'Host$' }).Count | Should BeGreaterThan 0
        (@($cols) -contains 'UNC') | Should Be $true
        (@($cols) -contains 'FriendlyName') | Should Be $true
    }

    It 'wcc_printers.csv loads with at least one row' {
        $csvPath = Join-Path $repoRoot 'Mapping\Config\wcc_printers.csv'
        $printers = @(Import-Csv -Path $csvPath -ErrorAction Stop)
        $printers | Should Not BeNullOrEmpty
        $printers.Count | Should BeGreaterThan 0
    }

    It 'hosts.txt contains non-comment host entries and no blanks' {
        $hostsPath = Join-Path $repoRoot 'Mapping\Config\hosts.txt'
        $hosts = Get-Content -Path $hostsPath | Where-Object { $_ -and $_.Trim() -notlike '#*' }
        $hosts.Count | Should BeGreaterThan 0
        ($hosts | Where-Object { -not $_.Trim() }) | Should BeNullOrEmpty
    }
}

Describe 'Map-MachineWide.NoWinRM.ps1 — script-level checks' {
    It 'Script file exists' {
        $workerPath | Should Exist
    }

    It 'Contains SupportsShouldProcess or -WhatIf support' {
        $content = Get-Content -Path $workerPath -Raw
        $content | Should Match 'SupportsShouldProcess|WhatIf'
    }

    It 'Does not use $Host as a variable name (Bug-Log fix)' {
        $content = Get-Content -Path $workerPath -Raw
        $content | Should Not Match '\$Host\b(?!Name|List|Path|File|Entry|s\b)'
    }

    It 'Uses $PSScriptRoot only inside script body (not in param block)' {
        $lines = Get-Content -Path $workerPath
        $paramBlock = $false
        $foundInParamBlock = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*param\s*\(') { $paramBlock = $true }
            if ($paramBlock -and $line -match '\$PSScriptRoot') { $foundInParamBlock = $true }
            if ($paramBlock -and $line -match '^\s*\)') { $paramBlock = $false }
        }
        $foundInParamBlock | Should Be $false
    }
}

Describe 'RPM-Recon.ps1 — script-level checks' {
    It 'Script file exists' {
        $reconPath | Should Exist
    }

    It 'Requires -HostsPath parameter and resolves worker paths without hard-coding' {
        $content = Get-Content -Path $reconPath -Raw
        $content | Should Match '\$HostsPath'
        $content | Should Match 'Workers'
    }
}

Describe 'Undo/redo integration plumbing' {
    It 'Machine-wide worker exposes undo/redo switches' {
        $content = Get-Content -Path $machineWideWorkerPath -Raw
        $content | Should Match '\$EnableUndoRedo'
        $content | Should Match '\$UndoRedoLogPath'
        $content | Should Match 'Export-UndoRedoSessionSummary'
    }

    It 'Machine-wide worker exposes GUI stop and status hooks' {
        $content = Get-Content -Path $machineWideWorkerPath -Raw
        $content | Should Match '\$StopSignalPath'
        $content | Should Match '\$StatusPath'
        $content | Should Match 'Export-WorkerStatus'
        $content | Should Match 'Test-WorkerStopRequested'
    }

    It 'Controller exposes undo/redo switches, task wrapping hooks, and launcher-based worker argument passthrough' {
        $content = Get-Content -Path $controllerPath -Raw
        $content | Should Match '\$EnableUndoRedo'
        $content | Should Match 'New-ControllerTaskAction'
        $content | Should Match 'UndoRedo\.Controller\.json'
        $content | Should Match '\$WorkerArgumentLine'
        $content | Should Match 'Write-WorkerLauncherScript'
        $content | Should Match 'Start-Worker\.ps1'
    }

    It 'Controller exposes GUI stop and status hooks' {
        $content = Get-Content -Path $controllerPath -Raw
        $content | Should Match '\$StopSignalPath'
        $content | Should Match '\$StatusPath'
        $content | Should Match 'Export-ControllerStatus'
        $content | Should Match 'Test-ControllerStopRequested'
    }
}