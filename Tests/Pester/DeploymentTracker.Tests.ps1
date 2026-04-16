#Requires -Modules Pester
<#
.SYNOPSIS
  Offline tests for DeploymentTracker reconciliation (no AD, no ImportExcel required).
#>

BeforeAll {
  $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $script:corePath = Join-Path $script:repoRoot 'DeploymentTracker\DeploymentTracker.Core.psm1'
  $script:comparePath = Join-Path $script:repoRoot 'DeploymentTracker\Compare-DeploymentToAd.ps1'
  $script:fixtureDep = Join-Path $script:repoRoot 'Tests\Fixtures\DeploymentTracker\deployments.csv'
  $script:fixtureTix = Join-Path $script:repoRoot 'Tests\Fixtures\DeploymentTracker\tickets.csv'
  Import-Module -Name $script:corePath -Force
}

Describe 'DeploymentTracker.Core.psm1' {
  It 'Get-TicketHostnameSet splits newlines and normalizes case' {
    $rows = @(
      [pscustomobject]@{ 'Hostname Used' = "AaBb`nCcDd" }
    )
    $s = Get-TicketHostnameSet -TicketRows $rows
    $s.Contains('AABB') | Should -Be $true
    $s.Contains('CCDD') | Should -Be $true
  }

  It 'ConvertTo-MacCompareKey strips separators' {
    (ConvertTo-MacCompareKey -Mac 'aa-bb-cc-dd-ee-ff') | Should -Be 'AABBCCDDEEFF'
    (ConvertTo-MacCompareKey -Mac 'AA:BB:CC:DD:EE:FF') | Should -Be 'AABBCCDDEEFF'
  }

  It 'Test-IsNeuronOnlyRow is true only for Deployed Yes and Device Type Neuron' {
    $r1 = [pscustomobject]@{ Deployed = 'Yes'; 'Device Type' = 'Neuron' }
    $r2 = [pscustomobject]@{ Deployed = 'Yes'; 'Device Type' = 'Cybernet-Neuron' }
    $r3 = [pscustomobject]@{ Deployed = 'No'; 'Device Type' = 'Neuron' }
    Test-IsNeuronOnlyRow -Row $r1 | Should -Be $true
    Test-IsNeuronOnlyRow -Row $r2 | Should -Be $false
    Test-IsNeuronOnlyRow -Row $r3 | Should -Be $false
  }

  It 'Test-PeripheralsAllowedSite matches LIJ four-site keywords' {
    $ok = [pscustomobject]@{
      'Current Building' = 'LIJ Plainview Hospital'
      'Install Building' = ''
      'Area/Unit/Dept'   = ''
    }
    $bad = [pscustomobject]@{
      'Current Building' = 'NSUH - PSP'
      'Install Building' = ''
      'Area/Unit/Dept'   = ''
    }
    Test-PeripheralsAllowedSite -Row $ok | Should -Be $true
    Test-PeripheralsAllowedSite -Row $bad | Should -Be $false
  }

  It 'Set-DeploymentDupMetadata flags duplicate Cybernet hostname across locations' {
    $rows = [System.Collections.Generic.List[object]]::new()
    $rows.Add([pscustomobject]@{
        'Device Type' = 'Cybernet-Neuron'; Deployed = 'Yes'
        'Current Building' = 'A'; 'Install Building' = 'A'; 'Area/Unit/Dept' = 'U1'; Room = '1'; Bay = ''
        'Cybernet Hostname' = 'DUPHOST'; 'Neuron Hostname' = 'N1'
        'Neuron MAC' = '11:11:11:11:11:11'; 'Cybernet Serial' = 'S1'; 'Neuron S/N' = ''; 'Cybernet MAC' = ''; 'Anesthesia S/N' = ''; 'Medical Device S/N' = ''
      })
    $rows.Add([pscustomobject]@{
        'Device Type' = 'Cybernet-Neuron'; Deployed = 'Yes'
        'Current Building' = 'B'; 'Install Building' = 'B'; 'Area/Unit/Dept' = 'U2'; Room = '2'; Bay = ''
        'Cybernet Hostname' = 'DUPHOST'; 'Neuron Hostname' = 'N2'
        'Neuron MAC' = '22:22:22:22:22:22'; 'Cybernet Serial' = 'S2'; 'Neuron S/N' = ''; 'Cybernet MAC' = ''; 'Anesthesia S/N' = ''; 'Medical Device S/N' = ''
      })
    Set-DeploymentDupMetadata -Rows $rows
    $rows[0].DupDeployedCalculated | Should -Be 'Yes'
    $rows[0].DuplicateProblematicColumns | Should -Match 'Cybernet Hostname'
    $rows[1].DuplicateProblematicColumns | Should -Match 'Cybernet Hostname'
  }
}

Describe 'Compare-DeploymentToAd.ps1 (CSV, -SkipAd)' {
  It 'Runs against fixtures and writes CSV' {
    $out = Join-Path $TestDrive 'out'
    & $script:comparePath -DeploymentCsv $script:fixtureDep -TicketCsv $script:fixtureTix -SkipAd -OutputDirectory $out
    $csv = Get-ChildItem -LiteralPath $out -Filter 'DeploymentAdReconcile-*.csv' | Select-Object -First 1
    $csv | Should -Not -BeNullOrEmpty
    $data = Import-Csv -LiteralPath $csv.FullName
    $neu = $data | Where-Object { $_.IsNeuronOnly -eq 'True' -or $_.IsNeuronOnly -eq $true }
    @($neu).Count | Should -Be 1
    $badPeriph = $data | Where-Object { $_.'Device Type' -eq 'Peripherals' -and $_.PeripheralsAllowedSite -eq 'False' }
    @($badPeriph).Count | Should -Be 1
    $tixRow = $data | Where-Object { $_.'Cybernet Hostname' -eq 'HOSTTIX' }
    $tixRow.Cybernet_InTicketHostnameUsed | Should -Be 'True'
  }
}
