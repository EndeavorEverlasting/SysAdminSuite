#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:modulePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
    $script:runnerPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:interactivePath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:batchPath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterBatch.ps1'
    $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
    $script:batchCmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinters-Batch.cmd'
    $script:editBatchCmdPath = Join-Path $script:repoRoot 'Edit-NorthwellPrinter-Batch.cmd'
    $script:batchExamplePath = Join-Path $script:repoRoot 'mapping\Examples\NorthwellPrinterBatch.example.csv'
    $script:gitIgnorePath = Join-Path $script:repoRoot '.gitignore'
    Import-Module $script:modulePath -Force
}

Describe 'Northwell printer input contract' {
    It 'accepts canonical UNC queue input' {
        ConvertTo-SasNorthwellPrinterUnc -Printer '\\PRINTSRV01\QUEUE01' |
            Should -Be '\\PRINTSRV01\QUEUE01'
    }

    It 'preserves queue names containing spaces' {
        ConvertTo-SasNorthwellPrinterUnc -Printer '\\PRINTSRV01\Nursing Station Printer' |
            Should -Be '\\PRINTSRV01\Nursing Station Printer'
    }

    It 'accepts //server/queue input and normalizes it to UNC' {
        ConvertTo-SasNorthwellPrinterUnc -Printer '//PRINTSRV01/QUEUE01' |
            Should -Be '\\PRINTSRV01\QUEUE01'
    }

    It 'accepts a queue name with an explicit print server' {
        ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -PrintServer 'PRINTSRV01' |
            Should -Be '\\PRINTSRV01\QUEUE01'
    }

    It 'resolves a queue-only name through the directory resolver' {
        $resolver = { param($queue) "\\PRINTSRV01\$queue" }
        ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -DirectoryResolver $resolver |
            Should -Be '\\PRINTSRV01\QUEUE01'
    }

    It 'fails closed when queue-only directory lookup is ambiguous' {
        $resolver = { param($queue) @("\\PRINTSRV01\$queue", "\\PRINTSRV02\$queue") }
        { ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -DirectoryResolver $resolver } |
            Should -Throw '*ambiguous*'
    }

    It 'rejects a printer-server IP even when written as a UNC path' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer '\\10.20.30.40\QUEUE01' } |
            Should -Throw '*IP address*'
    }

    It 'rejects malformed print-server hostnames and ports' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer '\\PRINTSRV01:9100\QUEUE01' } |
            Should -Throw '*invalid print-server hostname*'
        { ConvertTo-SasNorthwellPrinterUnc -Printer 'QUEUE01' -PrintServer 'PRINTSRV01:9100' } |
            Should -Throw '*hostname/FQDN*'
    }

    It 'rejects a raw printer IP address' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer '10.20.30.40' } |
            Should -Throw '*IP address*'
    }

    It 'rejects IPP/HTTP printer URLs' {
        { ConvertTo-SasNorthwellPrinterUnc -Printer 'ipp://printer.example/queue' } |
            Should -Throw '*URL*'
    }
}

Describe 'Northwell workstation target contract' {
    BeforeEach {
        $script:canonicalResolver = {
            param($name, $suffix)
            return [pscustomobject]@{
                fqdn = 'wpj001opr001.nslijhs.net'
                disposition = 'UNIQUE_CANONICAL_FQDN'
            }
        }
    }

    It 'resolves a short hostname through the canonical Northwell FQDN authority' {
        Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001' -CanonicalResolver $script:canonicalResolver |
            Should -Be 'wpj001opr001.nslijhs.net'
    }

    It 'preserves an explicitly canonical Northwell FQDN after DNS identity proof' {
        Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001.nslijhs.net' -CanonicalResolver $script:canonicalResolver |
            Should -Be 'wpj001opr001.nslijhs.net'
    }

    It 'rejects target-PC IP addresses' {
        { Resolve-SasNorthwellTargetComputer -ComputerName '10.20.30.50' -CanonicalResolver $script:canonicalResolver } |
            Should -Throw '*IP address*'
    }

    It 'rejects a canonical DNS identity with a different host label' {
        $aliasResolver = {
            param($name, $suffix)
            return [pscustomobject]@{
                fqdn = 'differenthost.nslijhs.net'
                disposition = 'UNIQUE_CANONICAL_FQDN'
            }
        }
        { Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001' -CanonicalResolver $aliasResolver } |
            Should -Throw '*different canonical host identity*'
    }

    It 'rejects a canonical FQDN outside the approved Northwell suffix' {
        $outsideResolver = {
            param($name, $suffix)
            return [pscustomobject]@{
                fqdn = 'wpj001opr001.example.org'
                disposition = 'UNIQUE_CANONICAL_FQDN'
            }
        }
        { Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001.example.org' -CanonicalResolver $outsideResolver } |
            Should -Throw '*approved Northwell DNS suffix*'
    }

    It 'routes production resolution through the repository canonical resolver' {
        $content = Get-Content -LiteralPath $script:modulePath -Raw
        $content | Should -Match 'SasTargetNameResolution\.psm1'
        $content | Should -Match 'Resolve-SasCanonicalTargetFqdn'
    }
}

Describe 'Northwell batch planning contract' {
    It 'turns one row into many-computers by many-queues using semicolon cells' {
        $rows = @(
            [pscustomobject]@{
                ComputerName = 'PC001;PC002;PC003'
                PrintServer = 'PRINTSRV01'
                QueueName = 'QUEUE01;QUEUE02'
            }
        )
        $resolver = { param($queue, $server) "\\$server\$queue" }
        $groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver)

        $groups.Count | Should -Be 1
        $groups[0].Computers | Should -Be @('PC001','PC002','PC003')
        $groups[0].Printers | Should -Be @('\\PRINTSRV01\QUEUE01','\\PRINTSRV01\QUEUE02')
        $groups[0].RowNumber | Should -Be 2
    }

    It 'keeps separate CSV rows as separate explicit mapping groups' {
        $rows = @(
            [pscustomobject]@{ ComputerName = 'PC001;PC002'; PrintServer = 'PRINTSRV01'; QueueName = 'QUEUE01' },
            [pscustomobject]@{ ComputerName = 'PC003'; PrintServer = 'PRINTSRV02'; QueueName = 'QUEUE02;QUEUE03' }
        )
        $resolver = { param($queue, $server) "\\$server\$queue" }
        $groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver)

        $groups.Count | Should -Be 2
        $groups[0].Computers.Count | Should -Be 2
        $groups[1].Printers.Count | Should -Be 2
    }

    It 'rejects the shipped placeholder computer before any mapping can run' {
        $rows = @(
            [pscustomobject]@{ ComputerName = 'REPLACE-WITH-PC-HOSTNAME'; PrintServer = 'PRINTSRV01'; QueueName = 'QUEUE01' }
        )
        $resolver = { param($queue, $server) "\\$server\$queue" }
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -PrinterResolver $resolver } |
            Should -Throw '*Replace it with a real Northwell hostname*'
    }

    It 'fails closed when a required CSV column is missing' {
        $rows = @(
            [pscustomobject]@{ ComputerName = 'PC001'; QueueName = 'QUEUE01' }
        )
        { ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows } |
            Should -Throw "*missing required CSV column 'PrintServer'*"
    }
}

Describe 'Northwell controller executable safety helpers' {
    It 'creates collision-resistant run tokens' {
        $tokens = @(1..20 | ForEach-Object { New-SasNorthwellPrinterRunToken })
        @($tokens | Sort-Object -Unique).Count | Should -Be 20
        foreach ($token in $tokens) {
            $token | Should -Match '^\d{8}-\d{9}-[0-9a-f]{12}$'
        }
    }

    It 'creates a locale-independent SYSTEM task definition for immediate manual run' {
        $arguments = @(New-SasNorthwellPrinterTaskCreateArguments `
            -Computer 'WPJ001OPR001.nslijhs.net' `
            -TaskName 'SysAdminSuite_NorthwellPrinterMap_test' `
            -RemoteLauncherLocal 'C:\ProgramData\SysAdminSuite\Mapping\NorthwellPrinterMap\test\Start-Agent.cmd')

        $arguments | Should -Contain '/RU'
        $arguments | Should -Contain 'SYSTEM'
        $arguments | Should -Contain '/SC'
        $arguments | Should -Contain 'ONSTART'
        $arguments | Should -Not -Contain '/SD'
        $arguments | Should -Not -Contain '/ST'
    }

    It 'accepts only SYSTEM status with every requested HKLM queue proven' {
        $status = [pscustomobject]@{
            Success = $true
            Identity = 'NT AUTHORITY\SYSTEM'
            MachineWideUNC = @('\\printsrv01\queue01', '\\printsrv01\queue02')
            Missing = @()
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01','\\PRINTSRV01\QUEUE02') } |
            Should -Not -Throw
    }

    It 'rejects status produced by a non-SYSTEM identity' {
        $status = [pscustomobject]@{
            Success = $true
            Identity = 'DOMAIN\Tech'
            MachineWideUNC = @('\\printsrv01\queue01')
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') } |
            Should -Throw '*did not run as SYSTEM*'
    }

    It 'rejects status that omits a requested machine-wide queue' {
        $status = [pscustomobject]@{
            Success = $true
            Identity = 'NT AUTHORITY\SYSTEM'
            MachineWideUNC = @('\\printsrv01\queue01')
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01','\\PRINTSRV01\QUEUE02') } |
            Should -Throw '*did not prove requested machine-wide connection*'
    }

    It 'propagates the endpoint failure classification' {
        $status = [pscustomobject]@{
            Success = $false
            Identity = 'NT AUTHORITY\SYSTEM'
            Error = 'PrintUIEntry /ga failed for queue.'
        }
        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') } |
            Should -Throw '*PrintUIEntry /ga failed*'
    }
}

Describe 'Canonical Northwell system-wide runner contract' {
    It 'uses SYSTEM plus PrintUIEntry /ga for per-computer mapping' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match "'/ga'"
        $content | Should -Match 'MachineWidePerComputer'
        $content | Should -Match 'New-SasNorthwellPrinterTaskCreateArguments'
        $content | Should -Match 'Assert-SasNorthwellPrinterStatusProof'
    }

    It 'passes the printer queue as a native argument instead of Start-Process string joining' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match '& "\$env:SystemRoot\\System32\\rundll32\.exe"'
        $content | Should -Match '"/n\$queue"'
        $content | Should -Not -Match "Start-Process -FilePath 'rundll32\.exe'"
    }

    It 'polls for requested HKLM machine-wide proof before failing' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Print\\Connections'
        $content | Should -Match 'AddSeconds\(30\)'
        $content | Should -Match 'Missing'
        $content | Should -Match 'VerifiedMachineWide'
    }

    It 'does not use locale-dependent task dates' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Not -Match 'ToShortDateString'
        $content | Should -Not -Match "'/SD'"
        $content | Should -Not -Match "'/ST'"
    }

    It 'does not use the per-user Add-Printer ConnectionName path' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Not -Match 'Add-Printer\s+-ConnectionName'
    }

    It 'preserves controller and per-host evidence before failing the run' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw
        $content | Should -Match 'ResolvedPlan\.json'
        $content | Should -Match 'Summary\.json'
        $content | Should -Match 'Status\.json'
        $content | Should -Match 'Agent\.log'
        $content | Should -Not -Match '(?m)^\s*exit\s+[1-9]'
    }

    It 'keeps the default live evidence tree ignored with exact path casing' {
        $ignore = Get-Content -LiteralPath $script:gitIgnorePath -Raw
        $ignore | Should -Match '(?m)^mapping/Logs/\*\r?$'
    }
}

Describe 'Technician quick front-door contract' {
    It 'has a root CMD launcher that self-elevates and delegates to the interactive wrapper' {
        Test-Path -LiteralPath $script:cmdPath | Should -BeTrue
        $content = Get-Content -LiteralPath $script:cmdPath -Raw
        $content | Should -Match 'WindowsBuiltInRole\]::Administrator'
        $content | Should -Not -Match '(?im)^net session'
        $content | Should -Match 'Start-Process.*-Verb RunAs'
        $content | Should -Match '\$env:ComSpec'
        $content | Should -Match 'Start-NorthwellPrinterMapping\.ps1'
        $content | Should -Match '(?i)pause'
        $content | Should -Match 'ALL users'
        $content | Should -Match 'Printer IP addresses are NOT allowed'
        $content | Should -Match '\\\\SYKPNHPHPS01V\\LS001-EMS01'
        $content | Should -Match 'Map-NorthwellPrinters-Batch\.cmd'
        $content | Should -Not -Match 'Remove-Printer'
        $content | Should -Not -Match 'direct-IP printer OBJECT may be removed'
    }

    It 'collects repeated print-server queue sets and delegates to the canonical engine' {
        Test-Path -LiteralPath $script:interactivePath | Should -BeTrue
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $content | Should -Match "Read-Host 'Target PC hostname\(s\), comma-separated'"
        $content | Should -Match 'Print server hostname \[\$defaultPrintServer\]'
        $content | Should -Match 'Queue name\(s\), comma-separated \[\$defaultPrinterQueue\]'
        $content | Should -Match 'Add another print server / queue set\? \[y/N\]'
        $content | Should -Match 'SYKPNHPHPS01V'
        $content | Should -Match 'LS001-EMS01'
        $content | Should -Match 'Invoke-NorthwellPrinterMapping\.ps1'
        $content | Should -Match 'SYSTEM-WIDE for all users'
    }
}

Describe 'Technician batch front-door contract' {
    It 'ships clickable batch edit and map CMDs plus a tracked example CSV' {
        Test-Path -LiteralPath $script:batchCmdPath | Should -BeTrue
        Test-Path -LiteralPath $script:editBatchCmdPath | Should -BeTrue
        Test-Path -LiteralPath $script:batchExamplePath | Should -BeTrue

        $example = Get-Content -LiteralPath $script:batchExamplePath -Raw
        $example | Should -Match '^ComputerName,PrintServer,QueueName'
        $example | Should -Match 'REPLACE-WITH-PC-HOSTNAME,SYKPNHPHPS01V,LS001-EMS01'

        $ignore = Get-Content -LiteralPath $script:gitIgnorePath -Raw
        $ignore | Should -Match '(?m)^!mapping/Examples/\*\.example\.csv\r?$'
    }

    It 'keeps editing local and execution separate' {
        $edit = Get-Content -LiteralPath $script:editBatchCmdPath -Raw
        $edit | Should -Match 'NorthwellPrinterBatch\.example\.csv'
        $edit | Should -Match 'NorthwellPrinterBatch\.csv'
        $edit | Should -Match 'notepad\.exe'
        $edit | Should -Match 'Map-NorthwellPrinters-Batch\.cmd'
        $edit | Should -Not -Match 'Start-NorthwellPrinterBatch\.ps1'

        $run = Get-Content -LiteralPath $script:batchCmdPath -Raw
        $run | Should -Match 'WindowsBuiltInRole\]::Administrator'
        $run | Should -Match 'Start-Process.*-Verb RunAs'
        $run | Should -Match 'Start-NorthwellPrinterBatch\.ps1'
        $run | Should -Match 'ComputerName,PrintServer,QueueName'
        $run | Should -Match 'PC001;PC002,SYKPNHPHPS01V,LS001-EMS01;QUEUE02'
        $run | Should -Match '(?i)pause'
        $run | Should -Match 'NO TEST PAGE'
    }

    It 'delegates every batch row to the canonical engine and preserves parent evidence' {
        Test-Path -LiteralPath $script:batchPath | Should -BeTrue
        $content = Get-Content -LiteralPath $script:batchPath -Raw
        $content | Should -Match 'Import-Csv'
        $content | Should -Match 'ConvertTo-SasNorthwellPrinterBatchGroups'
        $content | Should -Match 'Invoke-NorthwellPrinterMapping\.ps1'
        $content | Should -Match 'BatchPlan\.json'
        $content | Should -Match 'Summary\.json'
        $content | Should -Match 'LATEST-PATH\.txt'
        $content | Should -Match 'NorthwellPrinterBatch-'
        $content | Should -Match 'RuntimePrintObservedByEngine = \$false'
        $content | Should -Match 'TestPagesPrinted = \$false'
        $content | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $content | Should -Not -Match 'Remove-Printer'
        $content | Should -Not -Match 'PrintTestPage'
    }
}
