#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Unit tests for PowerComfort backup/revert helpers (no elevation, no powercfg).
#>

Describe 'PowerComfort import GUID parsing' {
    It 'Extracts GUID from standard powercfg import success line' {
        $t = @"
Imported Power Scheme Successfully. GUID: c93c323d-a8bc-4aff-9c32-1cba420d4c12

"@
        $t | Should -Match '(?i)GUID:\s*([a-f0-9-]{36})'
        $m = [regex]::Match($t, '(?i)GUID:\s*([a-f0-9-]{36})')
        $m.Groups[1].Value | Should -Be 'c93c323d-a8bc-4aff-9c32-1cba420d4c12'
    }
}

Describe 'PowerComfort backup meta shape' {
    It 'Round-trips version 1 meta with schemes array' {
        $meta = [pscustomobject]@{
            version                      = 1
            computerName                 = 'TESTHOST'
            exportedAt                   = '2026-04-17 12:00:00'
            activeSchemeGuid             = '381b4222-f694-41f0-9685-ff5bb260df2e'
            hibernateFileDisabledByApply = $false
            schemes                      = @(
                [pscustomobject]@{
                    guid = '381b4222-f694-41f0-9685-ff5bb260df2e'
                    name = 'Balanced'
                    file = '381b4222-f694-41f0-9685-ff5bb260df2e.pow'
                }
            )
        }
        $json = $meta | ConvertTo-Json -Depth 5
        $round = $json | ConvertFrom-Json
        $round.version | Should -Be 1
        @($round.schemes).Count | Should -Be 1
        $round.schemes[0].file | Should -Match '\.pow$'
    }
}
