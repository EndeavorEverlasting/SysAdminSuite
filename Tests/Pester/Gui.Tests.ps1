#Requires -Modules Pester

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$guiPath = Join-Path $repoRoot 'GUI\Start-SysAdminSuiteGui.ps1'

Describe 'Start-SysAdminSuiteGui.ps1 — script-level checks' {
    It 'GUI script exists' {
        $guiPath | Should Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It 'Uses Windows Forms and the GUI-safe run control hooks' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'System\.Windows\.Forms'
        $content | Should Match 'Request-RunStop'
        $content | Should Match 'Import-RunStatusSnapshot'
        $content | Should Match 'Import-UndoRedoSession'
        $content | Should Match 'Replay-UndoRedoAction'
        $content | Should Match 'Get-KronosClockInfo\.ps1'
    }

    It 'Exposes local worker and controller launch affordances' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'Start Local Worker'
        $content | Should Match 'Start Controller'
        $content | Should Match 'Worker options passthrough'
        $content | Should Match 'WorkerArgumentLine'
    }

    It 'Exposes polished run-session affordances for safe operation and operator convenience' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'Set-StatusBarText'
        $content | Should Match 'Update-RunActionState'
        $content | Should Match 'Load-SafeWorkerExample'
        $content | Should Match 'Open Session Folder'
        $content | Should Match 'Copy Status'
        $content | Should Match 'Copy History'
        $content | Should Match 'Auto refresh'
        $content | Should Match 'StatusStrip'
    }

    It 'Uses user-friendly placeholder and guidance text instead of blank panes' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'Status file not found yet'
        $content | Should Match 'Undo/redo history not found yet'
        $content | Should Match 'Dry-run defaults are preloaded'
        $content | Should Match 'Launch a run or click Refresh Now'
        $content | Should Match 'Launch a run or load a history file'
        $content | Should Match 'Probe live clocks or search a saved inventory CSV'
    }

    It 'Uses GroupBox controls for visual grouping and hierarchy' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'GroupBox'
        $content | Should Match 'Session File Paths'
        $content | Should Match 'Run Options'
        $content | Should Match 'Launch Configuration'
        $content | Should Match 'Kronos Clock Probe / Inventory'
    }

    It 'Provides browse dialogs for path text fields' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'Show-BrowseFileDialog'
        $content | Should Match 'Show-BrowseFolderDialog'
        $content | Should Match 'OpenFileDialog'
        $content | Should Match 'FolderBrowserDialog'
        $content | Should Match 'btnBrowseStop'
        $content | Should Match 'btnBrowseStatus'
        $content | Should Match 'btnBrowseHistory'
        $content | Should Match 'btnBrowseClockOut'
        $content | Should Match 'btnBrowseInv'
    }

    It 'Registers keyboard shortcuts via KeyDown with KeyPreview' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'KeyPreview'
        $content | Should Match 'Add_KeyDown'
        $content | Should Match 'SuppressKeyPress'
        $content | Should Match 'Ctrl\+S'
        $content | Should Match 'F5'
        $content | Should Match 'Ctrl\+L'
        $content | Should Match 'Ctrl\+Z'
        $content | Should Match 'Ctrl\+Y'
        $content | Should Match 'Ctrl\+E'
    }

    It 'Uses confirmation dialogs before destructive or launch actions' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'Confirm Stop'
        $content | Should Match 'Confirm Worker Launch'
        $content | Should Match 'Confirm Controller Launch'
        $content | Should Match 'YesNo'
    }

    It 'Shows labeled section headers above status and history panes' {
        $content = Get-Content -Path $guiPath -Raw
        $content | Should Match 'Run Status'
        $content | Should Match 'Undo / Redo History'
        $content | Should Match 'Results'
    }
}