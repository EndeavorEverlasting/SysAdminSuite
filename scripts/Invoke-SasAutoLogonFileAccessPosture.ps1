#Requires -Version 5.1
<#
.SYNOPSIS
Capture and compare read-only AutoLogon file-access posture on approved workstations.

.DESCRIPTION
Collects a bounded NTFS ACL posture for expected-user and operator-supplied target-local
directories. It also records the expected AutoLogon profile, loaded user-shell-folder
redirections, and mapped-drive registry metadata.

The collector does not enumerate directory contents, contact redirected UNC paths, impersonate
the AutoLogon account, calculate effective access, or write evidence to target workstations.
Evidence is returned through PowerShell remoting and stored only under the approved local,
gitignored SysAdminSuite output root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Before', 'After', 'Assess')]
    [string]$Mode,

    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [string]$RunId,
    [string]$OutputRoot,
    [string]$TechnicianLabel,

    [string[]]$PermissionPath = @(),

    [ValidateRange(1, 12)]
    [int]$MaxPermissionPaths = 12,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasProperty {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Write-SasJson {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-SasSafeName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Get-SasTargets {
    param([string[]]$Direct, [string]$CsvPath, [int]$Limit)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($Direct)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) { $items.Add($target.Trim()) }
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "TargetsCsv not found: $CsvPath"
        }
        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            $value = $null
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $value = $candidate.Trim()
                        break
                    }
                }
            }
            if ($value) { $items.Add($value) }
        }
    }

    $targets = @($items | Sort-Object -Unique)
    if ($targets.Count -gt $Limit) {
        throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the run to keep remote reads bounded."
    }
    return $targets
}

function Get-SasBaselineTargets {
    param([string]$BeforeDirectory)
    if (-not (Test-Path -LiteralPath $BeforeDirectory -PathType Container)) { return @() }

    $targets = foreach ($file in @(Get-ChildItem -LiteralPath $BeforeDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $snapshot = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $requested = [string](Get-SasProperty -Object $snapshot -Name 'requested_target' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($requested)) { $requested }
        }
        catch {
            Write-Warning "Unable to read baseline target from $($file.FullName): $($_.Exception.Message)"
        }
    }
    return @($targets | Sort-Object -Unique)
}

function Assert-SasPermissionPaths {
    param([string[]]$Paths, [int]$Limit)

    $clean = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $candidate = $path.Trim()

        if ($candidate.StartsWith('\\')) {
            throw "PermissionPath must be target-local. UNC paths are recorded from profile metadata but are not contacted: $candidate"
        }
        if ($candidate -notmatch '^[A-Za-z]:\\') {
            throw "PermissionPath must be an absolute target-local Windows path: $candidate"
        }
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($candidate)) {
            throw "PermissionPath cannot contain wildcard characters: $candidate"
        }
        if (@($candidate -split '\\') -contains '..') {
            throw "PermissionPath cannot contain parent traversal segments: $candidate"
        }
        $clean.Add($candidate.TrimEnd('\'))
    }

    $result = @($clean | Sort-Object -Unique)
    if ($result.Count -gt $Limit) {
        throw "PermissionPath count $($result.Count) exceeds MaxPermissionPaths $Limit."
    }
    return $result
}

function New-SasFixtureSnapshot {
    param([string]$Target, [string]$Phase, [string[]]$RequestedPaths)

    $isAfter = $Phase -eq 'after'
    $expectedAccount = "SAMPLE\$($Target.ToUpperInvariant())"
    $profilePath = "C:\Users\$($Target.ToUpperInvariant())"

    $paths = @(
        [pscustomobject]@{
            path = 'C:\Users\Public'
            source = 'default_public'
            required_capability = 'read_write_signal'
            exists = $true
            owner = 'BUILTIN\Administrators'
            inheritance_protected = $false
            relevant_rule_count = 1
            expected_identity_rule_count = 0
            allow_read_signal = $true
            allow_write_signal = $true
            deny_signal = $false
            posture = 'allow_signal_present'
            review_required = $false
            error = $null
            relevant_rules = @(
                [pscustomobject]@{
                    identity = 'BUILTIN\Users'
                    access_control_type = 'Allow'
                    file_system_rights = 'ReadAndExecute, Synchronize, Write'
                    is_inherited = $true
                    read_signal = $true
                    write_signal = $true
                }
            )
        },
        [pscustomobject]@{
            path = 'C:\ProgramData'
            source = 'default_program_data'
            required_capability = 'read_signal'
            exists = $true
            owner = 'NT AUTHORITY\SYSTEM'
            inheritance_protected = $false
            relevant_rule_count = 1
            expected_identity_rule_count = 0
            allow_read_signal = $true
            allow_write_signal = $false
            deny_signal = $false
            posture = 'allow_signal_present'
            review_required = $false
            error = $null
            relevant_rules = @(
                [pscustomobject]@{
                    identity = 'BUILTIN\Users'
                    access_control_type = 'Allow'
                    file_system_rights = 'ReadAndExecute, Synchronize'
                    is_inherited = $true
                    read_signal = $true
                    write_signal = $false
                }
            )
        },
        [pscustomobject]@{
            path = 'C:\Temp'
            source = 'default_temp'
            required_capability = 'read_write_signal'
            exists = $false
            owner = $null
            inheritance_protected = $null
            relevant_rule_count = 0
            expected_identity_rule_count = 0
            allow_read_signal = $false
            allow_write_signal = $false
            deny_signal = $false
            posture = 'missing'
            review_required = $false
            error = $null
            relevant_rules = @()
        },
        [pscustomobject]@{
            path = $profilePath
            source = 'expected_profile'
            required_capability = 'read_write_signal'
            exists = [bool]$isAfter
            owner = $(if ($isAfter) { $expectedAccount } else { $null })
            inheritance_protected = $(if ($isAfter) { $false } else { $null })
            relevant_rule_count = $(if ($isAfter) { 1 } else { 0 })
            expected_identity_rule_count = $(if ($isAfter) { 1 } else { 0 })
            allow_read_signal = [bool]$isAfter
            allow_write_signal = [bool]$isAfter
            deny_signal = $false
            posture = $(if ($isAfter) { 'allow_signal_present' } else { 'missing' })
            review_required = $false
            error = $null
            relevant_rules = $(if ($isAfter) {
                @(
                    [pscustomobject]@{
                        identity = $expectedAccount
                        access_control_type = 'Allow'
                        file_system_rights = 'FullControl'
                        is_inherited = $false
                        read_signal = $true
                        write_signal = $true
                    }
                )
            } else { @() })
        }
    )

    foreach ($customPath in @($RequestedPaths)) {
        $paths += [pscustomobject]@{
            path = $customPath
            source = 'operator_supplied'
            required_capability = 'read_write_signal'
            exists = $true
            owner = 'BUILTIN\Administrators'
            inheritance_protected = $false
            relevant_rule_count = 1
            expected_identity_rule_count = 0
            allow_read_signal = $true
            allow_write_signal = $true
            deny_signal = $false
            posture = 'allow_signal_present'
            review_required = $false
            error = $null
            relevant_rules = @(
                [pscustomobject]@{
                    identity = 'NT AUTHORITY\Authenticated Users'
                    access_control_type = 'Allow'
                    file_system_rights = 'Modify, Synchronize'
                    is_inherited = $true
                    read_signal = $true
                    write_signal = $true
                }
            )
        }
    }

    $shellFolders = if ($isAfter) {
        @(
            [pscustomobject]@{
                name = 'Personal'
                raw_path = "\\fileserver\autologon\$($Target.ToUpperInvariant())\Documents"
                path_kind = 'unc'
                contacted = $false
            }
        )
    }
    else { @() }

    $mappedDrives = if ($isAfter) {
        @(
            [pscustomobject]@{
                drive_letter = 'P'
                remote_path = "\\fileserver\autologon\$($Target.ToUpperInvariant())"
                path_kind = 'unc'
                contacted = $false
            }
        )
    }
    else { @() }

    return [pscustomobject]@{
        schema_version = 'sas-autologon-file-access-snapshot/v1'
        snapshot_id = [guid]::NewGuid().ToString()
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        capture_phase = $Phase
        requested_target = $Target
        computer_name = $Target.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        expected_identity = [pscustomobject]@{
            user_name = $Target.ToUpperInvariant()
            domain_name = 'SAMPLE'
            account = $expectedAccount
        }
        expected_profile = [pscustomobject]@{
            sid = $(if ($isAfter) { 'S-1-5-21-111-222-333-1001' } else { $null })
            local_path = $profilePath
            exists = [bool]$isAfter
            loaded = [bool]$isAfter
            status = 0
            user_hive_loaded = [bool]$isAfter
        }
        local_path_posture = @($paths)
        shell_folder_redirections = @($shellFolders)
        mapped_network_drives = @($mappedDrives)
        file_access_review_required = $false
        review_path_count = 0
        explicit_deny_path_count = 0
        missing_path_count = @($paths | Where-Object { -not $_.exists }).Count
        redirected_shell_folder_count = @($shellFolders | Where-Object { $_.path_kind -eq 'unc' }).Count
        mapped_drive_count = @($mappedDrives).Count
        path_contents_enumerated = $false
        share_paths_contacted = $false
        effective_access_proven = $false
        collection_notes = @(
            'fixture_mode',
            'no_network_activity',
            'no_target_mutation',
            'no_directory_content_enumeration',
            'no_share_path_contact',
            'effective_access_not_proven'
        )
    }
}

$remoteCollector = {
    param([string]$Phase, [string[]]$RequestedPaths)

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    function Get-RegistryValueSafe {
        param([string]$Path, [string]$Name)
        try {
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -notcontains $Name) { return $null }
            return $key.GetValue(
                $Name,
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            )
        }
        catch { return $null }
    }

    function ConvertTo-AccountLeaf {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $leaf = $Value.Trim()
        if ($leaf.Contains('\')) { $leaf = $leaf.Split('\')[-1] }
        if ($leaf.Contains('@')) { $leaf = $leaf.Split('@')[0] }
        return $leaf.ToUpperInvariant()
    }

    function Get-PathKind {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return 'empty' }
        if ($Value.StartsWith('\\')) { return 'unc' }
        if ($Value -match '^[A-Za-z]:\\') { return 'local' }
        if ($Value.Contains('%')) { return 'environment_expression' }
        return 'other'
    }

    function Test-RelevantIdentity {
        param([string]$Identity, [string]$ExpectedLeaf)
        $leaf = ConvertTo-AccountLeaf -Value $Identity
        $known = @(
            'EVERYONE',
            'AUTHENTICATED USERS',
            'USERS',
            'DOMAIN USERS',
            'INTERACTIVE',
            'CREATOR OWNER'
        )
        return ($leaf -eq $ExpectedLeaf -or $known -contains $leaf)
    }

    function Get-RuleSignals {
        param([object]$Rule)

        $rights = [System.Security.AccessControl.FileSystemRights]$Rule.FileSystemRights
        $readMask = [System.Security.AccessControl.FileSystemRights]::Read -bor
            [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor
            [System.Security.AccessControl.FileSystemRights]::ListDirectory
        $writeMask = [System.Security.AccessControl.FileSystemRights]::Write -bor
            [System.Security.AccessControl.FileSystemRights]::Modify -bor
            [System.Security.AccessControl.FileSystemRights]::FullControl -bor
            [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor
            [System.Security.AccessControl.FileSystemRights]::CreateDirectories

        return [pscustomobject]@{
            read = (($rights -band $readMask) -ne 0)
            write = (($rights -band $writeMask) -ne 0)
        }
    }

    function Get-ExpectedProfileSafe {
        param([string]$ExpectedLeaf)

        $profiles = @()
        try {
            $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop |
                Where-Object { -not $_.Special })
        }
        catch {}

        $match = $profiles | Where-Object {
            (ConvertTo-AccountLeaf -Value (Split-Path -Path ([string]$_.LocalPath) -Leaf)) -eq $ExpectedLeaf
        } | Select-Object -First 1

        $candidatePath = Join-Path -Path $env:SystemDrive -ChildPath "Users\$ExpectedLeaf"
        if ($null -eq $match) {
            return [pscustomobject]@{
                sid = $null
                local_path = $candidatePath
                exists = (Test-Path -LiteralPath $candidatePath -PathType Container)
                loaded = $false
                status = $null
                user_hive_loaded = $false
            }
        }

        $sid = [string]$match.SID
        return [pscustomobject]@{
            sid = $sid
            local_path = [string]$match.LocalPath
            exists = (Test-Path -LiteralPath ([string]$match.LocalPath) -PathType Container)
            loaded = [bool]$match.Loaded
            status = $match.Status
            user_hive_loaded = $(if ($sid) { Test-Path -LiteralPath "Registry::HKEY_USERS\$sid" } else { $false })
        }
    }

    function Get-LocalPathPosture {
        param(
            [string]$Path,
            [string]$Source,
            [string]$RequiredCapability,
            [string]$ExpectedLeaf,
            [string]$PhaseName
        )

        $exists = Test-Path -LiteralPath $Path -PathType Container
        if (-not $exists) {
            $missingReview = ($Source -eq 'operator_supplied') -or
                ($Source -eq 'expected_profile' -and $PhaseName -eq 'after')
            return [pscustomobject]@{
                path = $Path
                source = $Source
                required_capability = $RequiredCapability
                exists = $false
                owner = $null
                inheritance_protected = $null
                relevant_rule_count = 0
                expected_identity_rule_count = 0
                allow_read_signal = $false
                allow_write_signal = $false
                deny_signal = $false
                posture = 'missing'
                review_required = [bool]$missingReview
                error = $null
                relevant_rules = @()
            }
        }

        try {
            $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
            $rows = foreach ($rule in @($acl.Access)) {
                $identity = [string]$rule.IdentityReference
                if (-not (Test-RelevantIdentity -Identity $identity -ExpectedLeaf $ExpectedLeaf)) { continue }
                $signals = Get-RuleSignals -Rule $rule
                [pscustomobject]@{
                    identity = $identity
                    access_control_type = [string]$rule.AccessControlType
                    file_system_rights = [string]$rule.FileSystemRights
                    is_inherited = [bool]$rule.IsInherited
                    read_signal = [bool]$signals.read
                    write_signal = [bool]$signals.write
                }
            }
            $rows = @($rows)
            $allowRows = @($rows | Where-Object { $_.access_control_type -eq 'Allow' })
            $denyRows = @($rows | Where-Object {
                $_.access_control_type -eq 'Deny' -and ($_.read_signal -or $_.write_signal)
            })
            $allowRead = @($allowRows | Where-Object { $_.read_signal }).Count -gt 0
            $allowWrite = @($allowRows | Where-Object { $_.write_signal }).Count -gt 0
            $deny = $denyRows.Count -gt 0
            $capabilitySignal = if ($RequiredCapability -eq 'read_signal') {
                $allowRead
            }
            else {
                ($allowRead -and $allowWrite)
            }

            $posture = if ($deny) {
                'explicit_deny_review'
            }
            elseif ($capabilitySignal) {
                'allow_signal_present'
            }
            else {
                'no_relevant_grant_observed'
            }

            $review = $deny -or (
                -not $capabilitySignal -and
                $Source -in @('expected_profile', 'operator_supplied')
            )

            return [pscustomobject]@{
                path = $Path
                source = $Source
                required_capability = $RequiredCapability
                exists = $true
                owner = [string]$acl.Owner
                inheritance_protected = [bool]$acl.AreAccessRulesProtected
                relevant_rule_count = $rows.Count
                expected_identity_rule_count = @($rows | Where-Object {
                    (ConvertTo-AccountLeaf -Value $_.identity) -eq $ExpectedLeaf
                }).Count
                allow_read_signal = [bool]$allowRead
                allow_write_signal = [bool]$allowWrite
                deny_signal = [bool]$deny
                posture = $posture
                review_required = [bool]$review
                error = $null
                relevant_rules = $rows
            }
        }
        catch {
            return [pscustomobject]@{
                path = $Path
                source = $Source
                required_capability = $RequiredCapability
                exists = $true
                owner = $null
                inheritance_protected = $null
                relevant_rule_count = 0
                expected_identity_rule_count = 0
                allow_read_signal = $false
                allow_write_signal = $false
                deny_signal = $false
                posture = 'acl_unavailable'
                review_required = $true
                error = $_.Exception.Message
                relevant_rules = @()
            }
        }
    }

    function Get-ShellFolderRedirectionsSafe {
        param([string]$Sid)
        if ([string]::IsNullOrWhiteSpace($Sid)) { return @() }

        $path = "Registry::HKEY_USERS\$Sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        if (-not (Test-Path -LiteralPath $path)) { return @() }

        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $names = @('Desktop', 'Personal', 'AppData', 'Local AppData', 'Start Menu')
            $rows = foreach ($name in $names) {
                $property = $item.PSObject.Properties[$name]
                if ($null -eq $property) { continue }
                $value = [string]$property.Value
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                [pscustomobject]@{
                    name = $name
                    raw_path = $value
                    path_kind = Get-PathKind -Value $value
                    contacted = $false
                }
            }
            return @($rows | Sort-Object -Property name)
        }
        catch { return @() }
    }

    function Get-MappedDrivesSafe {
        param([string]$Sid)
        if ([string]::IsNullOrWhiteSpace($Sid)) { return @() }

        $path = "Registry::HKEY_USERS\$Sid\Network"
        if (-not (Test-Path -LiteralPath $path)) { return @() }

        $rows = foreach ($key in @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                $remotePath = [string]$item.RemotePath
                if ([string]::IsNullOrWhiteSpace($remotePath)) { continue }
                [pscustomobject]@{
                    drive_letter = $key.PSChildName.ToUpperInvariant()
                    remote_path = $remotePath
                    path_kind = Get-PathKind -Value $remotePath
                    contacted = $false
                }
            }
            catch {}
        }
        return @($rows | Sort-Object -Property drive_letter)
    }

    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $userValue = [string](Get-RegistryValueSafe -Path $winlogonPath -Name 'DefaultUserName')
    $domainValue = [string](Get-RegistryValueSafe -Path $winlogonPath -Name 'DefaultDomainName')
    $expectedLeaf = ConvertTo-AccountLeaf -Value $userValue
    if ([string]::IsNullOrWhiteSpace($expectedLeaf)) {
        $expectedLeaf = $env:COMPUTERNAME.ToUpperInvariant()
    }
    $expectedDomain = if ([string]::IsNullOrWhiteSpace($domainValue)) {
        $env:COMPUTERNAME
    }
    else {
        $domainValue.Trim()
    }
    $expectedAccount = "$expectedDomain\$expectedLeaf"
    $profile = Get-ExpectedProfileSafe -ExpectedLeaf $expectedLeaf

    $descriptors = New-Object System.Collections.Generic.List[object]
    $descriptors.Add([pscustomobject]@{
        path = (Join-Path -Path $env:SystemDrive -ChildPath 'Users\Public')
        source = 'default_public'
        required_capability = 'read_write_signal'
    })
    $descriptors.Add([pscustomobject]@{
        path = $env:ProgramData
        source = 'default_program_data'
        required_capability = 'read_signal'
    })
    $descriptors.Add([pscustomobject]@{
        path = (Join-Path -Path $env:SystemDrive -ChildPath 'Temp')
        source = 'default_temp'
        required_capability = 'read_write_signal'
    })
    $descriptors.Add([pscustomobject]@{
        path = [string]$profile.local_path
        source = 'expected_profile'
        required_capability = 'read_write_signal'
    })
    foreach ($path in @($RequestedPaths)) {
        $descriptors.Add([pscustomobject]@{
            path = $path
            source = 'operator_supplied'
            required_capability = 'read_write_signal'
        })
    }

    $seen = @{}
    $pathRows = foreach ($descriptor in @($descriptors)) {
        $candidate = ([string]$descriptor.path).TrimEnd('\')
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $key = $candidate.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        Get-LocalPathPosture `
            -Path $candidate `
            -Source ([string]$descriptor.source) `
            -RequiredCapability ([string]$descriptor.required_capability) `
            -ExpectedLeaf $expectedLeaf `
            -PhaseName $Phase
    }
    $pathRows = @($pathRows)
    $shellFolders = @(Get-ShellFolderRedirectionsSafe -Sid ([string]$profile.sid))
    $mappedDrives = @(Get-MappedDrivesSafe -Sid ([string]$profile.sid))
    $reviewRows = @($pathRows | Where-Object { $_.review_required })
    $denyRows = @($pathRows | Where-Object { $_.deny_signal })

    return [pscustomobject]@{
        schema_version = 'sas-autologon-file-access-snapshot/v1'
        snapshot_id = [guid]::NewGuid().ToString()
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        capture_phase = $Phase
        computer_name = $env:COMPUTERNAME.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        expected_identity = [pscustomobject]@{
            user_name = $expectedLeaf
            domain_name = $expectedDomain
            account = $expectedAccount
        }
        expected_profile = $profile
        local_path_posture = $pathRows
        shell_folder_redirections = $shellFolders
        mapped_network_drives = $mappedDrives
        file_access_review_required = ($reviewRows.Count -gt 0)
        review_path_count = $reviewRows.Count
        explicit_deny_path_count = $denyRows.Count
        missing_path_count = @($pathRows | Where-Object { -not $_.exists }).Count
        redirected_shell_folder_count = @($shellFolders | Where-Object { $_.path_kind -eq 'unc' }).Count
        mapped_drive_count = $mappedDrives.Count
        path_contents_enumerated = $false
        share_paths_contacted = $false
        effective_access_proven = $false
        collection_notes = @(
            'read_only_remote_collection',
            'bounded_target_local_acl_metadata',
            'no_directory_content_enumeration',
            'no_share_path_contact',
            'effective_access_not_proven',
            'no_target_side_sysadminsuite_artifacts'
        )
    }
}

function Invoke-SasCapture {
    param(
        [string]$Target,
        [string]$Phase,
        [string[]]$RequestedPaths,
        [switch]$UseFixture
    )

    if ($UseFixture) {
        return New-SasFixtureSnapshot -Target $Target -Phase $Phase -RequestedPaths $RequestedPaths
    }

    try {
        $localAliases = @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME)
        if ($localAliases -contains $Target) {
            $snapshot = & $remoteCollector $Phase $RequestedPaths
        }
        else {
            $session = $null
            try {
                $option = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 180000
                $session = New-PSSession -ComputerName $Target -SessionOption $option
                $snapshot = Invoke-Command `
                    -Session $session `
                    -ScriptBlock $remoteCollector `
                    -ArgumentList $Phase, $RequestedPaths
            }
            finally {
                if ($session) { Remove-PSSession -Session $session }
            }
        }
        $snapshot | Add-Member -NotePropertyName requested_target -NotePropertyValue $Target -Force
        return $snapshot
    }
    catch {
        return [pscustomobject]@{
            schema_version = 'sas-autologon-file-access-snapshot/v1'
            snapshot_id = [guid]::NewGuid().ToString()
            captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            capture_phase = $Phase
            requested_target = $Target
            computer_name = $Target.ToUpperInvariant()
            collection_status = 'failed'
            error = $_.Exception.Message
            expected_identity = $null
            expected_profile = $null
            local_path_posture = @()
            shell_folder_redirections = @()
            mapped_network_drives = @()
            file_access_review_required = $true
            review_path_count = 0
            explicit_deny_path_count = 0
            missing_path_count = 0
            redirected_shell_folder_count = 0
            mapped_drive_count = 0
            path_contents_enumerated = $false
            share_paths_contacted = $false
            effective_access_proven = $false
            collection_notes = @('collection_failed', 'no_target_mutation_attempted')
        }
    }
}

function Get-SasObjectMap {
    param([object[]]$Rows, [string]$KeyName)
    $map = @{}
    foreach ($row in @($Rows)) {
        $key = ([string](Get-SasProperty -Object $row -Name $KeyName -Default '')).Trim().ToLowerInvariant()
        if ($key) { $map[$key] = $row }
    }
    return $map
}

function Compare-SasAccessPosture {
    param([object]$BeforeAccess, [object]$AfterAccess)

    $changes = New-Object System.Collections.Generic.List[object]

    $beforePaths = @(Get-SasProperty -Object $BeforeAccess -Name 'local_path_posture' -Default @())
    $afterPaths = @(Get-SasProperty -Object $AfterAccess -Name 'local_path_posture' -Default @())
    $beforeMap = Get-SasObjectMap -Rows $beforePaths -KeyName 'path'
    $afterMap = Get-SasObjectMap -Rows $afterPaths -KeyName 'path'
    $pathKeys = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
    foreach ($key in $pathKeys) {
        $beforeRow = if ($beforeMap.ContainsKey($key)) { $beforeMap[$key] } else { $null }
        $afterRow = if ($afterMap.ContainsKey($key)) { $afterMap[$key] } else { $null }
        foreach ($field in @('exists', 'owner', 'posture', 'allow_read_signal', 'allow_write_signal', 'deny_signal', 'review_required')) {
            $beforeValue = Get-SasProperty -Object $beforeRow -Name $field
            $afterValue = Get-SasProperty -Object $afterRow -Name $field
            if ([string]$beforeValue -ne [string]$afterValue) {
                $changes.Add([pscustomobject]@{
                    category = 'local_path'
                    key = $key
                    field = $field
                    before = $beforeValue
                    after = $afterValue
                })
            }
        }
    }

    $beforeShell = Get-SasObjectMap `
        -Rows @(Get-SasProperty -Object $BeforeAccess -Name 'shell_folder_redirections' -Default @()) `
        -KeyName 'name'
    $afterShell = Get-SasObjectMap `
        -Rows @(Get-SasProperty -Object $AfterAccess -Name 'shell_folder_redirections' -Default @()) `
        -KeyName 'name'
    foreach ($key in @($beforeShell.Keys + $afterShell.Keys | Sort-Object -Unique)) {
        $beforeValue = if ($beforeShell.ContainsKey($key)) { [string]$beforeShell[$key].raw_path } else { $null }
        $afterValue = if ($afterShell.ContainsKey($key)) { [string]$afterShell[$key].raw_path } else { $null }
        if ($beforeValue -ne $afterValue) {
            $changes.Add([pscustomobject]@{
                category = 'shell_folder_redirection'
                key = $key
                field = 'raw_path'
                before = $beforeValue
                after = $afterValue
            })
        }
    }

    $beforeDrives = Get-SasObjectMap `
        -Rows @(Get-SasProperty -Object $BeforeAccess -Name 'mapped_network_drives' -Default @()) `
        -KeyName 'drive_letter'
    $afterDrives = Get-SasObjectMap `
        -Rows @(Get-SasProperty -Object $AfterAccess -Name 'mapped_network_drives' -Default @()) `
        -KeyName 'drive_letter'
    foreach ($key in @($beforeDrives.Keys + $afterDrives.Keys | Sort-Object -Unique)) {
        $beforeValue = if ($beforeDrives.ContainsKey($key)) { [string]$beforeDrives[$key].remote_path } else { $null }
        $afterValue = if ($afterDrives.ContainsKey($key)) { [string]$afterDrives[$key].remote_path } else { $null }
        if ($beforeValue -ne $afterValue) {
            $changes.Add([pscustomobject]@{
                category = 'mapped_network_drive'
                key = $key
                field = 'remote_path'
                before = $beforeValue
                after = $afterValue
            })
        }
    }

    return @($changes)
}

function New-SasAccessDelta {
    param([object]$Before, [object]$After, [string]$AssignmentLabel)

    $beforeCollection = [string](Get-SasProperty -Object $Before -Name 'collection_status' -Default 'failed')
    $afterCollection = [string](Get-SasProperty -Object $After -Name 'collection_status' -Default 'failed')
    $changes = Compare-SasAccessPosture -BeforeAccess $Before -AfterAccess $After
    $beforeReview = [bool](Get-SasProperty -Object $Before -Name 'file_access_review_required' -Default $true)
    $afterReview = [bool](Get-SasProperty -Object $After -Name 'file_access_review_required' -Default $true)
    $beforeReviewCount = [int](Get-SasProperty -Object $Before -Name 'review_path_count' -Default 0)
    $afterReviewCount = [int](Get-SasProperty -Object $After -Name 'review_path_count' -Default 0)

    $decision = 'INCONCLUSIVE'
    $reason = 'One or both file-access snapshots were unavailable or incomplete.'

    if ($beforeCollection -eq 'success' -and $afterCollection -eq 'success') {
        if ($afterReview -and (-not $beforeReview -or $afterReviewCount -gt $beforeReviewCount)) {
            $decision = 'ACCESS_REGRESSION_REVIEW'
            $reason = 'The final ACL/profile posture contains new or increased review conditions.'
        }
        elseif ($afterReview) {
            $decision = 'ACCESS_POSTURE_REVIEW'
            $reason = 'The final ACL/profile posture contains explicit deny, missing required path, unavailable ACL, or no direct/broad grant signal on a required path.'
        }
        elseif ($changes.Count -gt 0) {
            $decision = 'ACCESS_POSTURE_IMPROVED'
            $reason = 'The final posture has no flagged path review and shows a profile, ACL, redirect, or mapped-drive change.'
        }
        else {
            $decision = 'NO_MATERIAL_ACCESS_CHANGE'
            $reason = 'No ACL/profile redirection or mapped-drive difference was observed.'
        }
    }

    return [pscustomobject]@{
        schema_version = 'sas-autologon-file-access-delta/v1'
        compared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        computer_name = [string](Get-SasProperty -Object $After -Name 'computer_name' -Default 'unknown')
        requested_target = [string](Get-SasProperty -Object $After -Name 'requested_target' -Default '')
        technician_label = $AssignmentLabel
        decision = $decision
        decision_reason = $reason
        state_change_observed = ($changes.Count -gt 0)
        before_review_required = $beforeReview
        after_review_required = $afterReview
        before_review_path_count = $beforeReviewCount
        after_review_path_count = $afterReviewCount
        after_explicit_deny_path_count = [int](Get-SasProperty -Object $After -Name 'explicit_deny_path_count' -Default 0)
        after_redirected_shell_folder_count = [int](Get-SasProperty -Object $After -Name 'redirected_shell_folder_count' -Default 0)
        after_mapped_drive_count = [int](Get-SasProperty -Object $After -Name 'mapped_drive_count' -Default 0)
        access_posture_changes = $changes
        before_snapshot_id = Get-SasProperty -Object $Before -Name 'snapshot_id'
        after_snapshot_id = Get-SasProperty -Object $After -Name 'snapshot_id'
        safety = [pscustomobject]@{
            target_mutation_performed = $false
            target_side_sysadminsuite_artifacts_written = $false
            path_contents_enumerated = $false
            share_paths_contacted = $false
            effective_access_proven = $false
        }
    }
}

$permissionPaths = @(Assert-SasPermissionPaths -Paths $PermissionPath -Limit $MaxPermissionPaths)
$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule -PathType Leaf)) {
    throw "Missing target intake module: $targetIntakeModule"
}
Import-Module -Name $targetIntakeModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey/output/autologon_file_access'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'auto-logon file access output root'

if (-not $FixtureMode) {
    $networkGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasNetworkGuard.psm1'
    if (-not (Test-Path -LiteralPath $networkGuardModule -PathType Leaf)) {
        throw "Missing shared network guard module: $networkGuardModule"
    }
    Import-Module -Name $networkGuardModule -Force
    Assert-SasNorthwellWifi
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    if ($Mode -eq 'After') { throw 'After mode requires -RunId from the Before capture.' }
    $RunId = 'autologon-access-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
}
if ($RunId -notmatch '^autologon-access-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') {
    throw "Invalid RunId format: $RunId"
}

$runRoot = Join-Path -Path $OutputRoot -ChildPath $RunId
$beforeDirectory = Join-Path -Path $runRoot -ChildPath 'before'
$afterDirectory = Join-Path -Path $runRoot -ChildPath 'after'
$currentDirectory = Join-Path -Path $runRoot -ChildPath 'current'
$deltaDirectory = Join-Path -Path $runRoot -ChildPath 'delta'

$targets = @(Get-SasTargets -Direct $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)
if ($Mode -eq 'After' -and $targets.Count -eq 0) {
    $targets = @(Get-SasBaselineTargets -BeforeDirectory $beforeDirectory)
}
if ($targets.Count -eq 0) {
    throw 'No explicit targets were supplied. Use -ComputerName or -TargetsCsv.'
}

if ($Mode -eq 'Before' -and (Test-Path -LiteralPath $runRoot)) {
    throw "Refusing to overwrite existing baseline run: $runRoot"
}
if ($Mode -eq 'After' -and -not (Test-Path -LiteralPath $beforeDirectory -PathType Container)) {
    throw "Baseline directory not found: $beforeDirectory"
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$phaseDirectory = if ($Mode -eq 'Before') {
    $beforeDirectory
}
elseif ($Mode -eq 'After') {
    $afterDirectory
}
else {
    $currentDirectory
}
New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
if ($Mode -eq 'After') { New-Item -ItemType Directory -Path $deltaDirectory -Force | Out-Null }

$phase = $Mode.ToLowerInvariant()
$manifestPath = Join-Path -Path $runRoot -ChildPath ("run_manifest_{0}.json" -f $phase)
$manifest = [ordered]@{
    schema_version = 'sas-autologon-file-access-run/v1'
    run_id = $RunId
    mode = $Mode
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    target_count = $targets.Count
    targets = $targets
    permission_paths = $permissionPaths
    fixture_mode = [bool]$FixtureMode
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
    path_contents_enumerated = $false
    share_paths_contacted = $false
    effective_access_proven = $false
}
Write-SasJson -Path $manifestPath -Value $manifest

$snapshots = New-Object System.Collections.Generic.List[object]
$deltas = New-Object System.Collections.Generic.List[object]
$rows = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    $safeTarget = ConvertTo-SasSafeName -Value $target
    $snapshot = Invoke-SasCapture `
        -Target $target `
        -Phase $phase `
        -RequestedPaths $permissionPaths `
        -UseFixture:$FixtureMode
    $snapshotPath = Join-Path -Path $phaseDirectory -ChildPath "$safeTarget.json"
    Write-SasJson -Path $snapshotPath -Value $snapshot
    $snapshots.Add($snapshot)

    if ($Mode -eq 'After') {
        $beforePath = Join-Path -Path $beforeDirectory -ChildPath "$safeTarget.json"
        if (Test-Path -LiteralPath $beforePath -PathType Leaf) {
            $beforeSnapshot = Get-Content -LiteralPath $beforePath -Raw | ConvertFrom-Json
            $delta = New-SasAccessDelta `
                -Before $beforeSnapshot `
                -After $snapshot `
                -AssignmentLabel $TechnicianLabel
        }
        else {
            $delta = [pscustomobject]@{
                schema_version = 'sas-autologon-file-access-delta/v1'
                computer_name = $target
                requested_target = $target
                technician_label = $TechnicianLabel
                decision = 'INCONCLUSIVE'
                decision_reason = "Baseline snapshot missing: $beforePath"
                state_change_observed = $false
                before_review_required = $true
                after_review_required = $true
                before_review_path_count = 0
                after_review_path_count = 0
                after_explicit_deny_path_count = 0
                after_redirected_shell_folder_count = 0
                after_mapped_drive_count = 0
                access_posture_changes = @()
            }
        }

        $deltaPath = Join-Path -Path $deltaDirectory -ChildPath "$safeTarget.json"
        Write-SasJson -Path $deltaPath -Value $delta
        $deltas.Add($delta)
        $rows.Add([pscustomobject]@{
            ComputerName = $delta.computer_name
            TechnicianLabel = $TechnicianLabel
            Decision = $delta.decision
            StateChangeObserved = $delta.state_change_observed
            AfterReviewRequired = $delta.after_review_required
            ReviewPathCount = $delta.after_review_path_count
            ExplicitDenyPathCount = $delta.after_explicit_deny_path_count
            RedirectedShellFolderCount = $delta.after_redirected_shell_folder_count
            MappedDriveCount = $delta.after_mapped_drive_count
            EffectiveAccessProven = $false
            ShareAccessProven = $false
            EvidencePath = $deltaPath
        })
    }
    else {
        $identity = Get-SasProperty -Object $snapshot -Name 'expected_identity'
        $rows.Add([pscustomobject]@{
            ComputerName = $snapshot.computer_name
            TechnicianLabel = $TechnicianLabel
            Decision = $(if ($Mode -eq 'Before') { 'ACCESS_BASELINE_CAPTURED' } else { 'ACCESS_POSTURE_CAPTURED' })
            StateChangeObserved = $false
            AfterReviewRequired = [bool](Get-SasProperty -Object $snapshot -Name 'file_access_review_required' -Default $true)
            ReviewPathCount = [int](Get-SasProperty -Object $snapshot -Name 'review_path_count' -Default 0)
            ExplicitDenyPathCount = [int](Get-SasProperty -Object $snapshot -Name 'explicit_deny_path_count' -Default 0)
            RedirectedShellFolderCount = [int](Get-SasProperty -Object $snapshot -Name 'redirected_shell_folder_count' -Default 0)
            MappedDriveCount = [int](Get-SasProperty -Object $snapshot -Name 'mapped_drive_count' -Default 0)
            ExpectedAccount = [string](Get-SasProperty -Object $identity -Name 'account' -Default '')
            EffectiveAccessProven = $false
            ShareAccessProven = $false
            EvidencePath = $snapshotPath
        })
    }
}

$summaryCsvPath = Join-Path -Path $runRoot -ChildPath 'autologon_file_access_summary.csv'
$summaryJsonPath = Join-Path -Path $runRoot -ChildPath 'autologon_file_access_summary.json'
$handoffPath = Join-Path -Path $runRoot -ChildPath 'operator_handoff.txt'
$rows | Export-Csv -LiteralPath $summaryCsvPath -NoTypeInformation -Encoding UTF8

$summary = [ordered]@{
    schema_version = 'sas-autologon-file-access-summary/v1'
    run_id = $RunId
    mode = $Mode
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    target_count = $targets.Count
    permission_paths = $permissionPaths
    collection_success_count = @($snapshots | Where-Object { $_.collection_status -eq 'success' }).Count
    collection_failure_count = @($snapshots | Where-Object { $_.collection_status -ne 'success' }).Count
    access_posture_improved_count = @($deltas | Where-Object { $_.decision -eq 'ACCESS_POSTURE_IMPROVED' }).Count
    no_material_access_change_count = @($deltas | Where-Object { $_.decision -eq 'NO_MATERIAL_ACCESS_CHANGE' }).Count
    access_posture_review_count = @($deltas | Where-Object { $_.decision -eq 'ACCESS_POSTURE_REVIEW' }).Count
    access_regression_review_count = @($deltas | Where-Object { $_.decision -eq 'ACCESS_REGRESSION_REVIEW' }).Count
    inconclusive_count = @($deltas | Where-Object { $_.decision -eq 'INCONCLUSIVE' }).Count
    current_review_target_count = @($snapshots | Where-Object { $_.file_access_review_required }).Count
    current_explicit_deny_target_count = @($snapshots | Where-Object { [int]$_.explicit_deny_path_count -gt 0 }).Count
    redirected_shell_folder_target_count = @($snapshots | Where-Object { [int]$_.redirected_shell_folder_count -gt 0 }).Count
    mapped_drive_target_count = @($snapshots | Where-Object { [int]$_.mapped_drive_count -gt 0 }).Count
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
    path_contents_enumerated = $false
    share_paths_contacted = $false
    effective_access_proven = $false
    summary_csv = $summaryCsvPath
    phase_manifest = $manifestPath
    results = @($rows)
}
Write-SasJson -Path $summaryJsonPath -Value $summary

$handoff = @(
    'SysAdminSuite AutoLogon file-access posture',
    "Run ID: $RunId",
    "Mode: $Mode",
    "Targets: $($targets.Count)",
    "Operator-supplied local paths: $($permissionPaths.Count)",
    "Technician/assignment label: $(if ($TechnicianLabel) { $TechnicianLabel } else { '[not supplied]' })",
    "Summary CSV: $summaryCsvPath",
    "Summary JSON: $summaryJsonPath",
    '',
    'Review explicit denies, missing required paths, unavailable ACLs, and expected/custom paths without a direct or broad allow signal.',
    'UNC shell-folder redirects and mapped-drive paths are recorded as metadata only; the collector does not contact those shares.',
    'ACL signals do not prove effective access for the AutoLogon user. Validate access after a real logon before rollout expansion.',
    'No directory contents are enumerated and no SysAdminSuite evidence is written to target workstations.'
)
if ($Mode -eq 'Before') {
    $handoff += ''
    $handoff += 'After approved AutoLogon work completes, run:'
    $handoff += ".\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 -Mode After -RunId $RunId -TargetsCsv <same-approved-manifest>"
}
$handoff | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "AutoLogon file-access run: $RunId" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Targets: $($targets.Count)" -ForegroundColor Cyan
Write-Host "Evidence: $runRoot" -ForegroundColor Green
Write-Host "Summary: $summaryCsvPath" -ForegroundColor Green

[pscustomobject]@{
    run_id = $RunId
    mode = $Mode
    target_count = $targets.Count
    output_root = $runRoot
    summary_csv = $summaryCsvPath
    summary_json = $summaryJsonPath
    handoff = $handoffPath
    target_mutation_performed = $false
    target_side_sysadminsuite_artifacts_written = $false
    path_contents_enumerated = $false
    share_paths_contacted = $false
    effective_access_proven = $false
}
