#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:modulePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
    $script:runnerPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterState.ps1'
    $script:mapWrapperPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:unmapWrapperPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterUnmapping.ps1'
    $script:interactivePath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:batchPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterBatch.ps1'
    $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
    $script:unmapCmdPath = Join-Path $script:repoRoot 'Unmap-NorthwellPrinter-SystemWide.cmd'
    $script:undoCmdPath = Join-Path $script:repoRoot 'Undo-LatestNorthwellPrinterChange.cmd'
    $script:managerCmdPath = Join-Path $script:repoRoot 'Manage-NorthwellPrinters.cmd'
    $script:defaultsCmdPath = Join-Path $script:repoRoot 'Edit-NorthwellPrinter-Defaults.cmd'
    $script:batchCmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinters-Batch.cmd'
    $script:editBatchCmdPath = Join-Path $script:repoRoot 'Edit-NorthwellPrinter-Batch.cmd'
    $script:batchExamplePath = Join-Path $script:repoRoot 'mapping\Examples\NorthwellPrinterBatch.example.csv'
    $script:defaultsExamplePath = Join-Path $script:repoRoot 'mapping\Examples\NorthwellPrinterDefaults.example.json'
    $script:gitIgnorePath = Join-Path $script:repoRoot '.gitignore'
    Import-Module $script:modulePath -Force
}

Describe 'Northwell printer input contract' {
    It 'accepts canonical UNC queue input' {
        ConvertTo-SasNorthwellPrinterUnc -Printer '\\PRINTSRV01\QUEUE01' | Should -Be '\\PRINTSRV01\QUEUE01'
    }
    It 'preserves queue names containing spaces' {
        ConvertTo-SasNorthwellPrinterUnc -Printer '\\PRINTSRV01\Nursing Station Printer' | Should -Be '\\PRINTSRV01\Nursing Station Printer'
    }
    It 'accepts //server/queue input and normalizes it to UNC' {
        ConvertTo-SasNorthwellPrinterUnc -Printer '//PRINTSRV01/QUEUE01' | Should -Be '\\PRINTSRV01\QUEUE01'
    }
    It 'accepts a queue name with an explicit print server' {
        ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -PrintServer 'PRINTSRV01' | Should -Be '\\PRINTSRV01\QUEUE01'
    }
    It 'resolves a queue-only name through the directory resolver' {
        $resolver = { param($queue) "\\PRINTSRV01\$queue" }
        ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -DirectoryResolver $resolver | Should -Be '\\PRINTSRV01\QUEUE01'
    }
    It 'fails closed when queue-only directory lookup is ambiguous' {
        $resolver = { param($queue) @("\\PRINTSRV01\$queue", "\\PRINTSRV02\$queue") }
        { ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -DirectoryResolver $resolver } | Should -Throw '*ambiguous*'
    }
    It 'rejects a printer-server IP even when written as a UNC path' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer '\\10.20.30.40\QUEUE01' } | Should -Throw '*IP address*'
    }
    It 'rejects malformed print-server hostnames and ports' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer '\\PRINTSRV01:9100\QUEUE01' } | Should -Throw '*invalid print-server hostname*'
        { ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -PrintServer 'PRINTSRV01:9100' } | Should -Throw '*hostname/FQDN*'
    }
    It 'rejects a raw printer IP address' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer '10.20.30.40' } | Should -Throw '*IP address*'
    }
    It 'rejects IPP/HTTP printer URLs' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer 'ipp://printer.example/queue' } | Should -Throw '*URL*'
    }
}

Describe 'Northwell workstation target contract' {
    BeforeEach {
        $script:canonicalResolver = {
            param($name, $suffix)
            [pscustomobject]@{ fqdn = 'wpj001opr001.nslijhs.net'; disposition = 'UNIQUE_CANONICAL_FQDN' }
        }
    }
    It 'resolves a short hostname through the canonical Northwell FQDN authority' {
        Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001' -CanonicalResolver $script:canonicalResolver | Should -Be 'wpj001opr001.nslijhs.net'
    }
    It 'preserves an explicitly canonical Northwell FQDN after DNS identity proof' {
        Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001.nslijhs.net' -CanonicalResolver $script:canonicalResolver | Should -Be 'wpj001opr001.nslijhs.net'
    }
    It 'rejects target-PC IP addresses' {
        { Resolve-SasNorthwellTargetComputer -ComputerName '10.20.30.50' -CanonicalResolver $script:canonicalResolver } | Should -Throw '*IP address*'
    }
    It 'rejects a canonical DNS identity with a different host label' {
        $resolver = { param($name, $suffix) [pscustomobject]@{ fqdn = 'differenthost.nslijhs.net'; disposition = 'UNIQUE_CANONICAL_FQDN' } }
        { Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001' -CanonicalResolver $resolver } | Should -Throw '*different canonical host identity*'
    }
    It 'rejects a canonical FQDN outside the approved Northwell suffix' {
        $resolver = { param($name, $suffix) [pscustomobject]@{ fqdn = 'wpj001opr001.example.org'; disposition = 'UNIQUE_CANONICAL_FQDN' } }
        { Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001.example.org' -CanonicalResolver $resolver } | Should -Throw '*approved Northwell DNS suffix*'
    }
    It 'routes production resolution through the repository canonical resolver' {
        $content = Get-Content -LiteralPath $script:modulePath -Raw
        $content | Should -Match 'SasTargetNameResolution\.psm1'
        $content | Should -Match 'Resolve-SasCanonicalTargetFqdn'
    }
}

Describe 'Northwell batch planning contract' {
    It 'turns one row into many-computers by many-queues using semicolon cells' {
        $rows = @([pscustomobject]@{ Action='Map';ComputerName='PC001;PC002;PC003';PrintServer='PRINTSRV01';QueueName='QUEUE01;QUEUE02' })
        $resolver = { param($queue,$server) "\\$server\$queue" }
        $groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver)
        $groups.Count | Should -Be 1
        $groups[0].Action | Should -Be 'Map'
        ($groups[0].Computers -join ',') | Should -Be 'PC001,PC002,PC003'
        ($groups[0].Printers -join ',') | Should -Be '\\PRINTSRV01\QUEUE01,\\PRINTSRV01\QUEUE02'
        $groups[0].RowNumber | Should -Be 2
    }
    It 'keeps separate CSV rows as separate explicit groups and preserves actions' {
        $rows = @(
            [pscustomobject]@{ Action='Map';ComputerName='PC001;PC002';PrintServer='PRINTSRV01';QueueName='QUEUE01' },
            [pscustomobject]@{ Action='Unmap';ComputerName='PC003';PrintServer='PRINTSRV02';QueueName='QUEUE02;QUEUE03' }
        )
        $resolver = { param($queue,$server) "\\$server\$queue" }
        $groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver)
        $groups.Count | Should -Be 2
        $groups[0].Action | Should -Be 'Map'
        $groups[1].Action | Should -Be 'Unmap'
        $groups[0].Computers.Count | Should -Be 2
        $groups[1].Printers.Count | Should -Be 2
    }
    It 'defaults older local CSV rows without Action to Map' {
        $rows = @([pscustomobject]@{ ComputerName='PC001';PrintServer='PRINTSRV01';QueueName='QUEUE01' })
        $resolver = { param($queue,$server) "\\$server\$queue" }
        $groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver)
        $groups[0].Action | Should -Be 'Map'
    }
    It 'supports a local-only shape pass without invoking a printer resolver' {
        $rows = @([pscustomobject]@{ Action='Unmap';ComputerName='PC001';PrintServer='PRINTSRV01';QueueName='QUEUE01' })
        $resolver = { throw 'resolver should not run during ShapeOnly' }
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver -ShapeOnly } | Should -Not -Throw
    }
    It 'rejects invalid actions and tracked placeholder values before management' {
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows @([pscustomobject]@{ Action='Delete';ComputerName='PC001';PrintServer='PRINTSRV01';QueueName='QUEUE01' }) -ShapeOnly } | Should -Throw '*Action must be Map or Unmap*'
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows @([pscustomobject]@{ Action='Map';ComputerName='REPLACE-WITH-PC-HOSTNAME';PrintServer='PRINTSRV01';QueueName='QUEUE01' }) -ShapeOnly } | Should -Throw '*real Northwell hostname*'
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows @([pscustomobject]@{ Action='Map';ComputerName='PC001';PrintServer='REPLACE-WITH-PRINT-SERVER';QueueName='QUEUE01' }) -ShapeOnly } | Should -Throw '*example PrintServer*'
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows @([pscustomobject]@{ Action='Map';ComputerName='PC001';PrintServer='PRINTSRV01';QueueName='REPLACE-WITH-QUEUE-NAME' }) -ShapeOnly } | Should -Throw '*example QueueName*'
    }
    It 'fails closed when a required CSV column is missing' {
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows @([pscustomobject]@{ Action='Map';ComputerName='PC001';QueueName='QUEUE01' }) } | Should -Throw "*missing required CSV column 'PrintServer'*"
    }
}

Describe 'Northwell controller executable safety helpers' {
    It 'creates collision-resistant run tokens' {
        $tokens = @(1..20 | ForEach-Object { New-SasNorthwellPrinterRunToken })
        @($tokens | Sort-Object -Unique).Count | Should -Be 20
        foreach ($token in $tokens) { $token | Should -Match '^\d{8}-\d{9}-[0-9a-f]{12}$' }
    }
    It 'creates a locale-independent SYSTEM task definition for immediate manual run' {
        $arguments = @(New-SasNorthwellPrinterTaskCreateArguments -Computer 'WPJ001OPR001.nslijhs.net' -TaskName 'SysAdminSuite_NorthwellPrinterState_test' -RemoteLauncherLocal 'C:\ProgramData\SysAdminSuite\Mapping\NorthwellPrinterState\test\Start-Agent.cmd')
        $arguments | Should -Contain '/RU'
        $arguments | Should -Contain 'SYSTEM'
        $arguments | Should -Contain '/SC'
        $arguments | Should -Contain 'ONSTART'
        $arguments | Should -Not -Contain '/SD'
        $arguments | Should -Not -Contain '/ST'
    }
    It 'accepts only SYSTEM status with every requested HKLM queue present' {
        $status = [pscustomobject]@{ Success=$true;Identity='NT AUTHORITY\SYSTEM';DesiredState='Present';MachineWideUNC=@('\\printsrv01\queue01','\\printsrv01\queue02');Missing=@();StillPresent=@() }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01','\\PRINTSRV01\QUEUE02') -DesiredState Present } | Should -Not -Throw
    }
    It 'accepts SYSTEM status with every requested HKLM queue absent' {
        $status = [pscustomobject]@{ Success=$true;Identity='NT AUTHORITY\SYSTEM';DesiredState='Absent';MachineWideUNC=@('\\printsrv01\other');Missing=@();StillPresent=@() }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') -DesiredState Absent } | Should -Not -Throw
    }
    It 'rejects status produced by a non-SYSTEM identity' {
        $status = [pscustomobject]@{ Success=$true;Identity='DOMAIN\Tech';DesiredState='Present';MachineWideUNC=@('\\printsrv01\queue01') }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') } | Should -Throw '*did not run as SYSTEM*'
    }
    It 'rejects a missing requested queue when presence is desired' {
        $status = [pscustomobject]@{ Success=$true;Identity='NT AUTHORITY\SYSTEM';DesiredState='Present';MachineWideUNC=@('\\printsrv01\queue01') }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01','\\PRINTSRV01\QUEUE02') -DesiredState Present } | Should -Throw '*did not prove requested machine-wide connection*'
    }
    It 'rejects a still-present requested queue when absence is desired' {
        $status = [pscustomobject]@{ Success=$true;Identity='NT AUTHORITY\SYSTEM';DesiredState='Absent';MachineWideUNC=@('\\printsrv01\queue01') }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') -DesiredState Absent } | Should -Throw '*did not prove requested machine-wide connection removal*'
    }
}

Describe 'Canonical Northwell reversible system-wide runner contract' {
    It 'pairs SYSTEM PrintUIEntry /ga and /gd for per-computer desired state' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match "'/ga'"
        $content | Should -Match "'/gd'"
        $content | Should -Match 'MachineWidePerComputer'
        $content | Should -Match 'New-SasNorthwellPrinterTaskCreateArguments'
        $content | Should -Match 'Assert-SasNorthwellPrinterStatusProof'
    }
    It 'serializes result snapshots without the Windows PowerShell 5.1 generic-list array binder' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'Results = \$results\.ToArray\(\)'
        $content | Should -Not -Match 'Results = @\(\$results\)'
    }
    It 'passes printer queues as native arguments instead of Start-Process string joining' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match '& "\$env:SystemRoot\\System32\\rundll32\.exe"'
        $content | Should -Match '"/n\$queue"'
        $content | Should -Not -Match "Start-Process -FilePath 'rundll32\.exe'"
    }
    It 'polls HKLM for both desired states without synchronous gpupdate' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Print\\Connections'
        $content | Should -Match 'AddSeconds\(30\)'
        $content | Should -Match 'Missing'
        $content | Should -Match 'StillPresent'
        $content | Should -Not -Match 'gpupdate\.exe'
    }
    It 'does not use locale-dependent task dates or per-user printer paths' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Not -Match 'ToShortDateString'
        $content | Should -Not -Match "'/SD'"
        $content | Should -Not -Match "'/ST'"
        $content | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $content | Should -Not -Match 'Remove-Printer'
    }
    It 'preserves durable evidence plus a state-derived undo plan' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'ResolvedPlan\.json'
        $content | Should -Match 'Summary\.json'
        $content | Should -Match 'Status\.json'
        $content | Should -Match 'Agent\.log'
        $content | Should -Match 'UndoPlan\.json'
        $content | Should -Match 'BeforeMachineWideUNC'
        $content | Should -Match 'ChangedPrinters'
        $content | Should -Not -Match '(?m)^\s*exit\s+[1-9]'
    }
    It 'requires print-server DNS only for mapping so stale UNC entries remain removable' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'if \(\$DesiredState -eq ''Present''\)'
        $content | Should -Match 'removing a stale machine-wide connection must remain possible'
        $content | Should -Match 'GetHostAddresses\(\$server\)'
    }
    It 'keeps the default live evidence tree ignored with exact path casing' {
        (Get-Content -LiteralPath $script:gitIgnorePath -Raw) | Should -Match '(?m)^mapping/Logs/\*\r?$'
    }
    It 'keeps old and new advanced wrappers symmetric' {
        (Get-Content -LiteralPath $script:mapWrapperPath -Raw) | Should -Match "DesiredState = 'Present'"
        (Get-Content -LiteralPath $script:unmapWrapperPath -Raw) | Should -Match "DesiredState = 'Absent'"
    }
}

Describe 'Technician quick front-door contract' {
    It 'self-elevates with trustworthy child exit propagation and delegates by relative path' {
        $content = Get-Content -LiteralPath $script:cmdPath -Raw
        $content | Should -Match 'EnableDelayedExpansion'
        $content | Should -Match 'Start-Process.*-Verb RunAs'
        $content | Should -Match '!ERRORLEVEL!'
        $content | Should -Match 'Start-NorthwellPrinterMapping\.ps1.*-Action Map'
        $content | Should -Match '%~dp0'
        $content | Should -Not -Match '(?i)C:\\Users\\'
        $content | Should -Match 'ALL users'
        $content | Should -Match 'NO TEST PAGE'
        $content | Should -Match 'UndoPlan\.json'
    }
    It 'ships a symmetric unmap launcher without port deletion' {
        $content = Get-Content -LiteralPath $script:unmapCmdPath -Raw
        $content | Should -Match 'Start-NorthwellPrinterMapping\.ps1.*-Action Unmap'
        $content | Should -Match 'PrintUIEntry /gd'
        $content | Should -Match 'no printer port is deleted'
        $content | Should -Match 'Undo-LatestNorthwellPrinterChange\.cmd'
        $content | Should -Not -Match 'Remove-Printer'
    }
    It 'uses operator-local defaults rather than tracked live endpoints' {
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $content | Should -Match 'northwell-printer-defaults\.local\.json'
        $content | Should -Match 'Read-SasNorthwellPrinterSets -InitialPrintServer \$PrintServer'
        $content | Should -Match 'No operator-local printer default is configured'
        $content | Should -Not -Match 'SYKPNHPHPS01V'
    }
    It 'collects repeated server/queue sets and delegates to the reversible engine' {
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $content | Should -Match "Read-Host 'Target PC hostname\(s\), comma/semicolon-separated'"
        $content | Should -Match 'Add another print server / queue set\? \[y/N\]'
        $content | Should -Match 'Invoke-NorthwellPrinterState\.ps1'
        $content | Should -Match 'SYSTEM-WIDE for all users'
        $content | Should -Match 'SasNorthwellNetworkAuthority\.psm1'
    }
}

Describe 'Technician local-default contract' {
    It 'ships a clickable local defaults editor and synthetic tracked template' {
        Test-Path -LiteralPath $script:defaultsCmdPath | Should -BeTrue
        Test-Path -LiteralPath $script:defaultsExamplePath | Should -BeTrue
        $editor = Get-Content -LiteralPath $script:defaultsCmdPath -Raw
        $editor | Should -Match 'northwell-printer-defaults\.local\.json'
        $editor | Should -Match 'NorthwellPrinterDefaults\.example\.json'
        $editor | Should -Match 'notepad\.exe'
        $editor | Should -Not -Match 'Start-NorthwellPrinterMapping\.ps1'
        $example = Get-Content -LiteralPath $script:defaultsExamplePath -Raw | ConvertFrom-Json
        $example.PrintServer | Should -Be 'REPLACE-WITH-PRINT-SERVER'
        $example.QueueName | Should -Be 'REPLACE-WITH-QUEUE-NAME'
        (Get-Content -LiteralPath $script:gitIgnorePath -Raw) | Should -Match '(?m)^Config/northwell-printer-defaults\.local\.json\r?$'
    }
}

Describe 'Technician reversible batch front-door contract' {
    It 'ships clickable batch editor/runner plus a synthetic Action-aware example CSV' {
        Test-Path -LiteralPath $script:batchCmdPath | Should -BeTrue
        Test-Path -LiteralPath $script:editBatchCmdPath | Should -BeTrue
        Test-Path -LiteralPath $script:batchExamplePath | Should -BeTrue
        $rows = @(Import-Csv -LiteralPath $script:batchExamplePath)
        $rows.Count | Should -Be 1
        $rows[0].Action | Should -Be 'Map'
        $rows[0].ComputerName | Should -Be 'REPLACE-WITH-PC-HOSTNAME'
        $rows[0].PrintServer | Should -Be 'REPLACE-WITH-PRINT-SERVER'
        $rows[0].QueueName | Should -Be 'REPLACE-WITH-QUEUE-NAME'
        (Get-Content -LiteralPath $script:gitIgnorePath -Raw) | Should -Match '(?m)^!mapping/Examples/\*\.example\.csv\r?$'
    }
    It 'keeps editing local and execution separate' {
        $edit = Get-Content -LiteralPath $script:editBatchCmdPath -Raw
        $edit | Should -Match 'NorthwellPrinterBatch\.example\.csv'
        $edit | Should -Match 'NorthwellPrinterBatch\.csv'
        $edit | Should -Match 'notepad\.exe'
        $edit | Should -Match 'Map-NorthwellPrinters-Batch\.cmd'
        $edit | Should -Not -Match 'Start-NorthwellPrinterBatch\.ps1'
    }
    It 'propagates elevated child status and advertises reversible confirmation' {
        $run = Get-Content -LiteralPath $script:batchCmdPath -Raw
        $run | Should -Match 'EnableDelayedExpansion'
        $run | Should -Match 'Start-Process.*-Verb RunAs'
        $run | Should -Match '!ERRORLEVEL!'
        $run | Should -Match 'Start-NorthwellPrinterBatch\.ps1'
        $run | Should -Match 'Action,ComputerName,PrintServer,QueueName'
        $run | Should -Match 'type APPLY'
        $run | Should -Match 'UndoPlan\.json'
        $run | Should -Match 'NO TEST PAGE'
    }
    It 'guards network activity before full queue resolution and requires production confirmation' {
        $content = Get-Content -LiteralPath $script:batchPath -Raw
        $content | Should -Match 'ConvertTo-SasNorthwellPrinterBatchGroups -Rows \$rows -ShapeOnly'
        $guardIndex = $content.IndexOf('Assert-SasNorthwellNetwork')
        $resolveIndex = $content.IndexOf('$groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows)')
        $guardIndex | Should -BeGreaterThan -1
        $resolveIndex | Should -BeGreaterThan $guardIndex
        $content | Should -Match "Read-Host 'Type APPLY to execute this exact map/unmap batch plan'"
        $content | Should -Match '\$confirmation -cne ''APPLY'''
        $content | Should -Match 'ConfirmBatch'
    }
    It 'delegates every row to the reversible engine and aggregates undo evidence' {
        $content = Get-Content -LiteralPath $script:batchPath -Raw
        $content | Should -Match 'Invoke-NorthwellPrinterState\.ps1'
        $content | Should -Match 'BatchPlan\.json'
        $content | Should -Match 'Summary\.json'
        $content | Should -Match 'UndoPlan\.json'
        $content | Should -Match 'LATEST-PATH\.txt'
        $content | Should -Match 'RuntimePrintObservedByEngine = \$false'
        $content | Should -Match 'TestPagesPrinted = \$false'
        $content | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $content | Should -Not -Match 'Remove-Printer'
        $content | Should -Not -Match 'PrintTestPage'
    }
}

Describe 'Technician undo and manager contract' {
    It 'requires exact undo confirmation and makes undo itself reversible' {
        $undo = Get-Content -LiteralPath (Join-Path $script:repoRoot 'mapping\Undo-NorthwellPrinterChange.ps1') -Raw
        $undo | Should -Match "Read-Host 'Type UNDO to execute this exact inverse plan'"
        $undo | Should -Match 'sas-northwell-printer-undo/v1'
        $undo | Should -Match 'Invoke-NorthwellPrinterState\.ps1'
        $undo | Should -Match 'Next undo/redo plan'
        $undo | Should -Match 'SasNorthwellNetworkAuthority\.psm1'
    }
    It 'provides one portable manager front door for every technician angle' {
        $manager = Get-Content -LiteralPath $script:managerCmdPath -Raw
        $manager | Should -Match 'Map printer\(s\) system-wide'
        $manager | Should -Match 'Unmap printer\(s\) system-wide'
        $manager | Should -Match 'Undo latest observed printer state change'
        $manager | Should -Match 'Run batch map/unmap plan'
        $manager | Should -Match '%~dp0'
        $manager | Should -Not -Match '(?i)C:\\Users\\'
        $manager | Should -Not -Match 'if /i .*call .* & goto menu'
    }
}
