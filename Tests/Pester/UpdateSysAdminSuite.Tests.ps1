#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Updater = Join-Path $script:RepoRoot 'Update-SysAdminSuite.ps1'
    $script:BatWrapper = Join-Path $script:RepoRoot 'Update-SysAdminSuite.bat'
    $script:ProgressHelper = Join-Path $script:RepoRoot 'tools\update\Show-SysAdminSuiteProgress.ps1'
    $script:ApprovedHelper = Join-Path $script:RepoRoot 'tools\update\Invoke-SysAdminSuiteUpdate.ps1'
    $script:UpdaterContent = Get-Content -LiteralPath $script:Updater -Raw
    $script:ProgressContent = Get-Content -LiteralPath $script:ProgressHelper -Raw
    $script:ApprovedContent = Get-Content -LiteralPath $script:ApprovedHelper -Raw
}

Describe 'Field tech update entrypoint' {
    It 'exists with a double-click wrapper' {
        $script:Updater | Should -Exist
        $script:BatWrapper | Should -Exist
    }

    It 'parses without PowerShell syntax errors' {
        foreach ($path in @($script:Updater, $script:ProgressHelper)) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }
    }

    It 'shows stage-based progress and plain text step output' {
        $script:ProgressContent | Should -Match 'function\s+Show-SysAdminSuiteStep'
        $script:ProgressContent | Should -Match 'Write-Progress'
        $script:ProgressContent | Should -Match '\[\$Step/\$Total\]'
        $script:ProgressContent | Should -Match 'PercentComplete'
        $script:UpdaterContent | Should -Match 'Show-SysAdminSuiteStep'
        $script:UpdaterContent | Should -Match 'Git network operations stream their own output'
    }

    It 'keeps destructive repair commands scoped to the install root' {
        $script:UpdaterContent | Should -Match '& git -C \$Root @Arguments'
        $script:UpdaterContent | Should -Match "'reset', '--hard', 'origin/main'"
        $script:UpdaterContent | Should -Match "'clean', '-fd'"
        $script:UpdaterContent | Should -Match 'Assert-SafeInstallRoot'
        $script:UpdaterContent | Should -Match 'Refusing to update a drive root'
        $script:UpdaterContent | Should -Match 'Refusing to update protected folder'
        $script:UpdaterContent | Should -Match 'Default install path must end in SysAdminSuite'
        $script:UpdaterContent | Should -Match 'Get-Command git'
        $script:UpdaterContent | Should -Match 'Git is not available on PATH'
        $script:UpdaterContent | Should -Match 'Missing progress helper'
    }

    It 'backs up existing non-git folders instead of overwriting them' {
        $script:UpdaterContent | Should -Match 'function\s+Invoke-BackupNonGitFolder'
        $script:UpdaterContent | Should -Match 'Rename-Item'
        $script:UpdaterContent | Should -Match '\.old\.\$timestamp'
        $script:UpdaterContent | Should -Not -Match 'Remove-Item\s+-LiteralPath\s+\$TargetPath'
    }

    It 'launches only the documented dashboard launcher' {
        $script:UpdaterContent | Should -Match 'START-HERE-SysAdminSuite-Dashboard\.bat'
        $script:UpdaterContent | Should -Match 'Start-Process -FilePath \$dashboard'
    }

    It 'requires an explicit confirmation unless tests or IT pass SkipConfirm' {
        $script:UpdaterContent | Should -Match 'Read-Host'
        $script:UpdaterContent | Should -Match 'Type YES to update'
        $script:UpdaterContent | Should -Match 'SkipConfirm'
        $script:UpdaterContent | Should -Match 'reset --hard and clean -fd'
    }

    It 'preserves the approved update helper as fast-forward only' {
        $script:ApprovedContent | Should -Match "'pull', '--ff-only', 'origin', 'main'"
        $script:ApprovedContent | Should -Not -Match 'reset --hard'
        $script:ApprovedContent | Should -Match 'Refusing to apply update without -Approved'
    }
}
