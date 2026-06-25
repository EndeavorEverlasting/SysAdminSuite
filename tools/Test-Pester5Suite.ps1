<#
.SYNOPSIS
    Runs the SysAdminSuite Pester suite with a strict Pester 5 requirement.

.DESCRIPTION
    Provides a single test entrypoint that fails fast with a clear action when
    Pester 5 is unavailable. This avoids ambiguous failures under Pester 3.
#>
[CmdletBinding()]
param(
    [string]$TestPath = '.\Tests\Pester'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pesterModule = Get-Module -ListAvailable -Name Pester |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pesterModule -or $pesterModule.Version.Major -lt 5) {
    throw @"
Pester 5.0+ is required to run this suite.
Detected: $($pesterModule.Version)
Install on a trusted build/test machine:
  Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
"@
}

Import-Module Pester -RequiredVersion $pesterModule.Version -Force

$config = New-PesterConfiguration
$config.Run.Path = $TestPath
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = '.\_out\pester-results.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

$result = Invoke-Pester -Configuration $config
$failed = 0
if ($null -ne $result -and $result.PSObject.Properties['FailedCount']) {
    $failed = [int]$result.FailedCount
} elseif ($null -ne $result -and $result.PSObject.Properties['Failed']) {
    $failed = @($result.Failed).Count
} elseif ($null -eq $result) {
    $failed = 1
}

if ($failed -gt 0) {
    Write-Host ''
    Write-Host '--- PESTER FAILURE SUMMARY ---' -ForegroundColor Red
    $failedItems = @()
    if ($null -ne $result -and $result.PSObject.Properties['Failed']) {
        $failedItems = @($result.Failed)
    }

    if ($failedItems.Count -gt 0) {
        foreach ($item in $failedItems) {
            $name = if ($item.PSObject.Properties['ExpandedPath']) { $item.ExpandedPath } elseif ($item.PSObject.Properties['Name']) { $item.Name } else { '<unknown test>' }
            $message = ''
            if ($item.PSObject.Properties['ErrorRecord'] -and $null -ne $item.ErrorRecord) {
                $message = [string]$item.ErrorRecord.Exception.Message
            }
            Write-Host ("FAILED: {0}" -f $name) -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($message)) {
                Write-Host ("  {0}" -f $message)
            }
        }
    }
    else {
        Write-Host 'Pester did not expose individual failed tests. Check _out/pester-results.xml for details.' -ForegroundColor Yellow
    }
    exit 1
}
