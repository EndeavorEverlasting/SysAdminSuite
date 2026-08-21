#Requires -Version 5.1
Set-StrictMode -Version 2.0

$script:SasNetworkIntentSchema = 'sas-network-intent-transition/v1'
$script:SasProtectedBookmarkSchema = 'sas-protected-wlan-bookmark/v1'

function Import-SasNetworkIntentDependencies {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepoRoot)

    foreach ($relative in @(
        'scripts\SasOperatorSession.psm1',
        'scripts\SasFieldPlatform.psm1',
        'scripts\SasNetworkGuard.psm1',
        'scripts\SasBoundedNative.psm1'
    )) {
        $path = Join-Path $RepoRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing network-intent dependency: $path"
        }
        Import-Module $path -Force
    }
}

function Get-SasNetworkIntentDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('InternetSync','ProtectedNorthwell','LocalOnly','CommandSpecific')][string]$Intent)

    switch ($Intent) {
        'InternetSync' {
            return [pscustomobject][ordered]@{
                intent=$Intent; required='GUEST / INTERNET'; purpose='remote repository synchronization only'
            }
        }
        'ProtectedNorthwell' {
            return [pscustomobject][ordered]@{
                intent=$Intent; required='PROTECTED NORTHWELL'; purpose='Northwell target access: hardwire, NSLIJHS-WAB, or authenticated DomainAuthenticated VPN'
            }
        }
        'LocalOnly' {
            return [pscustomobject][ordered]@{
                intent=$Intent; required='ANY / UNCHANGED'; purpose='local-only operation; SysAdminSuite must not change the network'
            }
        }
        default {
            return [pscustomobject][ordered]@{
                intent=$Intent; required='COMMAND-SPECIFIC / UNCHANGED'; purpose='delegated command owns any additional network gate'
            }
        }
    }
}

function Get-SasNetworkIntentState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepoRoot)

    Import-SasNetworkIntentDependencies -RepoRoot $RepoRoot
    $classification = Get-SasOperatorNetworkClassification -RepoRoot $RepoRoot
    $authority = Get-SasProtectedNetworkAuthority -RepoRoot $RepoRoot
    return [pscustomobject][ordered]@{
        classification=[string]$classification.classification
        label=[string]$classification.label
        protected=[bool]$classification.protected
        authority=[string]$authority.authority
        authority_approved=[bool]$authority.approved
        interface_alias=[string]$authority.interface_alias
        network_label=[string]$authority.network_label
    }
}

function Write-SasNetworkCanary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('InternetSync','ProtectedNorthwell','LocalOnly','CommandSpecific')][string]$Intent,
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [string]$TransitionStatus='NOT_EVALUATED'
    )

    $definition = Get-SasNetworkIntentDefinition -Intent $Intent
    $state = Get-SasNetworkIntentState -RepoRoot $RepoRoot
    Write-Host ''
    Write-Host '=== NETWORK CANARY ===' -ForegroundColor Cyan
    Write-Host "NETWORK REQUIRED: $($definition.required)"
    Write-Host "NETWORK PURPOSE:  $($definition.purpose)"
    Write-Host "CURRENT NETWORK:  $($state.classification) [$($state.label)]"
    Write-Host "CURRENT AUTHORITY: $($state.authority) [$($state.interface_alias)]"
    Write-Host "AUTO-SWITCH:       $TransitionStatus"
    return $state
}

function Test-SasSavedWlanProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [ValidateRange(3,30)][int]$NativeTimeoutSeconds=10
    )

    Import-SasNetworkIntentDependencies -RepoRoot $RepoRoot
    $netsh = Join-Path $env:WINDIR 'System32\netsh.exe'
    # Do not parse localized netsh labels. Ask Windows for the exact profile and use only
    # the native exit code as profile-existence proof.
    $result = Invoke-SasBoundedNative -FilePath $netsh -Arguments @('wlan','show','profile',("name={0}" -f $ProfileName)) -TimeoutSeconds $NativeTimeoutSeconds
    if ($result.timed_out) { throw "Timed out validating saved WLAN profile after $NativeTimeoutSeconds seconds: $ProfileName" }
    return ($result.exit_code -eq 0)
}

function Invoke-SasSavedWlanConnect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [ValidateRange(10,90)][int]$TransitionTimeoutSeconds=30,
        [ValidateRange(3,30)][int]$NativeTimeoutSeconds=10
    )

    Import-SasNetworkIntentDependencies -RepoRoot $RepoRoot
    if (-not (Test-SasSavedWlanProfile -RepoRoot $RepoRoot -ProfileName $ProfileName -NativeTimeoutSeconds $NativeTimeoutSeconds)) {
        throw "Automatic WLAN transition refused: exact saved profile is unavailable in Windows: $ProfileName"
    }

    $netsh = Join-Path $env:WINDIR 'System32\netsh.exe'
    $result = Invoke-SasBoundedNative -FilePath $netsh -Arguments @('wlan','connect',("name={0}" -f $ProfileName)) -TimeoutSeconds $NativeTimeoutSeconds
    if ($result.timed_out) { throw "Timed out asking Windows to connect to saved WLAN profile: $ProfileName" }
    if ($result.exit_code -ne 0) { throw "Windows rejected saved WLAN profile $ProfileName. Exit=$($result.exit_code) $($result.error)" }

    $deadline = (Get-Date).AddSeconds($TransitionTimeoutSeconds)
    $observed = 'unknown'
    while ((Get-Date) -lt $deadline) {
        $observed = Get-SasCurrentWifiSsid
        if (-not [string]::IsNullOrWhiteSpace([string]$observed)) {
            if ([string]$observed -eq [string]$ProfileName) { return [string]$observed }
        }
        Start-Sleep -Seconds 2
    }
    throw "Windows accepted the saved WLAN request, but profile $ProfileName was not observed within $TransitionTimeoutSeconds seconds. Last observed: $observed"
}

function Read-SasInternetReturnBookmark {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepoRoot)

    Import-SasNetworkIntentDependencies -RepoRoot $RepoRoot
    $path = Join-Path (Get-SasOperatorStateRoot) 'return-network.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Saved Guest/Internet return bookmark is unreadable: $path" }
    if ([string]$value.schema_version -ne 'sas-operator-return-network/v1' -or [string]$value.classification -ne 'GUEST_INTERNET') {
        throw "Saved Guest/Internet return bookmark is not authoritative: $path"
    }
    if ([string]::IsNullOrWhiteSpace([string]$value.label) -or [string]$value.label -eq 'unknown') {
        throw "Saved Guest/Internet return bookmark has no usable WLAN label: $path"
    }
    if (Test-SasNorthwellWifiSsid -Ssid ([string]$value.label)) {
        throw 'Saved Guest/Internet return bookmark points to a protected Northwell WLAN; refusing automatic transition.'
    }
    return $value
}

function Write-SasProtectedWlanBookmark {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)][string]$Label
    )

    Import-SasNetworkIntentDependencies -RepoRoot $RepoRoot
    if (-not (Test-SasNorthwellWifiSsid -Ssid $Label)) { return $null }
    $path = Join-Path (Get-SasOperatorStateRoot) 'protected-network.json'
    [pscustomobject][ordered]@{
        schema_version=$script:SasProtectedBookmarkSchema
        classification='PROTECTED_NORTHWELL'
        authority='WAB_WIFI'
        label=$Label
        recorded_utc=(Get-Date).ToUniversalTime().ToString('o')
        target_contact_performed=$false
        target_mutation_performed=$false
        secret_material_collected=$false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Read-SasProtectedWlanBookmark {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepoRoot)

    Import-SasNetworkIntentDependencies -RepoRoot $RepoRoot
    $path = Join-Path (Get-SasOperatorStateRoot) 'protected-network.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $null }
    if ([string]$value.schema_version -ne $script:SasProtectedBookmarkSchema) { return $null }
    if ([string]$value.authority -ne 'WAB_WIFI') { return $null }
    if (-not (Test-SasNorthwellWifiSsid -Ssid ([string]$value.label))) { return $null }
    return $value
}

function Enter-SasNetworkIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('InternetSync','ProtectedNorthwell','LocalOnly','CommandSpecific')][string]$Intent,
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [switch]$AllowAutomaticWlanTransition
    )

    $before = Write-SasNetworkCanary -Intent $Intent -RepoRoot $RepoRoot -TransitionStatus 'evaluating'
    $transition = [pscustomobject][ordered]@{
        schema_version=$script:SasNetworkIntentSchema
        intent=$Intent
        before_classification=[string]$before.classification
        before_label=[string]$before.label
        before_authority=[string]$before.authority
        switched=$false
        switch_method='NONE'
        restore_required=$false
        restore_profile=$null
        status='ALREADY_SATISFIED'
    }

    if ($Intent -in @('LocalOnly','CommandSpecific')) {
        $transition.status = 'UNCHANGED_BY_POLICY'
        Write-Host "NETWORK DECISION: $($transition.status)" -ForegroundColor Green
        return $transition
    }

    if ($Intent -eq 'InternetSync') {
        if ([string]$before.classification -eq 'GUEST_INTERNET') {
            Write-Host 'NETWORK DECISION: Guest/Internet already active; no switch required.' -ForegroundColor Green
            return $transition
        }
        if ([string]$before.authority -eq 'DOMAIN_AUTHENTICATED_VPN') {
            throw 'SAS_NETWORK_TRANSITION_MANUAL_VPN_REQUIRED: NETWORK REQUIRED: GUEST / INTERNET. CURRENT NETWORK: authenticated DomainAuthenticated VPN. Disconnect the VPN while keeping ordinary Internet connected, rerun the command, then reconnect the VPN. SysAdminSuite did not change the VPN because no repository-proven VPN client lifecycle adapter is installed.'
        }
        if ([string]$before.authority -eq 'DOMAIN_AUTHENTICATED_WIRED') {
            throw 'SAS_NETWORK_TRANSITION_MANUAL_WIRED_REQUIRED: NETWORK REQUIRED: GUEST / INTERNET. CURRENT NETWORK: protected hardwire/LAN. Move to an ordinary Internet path before repository synchronization. SysAdminSuite did not disable the wired adapter.'
        }
        if ([string]$before.authority -ne 'WAB_WIFI') {
            throw "SAS_NETWORK_TRANSITION_UNPROVEN: NETWORK REQUIRED: GUEST / INTERNET. Current network could not be safely transitioned automatically: $($before.classification) [$($before.label)] / $($before.authority)."
        }
        if (-not $AllowAutomaticWlanTransition) {
            throw 'SAS_NETWORK_TRANSITION_REQUIRED: Guest/Internet is required and automatic saved-WLAN switching was not enabled for this command.'
        }

        [void](Write-SasProtectedWlanBookmark -RepoRoot $RepoRoot -Label ([string]$before.network_label))
        $return = Read-SasInternetReturnBookmark -RepoRoot $RepoRoot
        if ($null -eq $return) {
            throw 'SAS_NETWORK_TRANSITION_NO_GUEST_BOOKMARK: no exact Guest/Internet WLAN bookmark is available. Select an ordinary Internet network manually and run sas refresh once; future WAB refreshes can then return automatically.'
        }
        $guestLabel = [string]$return.label
        Write-Host "NETWORK AUTO-SWITCH: WAB -> saved Guest/Internet [$guestLabel]" -ForegroundColor Cyan
        try {
            [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName $guestLabel)
            $after = Get-SasNetworkIntentState -RepoRoot $RepoRoot
            if ([string]$after.classification -ne 'GUEST_INTERNET' -or [string]$after.label -ne $guestLabel) {
                throw "Guest/Internet transition was not proven. Observed: $($after.classification) [$($after.label)] / $($after.authority)"
            }
        }
        catch {
            try { [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName ([string]$before.network_label)) } catch { }
            throw
        }
        $transition.switched = $true
        $transition.switch_method = 'SAVED_WLAN_PROFILE'
        $transition.restore_required = $true
        $transition.restore_profile = [string]$before.network_label
        $transition.status = 'AUTO_SWITCHED_TO_INTERNET'
        Write-Host "NETWORK DECISION: $($transition.status); restore scheduled to [$($transition.restore_profile)]." -ForegroundColor Green
        return $transition
    }

    if ($Intent -eq 'ProtectedNorthwell') {
        if ([bool]$before.authority_approved) {
            if ([string]$before.authority -eq 'WAB_WIFI' -and -not [string]::IsNullOrWhiteSpace([string]$before.network_label)) {
                [void](Write-SasProtectedWlanBookmark -RepoRoot $RepoRoot -Label ([string]$before.network_label))
            }
            Write-Host 'NETWORK DECISION: protected Northwell authority already active; no switch required.' -ForegroundColor Green
            return $transition
        }

        if ($AllowAutomaticWlanTransition -and [string]$before.classification -eq 'GUEST_INTERNET') {
            $return = Read-SasInternetReturnBookmark -RepoRoot $RepoRoot
            $protectedBookmark = Read-SasProtectedWlanBookmark -RepoRoot $RepoRoot
            $sameGuest = $false
            if ($null -ne $return -and -not [string]::IsNullOrWhiteSpace([string]$return.label) -and -not [string]::IsNullOrWhiteSpace([string]$before.label)) {
                $sameGuest = ([string]$return.label -eq [string]$before.label)
            }
            if ($sameGuest -and $null -ne $protectedBookmark) {
                $protectedLabel = [string]$protectedBookmark.label
                Write-Host "NETWORK AUTO-SWITCH: saved Guest/Internet -> saved WAB [$protectedLabel]" -ForegroundColor Cyan
                try {
                    [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName $protectedLabel)
                    $after = Get-SasNetworkIntentState -RepoRoot $RepoRoot
                    if (-not [bool]$after.authority_approved -or [string]$after.authority -ne 'WAB_WIFI') {
                        throw "Protected WAB transition was not proven. Observed: $($after.classification) [$($after.label)] / $($after.authority)"
                    }
                }
                catch {
                    try { [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName ([string]$before.label)) } catch { }
                    throw
                }
                $transition.switched = $true
                $transition.switch_method = 'SAVED_WLAN_PROFILE'
                $transition.restore_required = $true
                $transition.restore_profile = [string]$before.label
                $transition.status = 'AUTO_SWITCHED_TO_PROTECTED_WAB'
                Write-Host "NETWORK DECISION: $($transition.status); restore scheduled to [$($transition.restore_profile)]." -ForegroundColor Green
                return $transition
            }
        }

        throw 'SAS_NETWORK_TRANSITION_PROTECTED_REQUIRED: NETWORK REQUIRED: PROTECTED NORTHWELL. Connect Northwell hardwire, NSLIJHS-WAB, or an authenticated DomainAuthenticated VPN, then rerun the command. SysAdminSuite did not guess or manipulate an unproven VPN client.'
    }

    return $transition
}

function Restore-SasNetworkIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Transition,
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )

    if (-not [bool]$Transition.restore_required) {
        Write-Host 'NETWORK RESTORE: not required; original network posture was left unchanged.' -ForegroundColor DarkGray
        return
    }

    $profile = [string]$Transition.restore_profile
    if ([string]::IsNullOrWhiteSpace($profile)) {
        throw 'SAS_NETWORK_RESTORE_FAILED: transition requested restoration but no saved WLAN profile was recorded.'
    }

    Write-Host "NETWORK RESTORE: returning to saved WLAN profile [$profile]" -ForegroundColor Cyan
    [void](Invoke-SasSavedWlanConnect -RepoRoot $RepoRoot -ProfileName $profile)
    $after = Get-SasNetworkIntentState -RepoRoot $RepoRoot

    if ([string]$Transition.before_classification -eq 'GUEST_INTERNET') {
        if ([string]$after.classification -ne 'GUEST_INTERNET' -or [string]$after.label -ne $profile) {
            throw "SAS_NETWORK_RESTORE_FAILED: expected Guest/Internet [$profile], observed $($after.classification) [$($after.label)] / $($after.authority)."
        }
    }
    elseif ([string]$Transition.before_authority -eq 'WAB_WIFI') {
        if ([string]$after.authority -ne 'WAB_WIFI' -or [string]$after.network_label -ne $profile) {
            throw "SAS_NETWORK_RESTORE_FAILED: expected protected WAB [$profile], observed $($after.classification) [$($after.label)] / $($after.authority)."
        }
    }

    Write-Host "NETWORK RESTORED: $($after.classification) [$($after.label)] / $($after.authority)" -ForegroundColor Green
}

Export-ModuleMember -Function Get-SasNetworkIntentDefinition,Get-SasNetworkIntentState,Write-SasNetworkCanary,Test-SasSavedWlanProfile,Invoke-SasSavedWlanConnect,Read-SasInternetReturnBookmark,Write-SasProtectedWlanBookmark,Read-SasProtectedWlanBookmark,Enter-SasNetworkIntent,Restore-SasNetworkIntent
