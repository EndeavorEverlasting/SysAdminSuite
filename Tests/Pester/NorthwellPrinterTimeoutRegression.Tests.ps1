#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:runnerPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
}

Describe 'Northwell printer proof-timeout regression contract' {
    It 'does not block Status.json proof behind a synchronous gpupdate' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Not -Match "Start-Process\s+-FilePath\s+'gpupdate\.exe'.*-Wait"
        $content | Should -Match 'Verifying the owning HKLM machine-wide registration directly'
    }

    It 'does not depend on LASTEXITCODE after rundll32 PrintUIEntry under Windows PowerShell strict mode' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Not -Match '\$printUiExitCode\s*=\s*\$LASTEXITCODE'
        $content | Should -Match 'registry proof will determine success'
    }

    It 'captures agent and scheduled-task diagnostics before classifying a proof timeout' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'Get-Content -LiteralPath \$remoteLogAdmin -Tail 20'
        $content | Should -Match "Stage 'TimeoutQuery'"
        $content | Should -Match "'/V'"
        $content | Should -Match "'/FO','LIST'"
    }
}
