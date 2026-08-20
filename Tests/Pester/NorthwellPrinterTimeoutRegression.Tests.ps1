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

    It 'recognizes the per-machine connection identity from the HKLM child key when Printer value metadata is absent' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'ConvertFrom-MachineWideConnectionKeyName'
        $content | Should -Match 'PSChildName'
        $content | Should -Match 'RawConnectionKeys'
        $content | Should -Not -Match 'if\s*\(\$item\.Server\s+-and\s+\$item\.Printer\)'
    }

    It 'uses the registry Printer value directly when it is already a complete UNC path' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match '\$printerValue\s+-match'
        $content | Should -Match '\$candidate\s*=\s*\$printerValue\.ToLowerInvariant\(\)'
        $content | Should -Match '\$printerValue\.TrimStart'
    }

    It 'captures agent and scheduled-task diagnostics before classifying a proof timeout' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'Get-Content -LiteralPath \$remoteLogAdmin -Tail 20'
        $content | Should -Match "Stage 'TimeoutQuery'"
        $content | Should -Match "'/V'"
        $content | Should -Match "'/FO','LIST'"
    }
}
