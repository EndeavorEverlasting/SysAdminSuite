#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'modules\CybernetSubnetDiscovery'
    $script:surveyRoot = Join-Path $script:repoRoot 'modules\CybernetSurvey'

    . (Join-Path $script:moduleRoot 'Import-CybernetSerialInventory.ps1')
    . (Join-Path $script:moduleRoot 'Convert-IpToSubnetCandidate.ps1')
    . (Join-Path $script:moduleRoot 'Resolve-CybernetDnsIdentity.ps1')
    . (Join-Path $script:moduleRoot 'New-CybernetSubnetDiscoveryReport.ps1')
    . (Join-Path $script:surveyRoot 'New-CybernetScannerCommand.ps1')
}

Describe 'Normalize-CybernetSerial' {
    It 'Uppercases and removes whitespace' {
        Normalize-CybernetSerial -Value ' cn12345678 ' | Should -Be 'CN12345678'
    }

    It 'Returns empty for blank input' {
        Normalize-CybernetSerial -Value '   ' | Should -Be ''
    }
}

Describe 'Normalize-CybernetMac' {
    It 'Normalizes dash-separated MAC' {
        Normalize-CybernetMac -Value '00-11-22-33-44-55' | Should -Be '00:11:22:33:44:55'
    }

    It 'Normalizes colon-separated MAC' {
        Normalize-CybernetMac -Value 'aa:bb:cc:dd:ee:ff' | Should -Be 'AA:BB:CC:DD:EE:FF'
    }

    It 'Normalizes bare hex MAC' {
        Normalize-CybernetMac -Value '001122334455' | Should -Be '00:11:22:33:44:55'
    }
}

Describe 'Import-CybernetSerialInventory' {
    It 'Imports manifest with blank optional fields' {
        $csv = Join-Path $TestDrive 'serials.csv'
        @'
Site,Serial,ExpectedHostname,ExpectedMAC,ExpectedRoom,ExpectedStatus,Notes
SSUH,CN12345678,WNH269OPR009,00-11-22-33-44-55,OR-2,Configured,
SSUH,CN87654321,,,,Configured,Serial known only
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        $result = Import-CybernetSerialInventory -Path $csv -Site 'SSUH'
        $result.Rows.Count | Should -Be 2
        $result.Rows[1].ExpectedHostname | Should -Be ''
        $result.Rows[1].ExpectedMAC | Should -Be ''
    }

    It 'Detects duplicate serials' {
        $csv = Join-Path $TestDrive 'dupes.csv'
        @'
Site,Serial,ExpectedHostname,ExpectedMAC,ExpectedRoom,ExpectedStatus,Notes
SSUH,CN11111111,H1,,,, 
SSUH,CN11111111,H2,,,, 
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        $result = Import-CybernetSerialInventory -Path $csv -Site 'SSUH'
        $result.DuplicateSerials | Should -Contain 'CN11111111'
    }
}

Describe 'Import-CybernetSiteSubnets' {
    It 'Parses ApprovedForScan values' {
        $csv = Join-Path $TestDrive 'subnets.csv'
        @'
Site,Subnet,Description,ApprovedForScan
SSUH,10.20.30.0/24,OR Cybernet VLAN,true
SSUH,10.20.99.0/24,Disabled VLAN,false
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        $rows = Import-CybernetSiteSubnets -Path $csv -Site 'SSUH'
        $rows.Count | Should -Be 2
        ($rows | Where-Object { $_.Subnet -eq '10.20.30.0/24' }).ApprovedForScan | Should -Be $true
        ($rows | Where-Object { $_.Subnet -eq '10.20.99.0/24' }).ApprovedForScan | Should -Be $false
    }
}

Describe 'Convert-IpToSubnetCandidate' {
    It 'Maps IP to approved subnet' {
        $subnets = @(
            [pscustomobject]@{ Site = 'SSUH'; Subnet = '10.20.30.0/24'; Description = 'OR'; ApprovedForScan = $true; Source = 'SiteSubnets' }
        )
        $match = Convert-IpToSubnetCandidate -IPv4 '10.20.30.42' -ApprovedSubnets $subnets
        $match.SubnetCandidate | Should -Be '10.20.30.0/24'
        $match.ApprovedForScan | Should -Be $true
    }

    It 'Rejects public IP addresses' {
        $subnets = @(
            [pscustomobject]@{ Site = 'SSUH'; Subnet = '10.20.30.0/24'; Description = 'OR'; ApprovedForScan = $true; Source = 'SiteSubnets' }
        )
        $match = Convert-IpToSubnetCandidate -IPv4 '8.8.8.8' -ApprovedSubnets $subnets
        $match.IsPublic | Should -Be $true
        $match.Matched | Should -Be $false
    }

    It 'Rejects unapproved subnet matches' {
        $rows = @(
            [pscustomobject]@{ Site = 'SSUH'; Subnet = '10.20.30.0/24'; Description = 'OR'; ApprovedForScan = $false; Source = 'SiteSubnets' }
        )
        $match = Convert-IpToSubnetCandidate -IPv4 '10.20.30.42' -ApprovedSubnets $rows -RequireApprovedSubnet $true
        $match.Matched | Should -Be $true
        $match.ApprovedForScan | Should -Be $false
    }

    It 'Blocks documentation-range IPs as public' {
        $subnets = @(
            [pscustomobject]@{ Site = 'SSUH'; Subnet = '10.20.30.0/24'; Description = 'OR'; ApprovedForScan = $true; Source = 'SiteSubnets' }
        )
        $match = Convert-IpToSubnetCandidate -IPv4 '203.0.113.1' -ApprovedSubnets $subnets
        $match.IsPublic | Should -Be $true
    }
}

Describe 'Resolve-CybernetDnsIdentity' {
    It 'Parses mocked Resolve-DnsName output' {
        $mockResolver = {
            param($Name)
            @([pscustomobject]@{ Name = $Name; Type = 'A'; IPAddress = '10.20.30.88' })
        }

        $records = Resolve-CybernetDnsForward -Hostname 'WNH269OPR014' -DnsResolver $mockResolver
        @($records).Count | Should -Be 1
        $records[0].IP | Should -Be '10.20.30.88'
    }

    It 'Applies DNS results to inventory rows' {
        $mockResolver = {
            param($Name)
            @([pscustomobject]@{ Name = $Name; Type = 'A'; IPAddress = '10.20.30.42' })
        }

        $rows = @([pscustomobject]@{
            Site = 'SSUH'; Serial = 'CN12345678'; ExpectedHostname = 'WNH269OPR009'
            ExpectedMAC = '00:11:22:33:44:55'; ExpectedRoom = ''; ExpectedStatus = ''
            Notes = ''; IP = ''; SubnetCandidate = ''; SubnetSource = ''
            Confidence = 'Missing'; Evidence = ''
        })

        $updated = Apply-CybernetDnsToInventory -InventoryRows $rows -DnsResolver $mockResolver
        $updated[0].IP | Should -Be '10.20.30.42'
    }
}

Describe 'New-CybernetSubnetDiscoveryReport' {
    It 'Generates target IPs only for approved scope' {
        $subnets = @(
            [pscustomobject]@{ Site = 'SSUH'; Subnet = '10.20.30.0/24'; Description = 'OR'; ApprovedForScan = $true; Source = 'SiteSubnets' }
        )
        $inventory = @(
            [pscustomobject]@{ Site='SSUH'; Serial='CN1'; ExpectedHostname='H1'; ExpectedMAC=''; IP='10.20.30.10'; Evidence='' }
            [pscustomobject]@{ Site='SSUH'; Serial='CN2'; ExpectedHostname='H2'; ExpectedMAC=''; IP='8.8.8.8'; Evidence='' }
            [pscustomobject]@{ Site='SSUH'; Serial='CN3'; ExpectedHostname=''; ExpectedMAC=''; IP=''; Evidence='' }
        )

        $matches = foreach ($row in $inventory) {
            Convert-IpToSubnetCandidate -IPv4 $row.IP -ApprovedSubnets $subnets
        }

        $identity = New-CybernetIdentityMapRows -InventoryRows $inventory -SubnetMatches $matches
        $targets = New-CybernetTargetIpList -IdentityMapRows $identity
        $targets | Should -Contain '10.20.30.10'
        $targets | Should -Not -Contain '8.8.8.8'
        @($targets).Count | Should -Be 1
    }

    It 'Generates action items for Missing records' {
        $identity = @(
            [pscustomobject]@{
                Site='SSUH'; Serial='CN87654321'; Hostname=''; MAC=''; IP=''
                SubnetCandidate=''; SubnetSource=''; Confidence='Missing'
                Evidence='Serial has no hostname, MAC, IP, or subnet bridge'
            }
        )
        $md = New-CybernetActionItemsMarkdown -IdentityMapRows $identity -DuplicateSerials @()
        $md | Should -Match 'Missing bridge'
        $md | Should -Match 'CN87654321'
    }

    It 'Classifies unapproved subnet as Blocked' {
        $row = [pscustomobject]@{
            Site='SSUH'; Serial='CN9'; ExpectedHostname='H9'; ExpectedMAC=''; IP='10.20.30.50'; Evidence=''
        }
        $match = Convert-IpToSubnetCandidate -IPv4 $row.IP -ApprovedSubnets @(
            [pscustomobject]@{ Site='SSUH'; Subnet='10.20.30.0/24'; ApprovedForScan=$false; Source='SiteSubnets' }
        )
        $identity = New-CybernetIdentityMapRows -InventoryRows @($row) -SubnetMatches @($match)
        $identity[0].Confidence | Should -Be 'Blocked'
    }

    It 'Generates summary JSON with confidence counts' {
        $identity = @(
            [pscustomobject]@{ Site='SSUH'; Serial='CN1'; Hostname='H1'; MAC=''; IP='10.20.30.10'; SubnetCandidate='10.20.30.0/24'; SubnetSource='SiteSubnets'; Confidence='High'; Evidence='' }
            [pscustomobject]@{ Site='SSUH'; Serial='CN2'; Hostname=''; MAC=''; IP=''; SubnetCandidate=''; SubnetSource=''; Confidence='Missing'; Evidence='' }
        )
        $summary = New-CybernetDiscoverySummary -Site 'SSUH' -IdentityMapRows $identity -TargetIps @('10.20.30.10') -DuplicateSerials @() -DnsResolvedCount 1
        $summary.site | Should -Be 'SSUH'
        $summary.confidenceCounts.High | Should -Be 1
        $summary.confidenceCounts.Missing | Should -Be 1
        ($summary | ConvertTo-Json) | Should -Match 'confidenceCounts'
    }
}

Describe 'New-CybernetScannerCommand' {
    It 'Generates deterministic Naabu command' {
        $profilePath = Join-Path $script:repoRoot 'config\cybernet-port-profile.json'
        $profile = Get-CybernetPortProfile -ProfilePath $profilePath
        $cmd = New-CybernetNaabuCommand -TargetFile '.\targets.txt' -OutputFile '.\out.jsonl' -Profile $profile
        $cmd.Command | Should -Be 'naabu -list .\targets.txt -p 135,139,445,3389,5985,5986,80,443,8080,8443 -rate 50 -c 10 -retries 1 -timeout 1000 -json -silent -duc -o .\out.jsonl'
    }

    It 'Generates deterministic Nmap host discovery command' {
        $cmd = New-CybernetNmapHostDiscoveryCommand -TargetFile '.\targets.txt' -OutputFile '.\out.xml'
        $cmd.Command | Should -Be 'nmap -sn -iL .\targets.txt -oX .\out.xml'
    }

    It 'Generates deterministic Nmap selected-port command' {
        $profilePath = Join-Path $script:repoRoot 'config\cybernet-port-profile.json'
        $profile = Get-CybernetPortProfile -ProfilePath $profilePath
        $cmd = New-CybernetNmapSelectedPortCommand -TargetFile '.\targets.txt' -OutputFile '.\out.xml' -Profile $profile
        $cmd.Command | Should -Be 'nmap -p 135,139,445,3389,5985,5986,80,443,8080,8443 --open -iL .\targets.txt -oX .\out.xml'
    }
}

Describe 'Invoke-SASCybernetSubnetDiscovery.ps1 integration' {
    It 'Runs end-to-end without executing scanners' {
        $outDir = Join-Path $TestDrive 'discovery'
        $invokePath = Join-Path $script:moduleRoot 'Invoke-SASCybernetSubnetDiscovery.ps1'
        $serials = Join-Path $script:repoRoot 'input\cybernet-serials.example.csv'
        $subnets = Join-Path $script:repoRoot 'input\site-subnets.example.csv'

        $knownHosts = Join-Path $TestDrive 'known.csv'
        @(
            [pscustomobject]@{ Serial = 'CN12345678'; ExpectedHostname = 'WNH269OPR009'; IP = '10.20.30.42' }
        ) | Export-Csv -LiteralPath $knownHosts -NoTypeInformation

        & $invokePath `
            -Site 'SSUH' `
            -SerialInventoryPath $serials `
            -SiteSubnetsPath $subnets `
            -KnownHostsPath $knownHosts `
            -OutDir $outDir `
            -GenerateSurveyTargets

        @(
            'CybernetSubnetDiscovery_NormalizedSerials.csv',
            'CybernetSubnetDiscovery_IdentityMap.csv',
            'CybernetSubnetDiscovery_SubnetsToSurvey.csv',
            'CybernetSubnetDiscovery_TargetIPs.txt',
            'CybernetSubnetDiscovery_Summary.json',
            'CybernetSubnetDiscovery_ActionItems.md',
            'CybernetSubnetDiscovery_EvidenceLog.jsonl'
        ) | ForEach-Object {
            Join-Path $outDir $_ | Should -Exist
        }

        $log = Get-Content -LiteralPath (Join-Path $outDir 'CybernetSubnetDiscovery_EvidenceLog.jsonl') -Raw
        $log | Should -Match 'naabu -list'
        $log | Should -Match 'nmap -sn'
        $log | Should -Match 'not executed'

        $targets = Get-Content -LiteralPath (Join-Path $outDir 'CybernetSubnetDiscovery_TargetIPs.txt')
        $targets | Should -Contain '10.20.30.42'
    }
}
