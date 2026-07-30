#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Get-SasAutoLogonPolicyProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Test-SasAutoLogonFirstInstallBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot
    )

    if ($null -eq $Snapshot) { return $false }
    $auto = Get-SasAutoLogonPolicyProperty -Object $Snapshot -Name 'autologon'
    if ($null -eq $auto) { return $false }

    $installed = @(
        @(Get-SasAutoLogonPolicyProperty -Object $Snapshot -Name 'installed_software' -Default @()) |
            Where-Object { [string](Get-SasAutoLogonPolicyProperty -Object $_ -Name 'name') -match '(?i)NW\s+AutoLogon\s+Setup' }
    )
    if ($installed.Count -ne 0) { return $false }

    $status = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'status')
    if ($status -eq 'not_configured') { return $true }
    if ($status -ne 'intent_only') { return $false }

    $intent = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'postinstall_set_autologon')
    $autoAdminLogon = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'auto_admin_logon')
    $defaultUser = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'default_user_name')
    $defaultDomain = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'default_domain_name')
    $forceAutoLogon = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'force_auto_logon')
    $autoLogonCount = [string](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'auto_logon_count')
    $passwordPresent = [bool](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'default_password_present' -Default $false)
    $expectedUserMatch = [bool](Get-SasAutoLogonPolicyProperty -Object $auto -Name 'expected_user_match' -Default $false)

    return (
        $intent -eq 'Autologon_YES' -and
        $autoAdminLogon.Trim() -in @('','0','0x0') -and
        [string]::IsNullOrWhiteSpace($defaultUser) -and
        [string]::IsNullOrWhiteSpace($defaultDomain) -and
        [string]::IsNullOrWhiteSpace($forceAutoLogon) -and
        [string]::IsNullOrWhiteSpace($autoLogonCount) -and
        -not $passwordPresent -and
        -not $expectedUserMatch
    )
}

Export-ModuleMember -Function Test-SasAutoLogonFirstInstallBaseline
