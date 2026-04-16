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
$config.Output.Verbosity = 'Detailed'
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
    exit 1
}
