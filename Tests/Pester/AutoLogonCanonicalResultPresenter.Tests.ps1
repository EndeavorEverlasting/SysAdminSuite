#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:presenter = Join-Path $script:repoRoot 'scripts\Show-SasAutoLogonResult.ps1'
    $script:fixture = Join-Path $script:repoRoot 'Tests\Fixtures\autologon-result-inspector\deployment-success'
}
Describe 'AutoLogon public-safe result presenter' {
    It 'parses under Windows PowerShell without errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:presenter, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'presents deployment success as runtime pending without paths or identities' {
        $runRoot = Join-Path $script:repoRoot ('survey\output\runs\autologon-proof\autologon-deploy-presenter-' + [guid]::NewGuid().ToString('N'))
        try {
            Copy-Item -LiteralPath $script:fixture -Destination $runRoot -Recurse -Force
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:presenter -RunRoot $runRoot 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $output | Should -Match 'Classification: DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING'
            $output | Should -Match 'Digest continuity: VERIFIED'
            $output | Should -Match 'Repo-owned remnants: 0'
            $output | Should -Match 'Runtime proof pending: True'
            $output | Should -Not -Match [regex]::Escape($runRoot)
            $output | Should -Not -Match 'autologon-deploy-20260722-120000-1234abcd'
            $output | Should -Not -Match 'target_binding_sha256'
        }
        finally {
            if (Test-Path -LiteralPath $runRoot) { Remove-Item -LiteralPath $runRoot -Recurse -Force }
        }
    }

    It 'fails closed when source and receipt digest continuity disagree' {
        $runRoot = Join-Path $script:repoRoot ('survey\output\runs\autologon-proof\autologon-deploy-presenter-' + [guid]::NewGuid().ToString('N'))
        try {
            Copy-Item -LiteralPath $script:fixture -Destination $runRoot -Recurse -Force
            $receiptPath = Join-Path $runRoot 'artifacts\autologon_proof_receipt.json'
            $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $receipt.source_evidence_sha256 = '9999999999999999999999999999999999999999999999999999999999999999'
            $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:presenter -RunRoot $runRoot 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 22
            $output | Should -Match 'Classification: EVIDENCE_INVALID'
            $output | Should -Match 'Digest continuity: FAILED'
            $output | Should -Match 'proof receipt digest continuity failed'
        }
        finally {
            if (Test-Path -LiteralPath $runRoot) { Remove-Item -LiteralPath $runRoot -Recurse -Force }
        }
    }
}
