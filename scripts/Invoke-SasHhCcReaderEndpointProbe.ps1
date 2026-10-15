#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ReaderIPAddress,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$RemoteEndpoint,

    [Parameter(Mandatory=$true, Position=2)]
    [ValidateRange(1,65535)]
    [int]$RemotePort,

    [Parameter(Mandatory=$true, Position=3)]
    [string]$ApprovalRef,

    [AllowEmptyString()]
    [string]$ExpectedMac = '',

    [Parameter(Position=4)]
    [ValidateSet('UNCLASSIFIED','HOSPITAL_GUEST_SHARED','CONSUMER_LAB','PROTECTED_ENTERPRISE','OTHER_SHARED')]
    [string]$NetworkEnvironment = 'UNCLASSIFIED',

    [switch]$ValidateOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-SasEndpointResult {
    param(
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Result,
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )

    $outputRoot = Join-Path $RepoRoot 'survey\output\hh-cc-reader'
    [void](New-Item -ItemType Directory -Force -Path $outputRoot)
    $stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss-fff')
    $nonce = [Guid]::NewGuid().ToString('N').Substring(0,8)
    $path = Join-Path $outputRoot ("hh-cc-reader-endpoint-{0}-{1}.json" -f $stamp,$nonce)
    $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host ("EVIDENCE={0}" -f $path)
}

$reader = $null
if (-not [System.Net.IPAddress]::TryParse($ReaderIPAddress, [ref]$reader) -or
    $reader.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'ReaderIPAddress must be one explicit IPv4 address. CIDRs, ranges, wildcards, and host discovery are refused.'
}

$endpoint = $RemoteEndpoint.Trim()
if ([string]::IsNullOrWhiteSpace($endpoint)) {
    throw 'RemoteEndpoint must be one observed hostname or IPv4 address.'
}
$hostKind = [System.Uri]::CheckHostName($endpoint)
if ($hostKind -ne [System.UriHostNameType]::Dns -and
    $hostKind -ne [System.UriHostNameType]::IPv4) {
    throw 'RemoteEndpoint must be one DNS hostname or IPv4 address. CIDRs, ranges, wildcards, whitespace lists, and IPv6 are refused in this lane.'
}

$approval = $ApprovalRef.Trim()
if ($approval -notmatch '^[A-Za-z0-9][A-Za-z0-9._:@-]{1,127}    Write-Host 'CLASSIFICATION=ENDPOINT_INPUT_VALID'
    exit 0
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$result = [ordered]@{
    schema_version = 'sas-hh-cc-reader-endpoint-probe/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    organization = 'health-and-hospitals'
    mode = 'read-only'
    reader_ip = $reader.ToString()
    remote_endpoint = $endpoint
    remote_port = $RemotePort
    approval_ref = $approval
    approval_reference_supplied = $true
    expected_mac_supplied = $expectedMacSupplied
    network_environment = $NetworkEnvironment
    network_environment_classified = ($NetworkEnvironment -ne 'UNCLASSIFIED')
    remote_address = $null
    name_resolution_results = @()
    interface_alias = $null
    source_address = $null
    tcp_test_succeeded = $false
    classification = 'STARTED'
    ownership_proven = $false
    approval_proven = $false
    error = $null
}

Write-Host '=== H&H CC READER REMOTE ENDPOINT CORRELATION ==='
Write-Host ("READER={0}" -f $reader)
Write-Host ("REMOTE_ENDPOINT={0}" -f $endpoint)
Write-Host ("REMOTE_PORT={0}" -f $RemotePort)
Write-Host ("APPROVAL_REF={0}" -f $approval)
Write-Host ("NETWORK_ENVIRONMENT={0}" -f $NetworkEnvironment)
Write-Host 'NOTE: ApprovalRef records the operator-provided evidence reference; this command does not independently validate the external approval source.'

$exitCode = 0
try {
    $probe = Test-NetConnection -ComputerName $endpoint -Port $RemotePort -InformationLevel Detailed -WarningAction SilentlyContinue
    $result.remote_address = [string]$probe.RemoteAddress
    $result.name_resolution_results = @($probe.NameResolutionResults | ForEach-Object { [string]$_ })
    $result.interface_alias = [string]$probe.InterfaceAlias
    $result.source_address = [string]$probe.SourceAddress
    $result.tcp_test_succeeded = [bool]$probe.TcpTestSucceeded
    $result.classification = 'REMOTE_ENDPOINT_CORRELATION_COMPLETE'

    Write-Host ("REMOTE_ADDRESS={0}" -f $(if ($result.remote_address) { $result.remote_address } else { 'UNRESOLVED' }))
    Write-Host ("SOURCE={0}" -f $(if ($result.source_address) { $result.source_address } else { 'UNRESOLVED' }))
    Write-Host ("INTERFACE={0}" -f $(if ($result.interface_alias) { $result.interface_alias } else { 'UNRESOLVED' }))
    Write-Host ("TCP_{0}={1}" -f $RemotePort,$result.tcp_test_succeeded)
    Write-Host 'CLASSIFICATION=REMOTE_ENDPOINT_CORRELATION_COMPLETE'
    Write-Host 'NOTE: endpoint reachability does not identify service ownership or prove a firmware-management path.'
}
catch {
    $result.classification = 'REMOTE_ENDPOINT_TEST_ERROR'
    $result.error = $_.Exception.Message
    $exitCode = 7
    Write-Host 'CLASSIFICATION=REMOTE_ENDPOINT_TEST_ERROR'
    Write-Host ("ERROR={0}" -f $result.error)
}

try {
    Write-SasEndpointResult -Result $result -RepoRoot $repoRoot
}
catch {
    Write-Error ("Endpoint correlation evidence could not be persisted: {0}" -f $_.Exception.Message)
    exit 8
}

exit $exitCode
) {
    throw 'ApprovalRef must be a non-secret 2-128 character evidence/ticket token using only letters, numbers, dot, underscore, colon, at-sign, or hyphen.'
}

$expectedMacSupplied = -not [string]::IsNullOrWhiteSpace($ExpectedMac)
if ($expectedMacSupplied -and $NetworkEnvironment -eq 'UNCLASSIFIED') {
    throw 'NetworkEnvironment must be explicitly classified when ExpectedMac is supplied.'
}

if ($ValidateOnly) {
    Write-Host 'CLASSIFICATION=ENDPOINT_INPUT_VALID'
    exit 0
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$result = [ordered]@{
    schema_version = 'sas-hh-cc-reader-endpoint-probe/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    organization = 'health-and-hospitals'
    mode = 'read-only'
    reader_ip = $reader.ToString()
    remote_endpoint = $endpoint
    remote_port = $RemotePort
    approval_ref = $approval
    approval_reference_supplied = $true
    network_environment = $NetworkEnvironment
    network_environment_classified = ($NetworkEnvironment -ne 'UNCLASSIFIED')
    remote_address = $null
    name_resolution_results = @()
    interface_alias = $null
    source_address = $null
    tcp_test_succeeded = $false
    classification = 'STARTED'
    ownership_proven = $false
    approval_proven = $false
    error = $null
}

Write-Host '=== H&H CC READER REMOTE ENDPOINT CORRELATION ==='
Write-Host ("READER={0}" -f $reader)
Write-Host ("REMOTE_ENDPOINT={0}" -f $endpoint)
Write-Host ("REMOTE_PORT={0}" -f $RemotePort)
Write-Host ("APPROVAL_REF={0}" -f $approval)
Write-Host ("NETWORK_ENVIRONMENT={0}" -f $NetworkEnvironment)
Write-Host 'NOTE: ApprovalRef records the operator-provided evidence reference; this command does not independently validate the external approval source.'

$exitCode = 0
try {
    $probe = Test-NetConnection -ComputerName $endpoint -Port $RemotePort -InformationLevel Detailed -WarningAction SilentlyContinue
    $result.remote_address = [string]$probe.RemoteAddress
    $result.name_resolution_results = @($probe.NameResolutionResults | ForEach-Object { [string]$_ })
    $result.interface_alias = [string]$probe.InterfaceAlias
    $result.source_address = [string]$probe.SourceAddress
    $result.tcp_test_succeeded = [bool]$probe.TcpTestSucceeded
    $result.classification = 'REMOTE_ENDPOINT_CORRELATION_COMPLETE'

    Write-Host ("REMOTE_ADDRESS={0}" -f $(if ($result.remote_address) { $result.remote_address } else { 'UNRESOLVED' }))
    Write-Host ("SOURCE={0}" -f $(if ($result.source_address) { $result.source_address } else { 'UNRESOLVED' }))
    Write-Host ("INTERFACE={0}" -f $(if ($result.interface_alias) { $result.interface_alias } else { 'UNRESOLVED' }))
    Write-Host ("TCP_{0}={1}" -f $RemotePort,$result.tcp_test_succeeded)
    Write-Host 'CLASSIFICATION=REMOTE_ENDPOINT_CORRELATION_COMPLETE'
    Write-Host 'NOTE: endpoint reachability does not identify service ownership or prove a firmware-management path.'
}
catch {
    $result.classification = 'REMOTE_ENDPOINT_TEST_ERROR'
    $result.error = $_.Exception.Message
    $exitCode = 7
    Write-Host 'CLASSIFICATION=REMOTE_ENDPOINT_TEST_ERROR'
    Write-Host ("ERROR={0}" -f $result.error)
}

try {
    Write-SasEndpointResult -Result $result -RepoRoot $repoRoot
}
catch {
    Write-Error ("Endpoint correlation evidence could not be persisted: {0}" -f $_.Exception.Message)
    exit 8
}

exit $exitCode
