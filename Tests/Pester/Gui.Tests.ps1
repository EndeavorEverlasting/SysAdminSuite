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
}