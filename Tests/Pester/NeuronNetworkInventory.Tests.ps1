#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $repoRoot 'GetInfo\Get-NeuronNetworkInventory.ps1'
    $templatePath = Join-Path $repoRoot 'GetInfo\Config\NeuronTargets.example.csv'
    $script:content = Get-Content -Path $scriptPath -Raw
}

Describe 'Get-NeuronNetworkInventory.ps1 -- admin-box survey contract' {
    It 'Script file exists' {
        $scriptPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Accepts a target list and direct targets' {
        $script:content | Should -Match '\$ListPath'
        $script:content | Should -Match '\$Targets'
    }

    It 'Writes artifacts to an admin-box output directory' {
        $script:content | Should -Match '\$OutputDirectory'
        $script:content | Should -Match 'NeuronNetworkInventory_\{0\}\.csv'
        $script:content | Should -Match 'NeuronNetworkInventory_\{0\}\.json'
        $script:content | Should -Match 'NeuronNetworkInventory_\{0\}\.html'
    }

    It 'Does not stage files or scheduled tasks on target machines' {
        $script:content | Should -Not -Match 'Copy-Item\s+.*\\\\\$'
        $script:content | Should -Not -Match 'schtasks'
        $script:content | Should -Not -Match 'Invoke-Command'
        $script:content | Should -Match 'TargetSideArtifacts\s*=\s*''None'''
    }

    It 'Collects host, serial, IP, MAC, manufacturer, and model fields' {
        foreach ($field in @('TargetHost','ExpectedMAC','ExpectedSerial','IPAddress','MACAddress','PrimaryMAC','SerialNumber','SystemSerialNumber','Manufacturer','Model')) {
            $script:content | Should -Match $field
        }
    }

    It 'Compares observed MAC and serial values against tracked target data' {
        $script:content | Should -Match 'MatchExpectedMAC'
        $script:content | Should -Match 'MatchExpectedSerial'
        $script:content | Should -Match 'Normalize-MacAddress'
    }

    It 'Supports skip-ping and credential parameters for locked-down networks' {
        $script:content | Should -Match '\$SkipPing'
        $script:content | Should -Match '\$Credential'
    }

    It 'Uses WMI for remote reads and Start-Job for throttled parallelism' {
        $script:content | Should -Match 'Get-WmiObject'
        $script:content | Should -Match 'Start-Job'
        $script:content | Should -Match '\$Throttle'
    }

    It 'Generates suite HTML when the helper exists' {
        $script:content | Should -Match 'ConvertTo-SuiteHtml'
    }
}

Describe 'NeuronTargets.example.csv -- template contract' {
    It 'Template file exists' {
        $templatePath | Should -Exist
    }

    It 'Provides the expected columns' {
        $header = Get-Content -Path $templatePath -First 1
        $header | Should -Be 'NeuronHost,ExpectedMAC,ExpectedSerial,Site,Room,Notes'
    }
}
