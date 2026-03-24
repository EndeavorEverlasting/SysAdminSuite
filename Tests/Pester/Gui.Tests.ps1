#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:guiPath = Join-Path $script:repoRoot 'GUI\Start-SysAdminSuiteGui.ps1'
}

Describe 'Start-SysAdminSuiteGui.ps1 -- script-level checks' {
    It 'GUI script exists' {
        $script:guiPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:guiPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'Uses Windows Forms and the GUI-safe run control hooks' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'System\.Windows\.Forms'
        $content | Should -Match 'Request-RunStop'
        $content | Should -Match 'Import-RunStatusSnapshot'
        $content | Should -Match 'Import-UndoRedoSession'
        $content | Should -Match 'Replay-UndoRedoAction'
        $content | Should -Match 'Get-KronosClockInfo\.ps1'
    }

    It 'Exposes local worker and controller launch affordances' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Start Local Worker'
        $content | Should -Match 'Start Controller'
        $content | Should -Match 'Worker options passthrough'
        $content | Should -Match 'WorkerArgumentLine'
    }

    It 'Exposes polished run-session affordances for safe operation and operator convenience' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Set-StatusBarText'
        $content | Should -Match 'Update-RunActionState'
        $content | Should -Match 'Load-SafeWorkerExample'
        $content | Should -Match 'Open Session Folder'
        $content | Should -Match 'Copy Status'
        $content | Should -Match 'Copy History'
        $content | Should -Match 'Auto refresh'
        $content | Should -Match 'StatusStrip'
    }

    It 'Uses user-friendly placeholder and guidance text instead of blank panes' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Status file not found yet'
        $content | Should -Match 'Undo/redo history not found yet'
        $content | Should -Match 'Dry-run defaults are preloaded'
        $content | Should -Match 'Launch a run or click Refresh Now'
        $content | Should -Match 'Launch a run or load a history file'
        $content | Should -Match 'Probe live clocks or search a saved inventory CSV'
    }

    It 'Uses GroupBox controls for visual grouping and hierarchy' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'GroupBox'
        $content | Should -Match 'Session File Paths'
        $content | Should -Match 'Run Options'
        $content | Should -Match 'Launch Configuration'
        $content | Should -Match 'Kronos Clock Probe / Inventory'
    }

    It 'Provides browse dialogs for path text fields' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Show-BrowseFileDialog'
        $content | Should -Match 'Show-BrowseFolderDialog'
        $content | Should -Match 'OpenFileDialog'
        $content | Should -Match 'FolderBrowserDialog'
        $content | Should -Match 'btnBrowseStop'
        $content | Should -Match 'btnBrowseStatus'
        $content | Should -Match 'btnBrowseHistory'
        $content | Should -Match 'btnBrowseClockOut'
        $content | Should -Match 'btnBrowseInv'
    }

    It 'Registers keyboard shortcuts via KeyDown with KeyPreview' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'KeyPreview'
        $content | Should -Match 'Add_KeyDown'
        $content | Should -Match 'SuppressKeyPress'
        $content | Should -Match 'Ctrl\+S'
        $content | Should -Match 'F5'
        $content | Should -Match 'Ctrl\+L'
        $content | Should -Match 'Ctrl\+Z'
        $content | Should -Match 'Ctrl\+Y'
        $content | Should -Match 'Ctrl\+E'
    }

    It 'Uses confirmation dialogs before destructive or launch actions' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Confirm Stop'
        $content | Should -Match 'Confirm Worker Launch'
        $content | Should -Match 'Confirm Controller Launch'
        $content | Should -Match 'YesNo'
    }

    It 'Shows labeled section headers above status and history panes' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Run Status'
        $content | Should -Match 'Undo / Redo History'
        $content | Should -Match 'Results'
    }

    It 'Exposes a UTF-8 BOM Sync tab with dual-panel layout' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'UTF-8 BOM Sync'
        $content | Should -Match 'bomTab'
        $content | Should -Match 'lstBomNeed'
        $content | Should -Match 'lstBomHave'
        $content | Should -Match 'Without BOM'
        $content | Should -Match 'With BOM'
    }

    It 'Provides Scan, Sync, Move Right, Move Left, and Move All buttons on the BOM tab' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'btnBomScan'
        $content | Should -Match 'btnBomSync'
        $content | Should -Match 'btnBomMoveRight'
        $content | Should -Match 'btnBomMoveLeft'
        $content | Should -Match 'btnBomMoveAllRight'
    }

    It 'Implements BOM detection and sync helper functions' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'function Test-FileHasBom'
        $content | Should -Match 'function Invoke-BomScan'
        $content | Should -Match 'function Invoke-BomSync'
        $content | Should -Match '0xEF.*0xBB.*0xBF'
    }

    It 'Uses confirmation dialog before applying BOM sync' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Confirm BOM Sync'
    }
}

Describe 'Launch-SysAdminSuite.bat -- launcher checks' {
    BeforeAll {
        $script:launcherPath = Join-Path $script:repoRoot 'Launch-SysAdminSuite.bat'
    }

    It 'Launcher batch file exists at repo root' {
        $script:launcherPath | Should -Exist
    }

    It 'Invokes PowerShell with -STA and the GUI script' {
        $content = Get-Content -Path $script:launcherPath -Raw
        $content | Should -Match '-STA'
        $content | Should -Match 'Start-SysAdminSuiteGui\.ps1'
        $content | Should -Match '-ExecutionPolicy Bypass'
    }
}