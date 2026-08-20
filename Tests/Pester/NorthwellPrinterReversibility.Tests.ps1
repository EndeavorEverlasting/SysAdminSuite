#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:corePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
    $script:statePath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:mapWrapperPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:unmapWrapperPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterUnmapping.ps1'
    $script:startPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:batchPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterBatch.ps1'
    $script:undoPath = Join-Path $script:repoRoot 'mapping\Undo-NorthwellPrinterChange.ps1'
    $script:authorityPath = Join-Path $script:repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
    $script:mapCmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
    $script:unmapCmdPath = Join-Path $script:repoRoot 'Unmap-NorthwellPrinter-SystemWide.cmd'
    $script:undoCmdPath = Join-Path $script:repoRoot 'Undo-LatestNorthwellPrinterChange.cmd'
    $script:managerCmdPath = Join-Path $script:repoRoot 'Manage-NorthwellPrinters.cmd'
    $script:batchCmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinters-Batch.cmd'
    $script:batchExamplePath = Join-Path $script:repoRoot 'mapping\Examples\NorthwellPrinterBatch.example.csv'
    Import-Module $script:corePath -Force
}

Describe 'Northwell reversible desired-state contract' {
    It 'keeps old batch files mapping by default and accepts explicit unmap rows' {
        $resolver = { param($queue,$server) "\\$server\$queue" }
        $legacy = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows @(
            [pscustomobject]@{ ComputerName='PC001';PrintServer='PRINT01';QueueName='QUEUE01' }
        ) -PrinterResolver $resolver)
        $legacy[0].Action | Should -Be 'Map'

        $mixed = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows @(
            [pscustomobject]@{ Action='Map';ComputerName='PC001';PrintServer='PRINT01';QueueName='QUEUE01' },
            [pscustomobject]@{ Action='Unmap';ComputerName='PC002';PrintServer='PRINT02';QueueName='QUEUE02' }
        ) -PrinterResolver $resolver)
        $mixed.Count | Should -Be 2
        $mixed[0].Action | Should -Be 'Map'
        $mixed[1].Action | Should -Be 'Unmap'
    }

    It 'rejects unsafe batch actions before printer resolution' {
        $resolver = { throw 'resolver must not run' }
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows @(
            [pscustomobject]@{ Action='DeleteEverything';ComputerName='PC001';PrintServer='PRINT01';QueueName='QUEUE01' }
        ) -PrinterResolver $resolver -ShapeOnly } | Should -Throw '*Action must be Map or Unmap*'
    }

    It 'proves requested queues present for mapping' {
        $status = [pscustomobject]@{
            Success=$true; Identity='NT AUTHORITY\SYSTEM'; DesiredState='Present'
            MachineWideUNC=@('\\print01\queue01'); Missing=@(); StillPresent=@()
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINT01\QUEUE01') -DesiredState Present } | Should -Not -Throw
    }

    It 'proves requested queues absent for unmapping' {
        $status = [pscustomobject]@{
            Success=$true; Identity='NT AUTHORITY\SYSTEM'; DesiredState='Absent'
            MachineWideUNC=@('\\print01\other'); Missing=@(); StillPresent=@()
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINT01\QUEUE01') -DesiredState Absent } | Should -Not -Throw
    }

    It 'rejects a still-present queue when absence is requested' {
        $status = [pscustomobject]@{
            Success=$true; Identity='NT AUTHORITY\SYSTEM'; DesiredState='Absent'
            MachineWideUNC=@('\\print01\queue01'); Missing=@(); StillPresent=@('\\print01\queue01')
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINT01\QUEUE01') -DesiredState Absent } | Should -Throw '*did not prove requested machine-wide connection removal*'
    }
}

Describe 'Canonical reversible printer engine contract' {
    It 'pairs PrintUIEntry add and delete while preserving system-wide proof' {
        $text = Get-Content -LiteralPath $script:statePath -Raw
        $text | Should -Match "'/ga'"
        $text | Should -Match "'/gd'"
        $text | Should -Match 'DesiredState'
        $text | Should -Match 'BeforeMachineWideUNC'
        $text | Should -Match 'ChangedPrinters'
        $text | Should -Match 'AlreadyDesiredPrinters'
        $text | Should -Match 'UndoPlan\.json'
        $text | Should -Match 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Print\\Connections'
        $text | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $text | Should -Not -Match 'Remove-Printer'
        $text | Should -Not -Match 'PrintTestPage'
        $text | Should -Not -Match 'gpupdate\.exe'
    }

    It 'requires print-server DNS for mapping but not for known-UNC unmapping' {
        $text = Get-Content -LiteralPath $script:statePath -Raw
        $text | Should -Match "if \(\$DesiredState -eq 'Present'\)"
        $text | Should -Match 'removing a stale machine-wide connection must remain possible'
        $text | Should -Match "GetHostAddresses\(\$server\)"
    }

    It 'records only observed transitions as inverse work' {
        $text = Get-Content -LiteralPath $script:statePath -Raw
        $text | Should -Match 'Before -notcontains \$_ -and \$After -contains \$_'
        $text | Should -Match 'Before -contains \$_ -and \$After -notcontains \$_'
        $text | Should -Match 'if \(\$changed\.Count -eq 0\) \{ continue \}'
        $text | Should -Match 'UndoDesiredState'
    }

    It 'keeps compatibility wrappers symmetric' {
        (Get-Content -LiteralPath $script:mapWrapperPath -Raw) | Should -Match "DesiredState = 'Present'"
        (Get-Content -LiteralPath $script:unmapWrapperPath -Raw) | Should -Match "DesiredState = 'Absent'"
    }
}

Describe 'Northwell network-angle authority contract' {
    BeforeEach {
        $script:oldGuardConfig = $env:SAS_NETWORK_GUARD_CONFIG
        $env:SAS_NETWORK_GUARD_CONFIG = Join-Path ([System.IO.Path]::GetTempPath()) 'sas-network-guard-definitely-missing.json'
        Import-Module $script:authorityPath -Force
    }
    AfterEach {
        $env:SAS_NETWORK_GUARD_CONFIG = $script:oldGuardConfig
    }

    It 'accepts WAB Wi-Fi directly' {
        $authority = Get-SasNorthwellNetworkAuthority -Ssid 'NSLIJHS-WAB-TEST' -NetworkText '' -ConnectionProfiles @()
        $authority.Allowed | Should -BeTrue
        $authority.Route | Should -Be 'WAB_WIFI'
    }

    It 'accepts a DomainAuthenticated Ethernet controller without exact IP policy' {
        $profile = [pscustomobject]@{ InterfaceAlias='Ethernet 4';NetworkCategory='DomainAuthenticated';IPv4Connectivity='Internet';IPv6Connectivity='NoTraffic';InterfaceIndex=8 }
        $resolver = { param($index) @([pscustomobject]@{ IPAddress='10.20.30.40' }) }
        $authority = Get-SasNorthwellNetworkAuthority -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles @($profile) -AddressResolver $resolver
        $authority.Allowed | Should -BeTrue
        $authority.Route | Should -Be 'DOMAIN_AUTHENTICATED_NON_WIFI'
    }

    It 'accepts an authenticated VPN regardless of adapter product name' {
        $profile = [pscustomobject]@{ InterfaceAlias='Corporate Tunnel Adapter';NetworkCategory='DomainAuthenticated';IPv4Connectivity='Internet';IPv6Connectivity='NoTraffic';InterfaceIndex=22 }
        $resolver = { param($index) @([pscustomobject]@{ IPAddress='10.40.50.60' }) }
        $authority = Get-SasNorthwellNetworkAuthority -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles @($profile) -AddressResolver $resolver
        $authority.Allowed | Should -BeTrue
        $authority.Route | Should -Be 'DOMAIN_AUTHENTICATED_NON_WIFI'
    }

    It 'rejects guest-only network posture' {
        $profile = [pscustomobject]@{ InterfaceAlias='Wi-Fi';NetworkCategory='Public';IPv4Connectivity='Internet';IPv6Connectivity='NoTraffic';InterfaceIndex=5 }
        $authority = Get-SasNorthwellNetworkAuthority -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles @($profile) -AddressResolver { @() }
        $authority.Allowed | Should -BeFalse
        $authority.Route | Should -Be 'UNAUTHORIZED'
    }
}

Describe 'Technician all-angle entrypoints' {
    It 'routes quick map and unmap through the same interactive state surface' {
        $start = Get-Content -LiteralPath $script:startPath -Raw
        $start | Should -Match "ValidateSet\('Map','Unmap'\)"
        $start | Should -Match 'Invoke-NorthwellPrinterState\.ps1'
        $start | Should -Match 'SasNorthwellNetworkAuthority\.psm1'
        $start | Should -Match 'WAB, hardwire, or authenticated VPN'
    }

    It 'provides portable one-click map unmap undo and manager launchers' {
        foreach ($path in @($script:mapCmdPath,$script:unmapCmdPath,$script:undoCmdPath,$script:managerCmdPath,$script:batchCmdPath)) {
            Test-Path -LiteralPath $path | Should -BeTrue
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match '%~dp0'
            $text | Should -Not -Match '(?i)C:\\Users\\'
        }
        (Get-Content -LiteralPath $script:unmapCmdPath -Raw) | Should -Match 'Start-NorthwellPrinterMapping\.ps1.*-Action Unmap'
        (Get-Content -LiteralPath $script:undoCmdPath -Raw) | Should -Match 'Undo-NorthwellPrinterChange\.ps1'
    }

    It 'keeps the manager menu deterministic instead of IF command fall-through' {
        $text = Get-Content -LiteralPath $script:managerCmdPath -Raw
        $text | Should -Match 'goto map'
        $text | Should -Match ':unmap'
        $text | Should -Match ':undo'
        $text | Should -Not -Match 'if /i .*call .* & goto menu'
    }

    It 'requires explicit confirmations for batch and undo mutation' {
        $batch = Get-Content -LiteralPath $script:batchPath -Raw
        $undo = Get-Content -LiteralPath $script:undoPath -Raw
        $batch | Should -Match "Read-Host 'Type APPLY to execute this exact map/unmap batch plan'"
        $undo | Should -Match "Read-Host 'Type UNDO to execute this exact inverse plan'"
        $batch | Should -Match 'SasNorthwellNetworkAuthority\.psm1'
        $undo | Should -Match 'SasNorthwellNetworkAuthority\.psm1'
    }

    It 'tracks only a synthetic reversible batch example' {
        $rows = @(Import-Csv -LiteralPath $script:batchExamplePath)
        $rows.Count | Should -Be 1
        $rows[0].Action | Should -Be 'Map'
        $rows[0].ComputerName | Should -Be 'REPLACE-WITH-PC-HOSTNAME'
        $rows[0].PrintServer | Should -Be 'REPLACE-WITH-PRINT-SERVER'
        $rows[0].QueueName | Should -Be 'REPLACE-WITH-QUEUE-NAME'
    }
}
