#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:runnerPath = Join-Path $script:repoRoot 'mapping\Invoke-NorthwellPrinterMapping.ps1'
    $script:launcherPath = Join-Path $script:repoRoot 'Map-NorthwellPrinter-SystemWide.cmd'
}

Describe 'Northwell stale direct-IP queue collision repair contract' {
    It 'repairs only an exact same-queue local direct-IP printer object before machine-wide mapping' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw

        $content | Should -Match 'Get-StaleLocalIpQueueCollision'
        $content | Should -Match 'REPAIRED_STALE_DIRECT_IP_QUEUE_COLLISION'
        $content | Should -Match 'AMBIGUOUS_LOCAL_IP_QUEUE_COLLISION'
        $content | Should -Match 'Get-Printer -ErrorAction Stop'
        $content | Should -Match 'Remove-Printer -Name \$staleName -Confirm:\$false'
        $content | Should -Match 'PreservedPort = \$stalePort'
        $content | Should -Match 'PrinterPortDeleted = \$false'
        $content | Should -Match 'TestPagePrinted = \$false'

        $repairCall = $content.IndexOf('$collision = @(Get-StaleLocalIpQueueCollision -Queue $queue)')
        $mapCall = $content.IndexOf('Write-AgentLog "ADD /ga $queue"')
        $repairCall | Should -BeGreaterThan -1
        $mapCall | Should -BeGreaterThan -1
        $repairCall | Should -BeLessThan $mapCall
    }

    It 'never turns the collision repair into direct-IP mapping, port deletion, or print testing' {
        $content = Get-Content -LiteralPath $script:runnerPath -Raw

        $content | Should -Not -Match 'Remove-PrinterPort'
        $content | Should -Not -Match 'Add-PrinterPort'
        $content | Should -Not -Match 'Add-Printer\s+-ConnectionName'
        $content | Should -Not -Match 'PrintTestPage'
        $content | Should -Match "'/ga'"
        $content | Should -Match 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Print\\Connections'
    }

    It 'publishes the exact mapping evidence directory and keeps the operator window open' {
        $runner = Get-Content -LiteralPath $script:runnerPath -Raw
        $launcher = Get-Content -LiteralPath $script:launcherPath -Raw

        $runner | Should -Match 'LATEST-PATH\.txt'
        $runner | Should -Match 'SessionRoot = \$SessionRoot'
        $launcher | Should -Match 'LATEST-PATH\.txt'
        $launcher | Should -Match 'Summary\.json'
        $launcher | Should -Match 'Controller\.log'
        $launcher | Should -Match 'Status\.json'
        $launcher | Should -Match 'Agent\.log'
        $launcher | Should -Match 'notepad\.exe'
        $launcher | Should -Match '(?i)pause'
        $launcher | Should -Match 'NO TEST PAGE'
        $launcher | Should -Match 'TCP/IP PORT is preserved'
    }
}
