#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:batchProbe = Join-Path $script:repoRoot 'survey\sas-network-batch-probe.ps1'
    $script:universalLauncher = Join-Path $script:repoRoot 'scripts\Invoke-SasUniversalField.ps1'
    $script:universalInstaller = Join-Path $script:repoRoot 'scripts\Install-SasUniversalFieldLauncher.ps1'
}

Describe 'SysAdminSuite bounded batch network probe' {
    It 'keeps the helper, universal front door, and installer parseable' {
        foreach ($path in @($script:batchProbe, $script:universalLauncher, $script:universalInstaller)) {
            $path | Should -Exist
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It 'materializes approved target intake relative to the repo instead of caller cwd' {
        $content = Get-Content -LiteralPath $script:batchProbe -Raw
        $content | Should -Match ([regex]::Escape('$repoRoot = Split-Path -Parent $PSScriptRoot'))
        $content | Should -Match ([regex]::Escape("'targets\local'"))
        $content | Should -Match 'New-Item -ItemType Directory'
        $content | Should -Match 'Set-Content -LiteralPath \$targetFile'
        $content | Should -Match 'Remove-Item -LiteralPath \$targetFile'
        $content | Should -Match 'finally'
    }

    It 'uses the canonical low-noise preflight with 135 and 445 defaults' {
        $content = Get-Content -LiteralPath $script:batchProbe -Raw
        $content | Should -Match ([regex]::Escape("'survey\sas-network-preflight.ps1'"))
        $content | Should -Match '\[int\[\]\]\$Ports = @\(135, 445\)'
        $content | Should -Match ([regex]::Escape('& $preflight -TargetFile $targetFile -Ports $Ports -PolicyProfile $PolicyProfile'))
    }

    It 'accepts only target shapes that survive canonical preflight intake' {
        $content = Get-Content -LiteralPath $script:batchProbe -Raw
        $content | Should -Match ([regex]::Escape("'^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$'"))
        $content | Should -Match ([regex]::Escape("'^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$'"))
        $content | Should -Match ([regex]::Escape("'^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$'"))
        $content | Should -Match 'HOST01'
        $content | Should -Not -Match 'for example HOST1,'
    }

    It 'routes sas network probe through the batch helper while preserving one-target readiness' {
        $content = Get-Content -LiteralPath $script:universalLauncher -Raw
        $content | Should -Match ([regex]::Escape('sas network probe HOST01 HOST02 ...'))
        $content | Should -Match ([regex]::Escape('Join-Path $controllerRoot ''survey\sas-network-batch-probe.ps1'''))
        $content | Should -Match ([regex]::Escape('Batch network probe for $($targets.Count) explicit targets'))
        $content | Should -Match ([regex]::Escape('Network readiness probe for $($actualArgs[0])'))
        $content | Should -Match ([regex]::Escape('& $batchProbe -Target $targets'))
        $content | Should -Match 'Run ''sas refresh'' on Guest/Internet'
    }

    It 'refuses to install a launcher that would point at a stale legacy controller without the batch runtime' {
        $content = Get-Content -LiteralPath $script:universalInstaller -Raw
        $content | Should -Match ([regex]::Escape("'survey\sas-network-batch-probe.ps1'"))
        $content | Should -Match ([regex]::Escape("'survey\sas-network-preflight.ps1'"))
        $content | Should -Match 'MACHINE_RUNTIME_REFRESH_REQUIRED'
        $content | Should -Match 'SasLowNoisePolicy.psm1'
        $content | Should -Match 'SasPortFallbackDecision.psm1'
        $content | Should -Match 'Render-SasEnglishReport.ps1'
    }
}
