#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:sourceModule = Join-Path $script:repoRoot 'scripts\SasAutoLogonSmbStateRecovery.psm1'

    function New-SasStateCaptureFixture {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('sas-state-stderr-' + [guid]::NewGuid().ToString('N'))
        $scripts = Join-Path $root 'scripts'
        New-Item -ItemType Directory -Path $scripts -Force | Out-Null
        Copy-Item -LiteralPath $script:sourceModule -Destination (Join-Path $scripts 'SasAutoLogonSmbStateRecovery.psm1') -Force

        @'
#Requires -Version 5.1
function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30
    )
    [pscustomobject][ordered]@{
        exit_code = 1
        timed_out = $false
        timeout_seconds = $TimeoutSeconds
        output = ''
        error = 'ERROR: The system cannot find the file specified.'
    }
}
Export-ModuleMember -Function Invoke-SasBoundedNative
'@ | Set-Content -LiteralPath (Join-Path $scripts 'SasBoundedNative.psm1') -Encoding UTF8

        return [pscustomobject]@{
            root = $root
            module = (Join-Path $scripts 'SasAutoLogonSmbStateRecovery.psm1')
        }
    }
}

Describe 'AutoLogon SMB state-capture scheduler stderr boundary' {
    It 'uses the bounded native adapter instead of direct schtasks stderr redirection' {
        $text = Get-Content -LiteralPath $script:sourceModule -Raw -Encoding UTF8
        $text | Should -Match 'SasBoundedNative\.psm1'
        $text | Should -Match 'Invoke-SasBoundedNative\s+-FilePath\s+\$schtasksPath'
        $text | Should -Match '\$run\.error'
        $text | Should -Not -Match 'schtasks\.exe"\s+@Arguments\s+2>&1'
    }

    It 'preserves the exact field file-not-found stderr as classifiable data' {
        $fixture = New-SasStateCaptureFixture
        try {
            Remove-Module SasAutoLogonSmbStateRecovery -Force -ErrorAction SilentlyContinue
            Remove-Module SasBoundedNative -Force -ErrorAction SilentlyContinue
            Import-Module $fixture.module -Force -ErrorAction Stop
            $module = Get-Module SasAutoLogonSmbStateRecovery
            $module | Should -Not -BeNullOrEmpty

            $native = & $module {
                Invoke-SasAutoLogonRecoverySchtasksCommand -Arguments @(
                    '/Query','/S','fixture.example.invalid','/TN','missing-task'
                )
            }
            [int]$native.exit_code | Should -Be 1
            [bool]$native.timed_out | Should -BeFalse
            [string]$native.output | Should -Match 'ERROR: The system cannot find the file specified\.'

            $absent = & $module {
                param($Text)
                Test-SasAutoLogonRecoveryTaskAbsentText -Text $Text
            } ([string]$native.output)
            [bool]$absent | Should -BeTrue
        }
        finally {
            Remove-Module SasAutoLogonSmbStateRecovery -Force -ErrorAction SilentlyContinue
            Remove-Module SasBoundedNative -Force -ErrorAction SilentlyContinue
            if ($null -ne $fixture -and (Test-Path -LiteralPath $fixture.root)) {
                Remove-Item -LiteralPath $fixture.root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
