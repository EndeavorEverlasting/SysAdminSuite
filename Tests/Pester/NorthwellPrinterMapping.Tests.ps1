#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:modulePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
    $script:runnerPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:interactivePath = Join-Path $script:repoRoot 'mapping\Start-NorthwellPrinterMapping.ps1'
    $script:cmdPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
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
            param($name)
            if ($name -ieq 'WPJ001OPR001.nslijhs.net') {
                return [pscustomobject]@{
                    canonical_name = 'WPJ001OPR001.nslijhs.net'
                    addresses = @('10.20.30.50')
                }
            }
            return $null
        }
    }

    It 'resolves a short hostname through the canonical Northwell FQDN authority' {
        Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001' -DnsResolver $script:canonicalResolver |
            Should -Be 'wpj001opr001.nslijhs.net'
    }

    It 'preserves an explicitly canonical Northwell FQDN after DNS identity proof' {
        Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001.nslijhs.net' -DnsResolver $script:canonicalResolver |
            Should -Be 'wpj001opr001.nslijhs.net'
    }

    It 'rejects target-PC IP addresses' {
        { Resolve-SasNorthwellTargetComputer -ComputerName '10.20.30.50' -DnsResolver $script:canonicalResolver } |
            Should -Throw '*IP address*'
    }

    It 'rejects a canonical DNS identity with a different host label' {
        $aliasResolver = {
            param($name)
            return [pscustomobject]@{
                canonical_name = 'DIFFERENTHOST.nslijhs.net'
                addresses = @('10.20.30.50')
            }
        }
        { Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001' -DnsResolver $aliasResolver } |
            Should -Throw '*different canonical host identity*'
    }

    It 'rejects a canonical FQDN outside the approved Northwell suffix' {
        $outsideResolver = {
            param($name)
            return [pscustomobject]@{
                canonical_name = 'WPJ001OPR001.example.org'
                addresses = @('10.20.30.50')
            }
        }
        { Resolve-SasNorthwellTargetComputer -ComputerName 'WPJ001OPR001.example.org' -DnsResolver $outsideResolver } |
            Should -Throw '*approved Northwell DNS suffix*'
    }
}

Describe 'Northwell controller executable safety helpers' {
    It 'creates collision-resistant run tokens' {
        $tokens = @(1..20 | ForEach-Object { New-SasNorthwellPrinterRunToken })
        @($tokens | Sort-Object -Unique).Count | Should -Be 20
        foreach ($token in $tokens) {
            $token | Should -Match '^\d{17}-[0-9a-f]{12}$'
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
        $ignore | Should -Match '(?m)^mapping/Logs/\*$'
    }
}

Describe 'Technician front-door contract' {
    It 'has one root CMD launcher that self-elevates and delegates to the interactive wrapper' {
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
    }

    It 'prompts only for missing hostnames and queues and delegates to the canonical engine' {
        Test-Path -LiteralPath $script:interactivePath | Should -BeTrue
        $content = Get-Content -LiteralPath $script:interactivePath -Raw
        $content | Should -Match "Read-Host 'Target PC hostname\(s\), comma-separated'"
        $content | Should -Match "Read-Host 'Printer queue\(s\), comma-separated'"
        $content | Should -Match 'Invoke-NorthwellPrinterMapping\.ps1'
        $content | Should -Match 'SYSTEM-WIDE for all users'
    }
}
