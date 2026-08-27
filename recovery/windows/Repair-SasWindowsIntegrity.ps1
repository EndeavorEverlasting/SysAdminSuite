[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-RepairResult {
    param([Parameter(Mandatory)]$Result)

    $json = $Result | ConvertTo-Json -Depth 8
    if ($ReportPath) {
        $parent = Split-Path -Parent $ReportPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $ReportPath -Value $json -Encoding UTF8
    }
    $json
}

$plan = @(
    'Resolve repository-owned organization/site profile authority',
    'Resolve repository-owned equipment profile authority',
    'Resolve an approved local Windows repair source',
    'DISM.exe /Online /Cleanup-Image /RestoreHealth /Source:<approved-local-source> /LimitAccess',
    'sfc.exe /scannow',
    'Repair-WindowsImage -Online -ScanHealth',
    'sfc.exe /verifyonly'
)

if (-not $Apply) {
    Write-RepairResult -Result ([pscustomobject]@{
        schema_version = '1.0'
        status = 'plan_only'
        mutation_performed = $false
        network_access_attempted = $false
        requires_administrator = $true
        requires_profile_authority = $true
        sequence = $plan
        note = 'This generic recovery lane has no canonical organization/site plus equipment-profile repair authority. -Apply therefore fails closed until a profile-specific authority is added and validated. RestoreHealth is planned with an approved local source plus /LimitAccess so repair cannot implicitly contact Windows Update or WSUS.'
        proof_ceiling = 'Plan only; no Windows integrity mutation or network access was attempted.'
    })
    exit 0
}

# Repository governance requires both organization/site and equipment-profile
# authority before repair mutation. No generic workstation repair authority is
# currently registered, so this lane must fail closed rather than treating
# elevation, hostname, model, or operator intent as profile proof.
Write-RepairResult -Result ([pscustomobject]@{
    schema_version = '1.0'
    status = 'blocked_profile_authority_unavailable'
    mutation_performed = $false
    network_access_attempted = $false
    requires_administrator = $true
    requires_profile_authority = $true
    sequence = $plan
    reason = 'No canonical generic organization/site plus equipment-profile authorization authority exists for Windows integrity repair in this repository.'
    next_gate = 'Add and validate a profile-specific repair authority before enabling any RestoreHealth or SFC mutation path.'
    proof_ceiling = 'Fail-closed authorization proof only; no DISM/SFC repair command or network access was attempted.'
})
exit 3
