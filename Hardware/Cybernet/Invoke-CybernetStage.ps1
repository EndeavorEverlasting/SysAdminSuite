#Requires -Version 5.1
<#
.SYNOPSIS
Invoke one tracked Cybernet hardware stage from a JSON parameter document.

.DESCRIPTION
Used by Invoke-CybernetBatchConfiguration.ps1 to preserve string-array targets and switch values across
a bounded child PowerShell process. The parameter document is generated under the ignored run root.
This helper does not select stages, discover targets, elevate, or grant mutation authority.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$ParameterJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw "Stage script not found: $ScriptPath" }
if (-not (Test-Path -LiteralPath $ParameterJson -PathType Leaf)) { throw "Stage parameter JSON not found: $ParameterJson" }

$document = Get-Content -LiteralPath $ParameterJson -Raw -Encoding UTF8 | ConvertFrom-Json
$parameters = @{}
foreach ($property in $document.PSObject.Properties) {
    if ($null -eq $property.Value) { continue }
    if ($property.Value -is [System.Array]) {
        $parameters[$property.Name] = @($property.Value)
    }
    else {
        $parameters[$property.Name] = $property.Value
    }
}

& $ScriptPath @parameters
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }
exit $exitCode
