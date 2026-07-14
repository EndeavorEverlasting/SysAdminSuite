<#
.SYNOPSIS
    Generates a read-only, redacted inventory of an operator-local package tree.
.DESCRIPTION
    Reads file metadata, hashes, Authenticode status, selected MSI properties, and
    bounded text indicators without executing package code. Output paths are
    relative to the supplied scan root. The scan root itself is never persisted.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ScanPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$FixtureOnly
)

$ErrorActionPreference = 'Stop'

function Get-FileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-MsiInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $installer = $null
    $database = $null
    $view = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.OpenDatabase($Path, 0)
        $view = $database.OpenView('SELECT Property, Value FROM Property')
        $view.Execute()

        $result = [ordered]@{
            product_code = $null
            product_name = $null
            product_version = $null
            manufacturer = $null
        }

        while ($record = $view.Fetch()) {
            $name = $record.StringData(1)
            $value = $record.StringData(2)
            switch ($name) {
                'ProductCode' { $result.product_code = $value }
                'ProductName' { $result.product_name = $value }
                'ProductVersion' { $result.product_version = $value }
                'Manufacturer' { $result.manufacturer = $value }
            }
        }

        return $result
    }
    catch {
        return $null
    }
    finally {
        if ($view) {
            try { $view.Close() } catch {}
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($view)
        }
        if ($database) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
        }
        if ($installer) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
        }
    }
}

function Get-DangerousIndicators {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TextContent)

    $indicators = [System.Collections.Generic.List[string]]::new()
    $rules = [ordered]@{
        registry_changes = 'reg\.exe|reg\s+add|reg\s+delete|regedit|New-ItemProperty|Set-ItemProperty|Remove-ItemProperty'
        services = 'sc\.exe|sc\s+create|sc\s+delete|sc\s+config|New-Service|Set-Service|Start-Service|Stop-Service|Remove-Service'
        scheduled_tasks = 'schtasks|New-ScheduledTask|Register-ScheduledTask|Unregister-ScheduledTask'
        reboot = 'reboot|restart-computer|shutdown\.exe|/forcerestart|/norestart'
        autologon = 'AutoLogon|DefaultPassword|DefaultUserName|AutoAdminLogon|Winlogon'
        account_changes = 'net\s+user|net\s+localgroup|New-LocalUser|Add-LocalGroupMember'
        firewall_changes = 'netsh\s+advfirewall|New-NetFirewallRule|Set-NetFirewallRule'
        group_policy_refresh = 'gpupdate(?:\.exe)?'
        broad_deletion = 'rmdir\s+/s\s+/q|Remove-Item\s+-Recurse|del\s+/f\s+/s\s+/q'
        self_removal = 'del\s+%0|del\s+"%~f0"'
        silent_switches_observed = '/q(?:n|b)?\b|/s(?:ilent)?\b|/norestart\b'
    }

    foreach ($entry in $rules.GetEnumerator()) {
        if ($TextContent -match $entry.Value) {
            $indicators.Add([string]$entry.Key)
        }
    }

    return @($indicators | Select-Object -Unique)
}

function Get-SafeRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FullName
    )

    $rootWithSeparator = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $FullName.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'File is outside the approved scan root.'
    }

    return $FullName.Substring($rootWithSeparator.Length).Replace('\', '/')
}

function New-FixtureInventory {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $fixturePath = Join-Path $repoRoot 'Tests\Fixtures\local-package-inventory.fixture.json'
    if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
        throw 'The sanitized package-inventory fixture is missing.'
    }

    return Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
}

if ($FixtureOnly) {
    $inventory = New-FixtureInventory
}
else {
    if ([string]::IsNullOrWhiteSpace($ScanPath)) {
        throw 'ScanPath is required unless FixtureOnly is specified.'
    }
    if (-not (Test-Path -LiteralPath $ScanPath -PathType Container)) {
        throw 'The supplied scan root does not exist or is not a directory.'
    }

    $scanRootAbsolute = (Resolve-Path -LiteralPath $ScanPath).Path
    $packages = [System.Collections.Generic.List[object]]::new()
    $files = Get-ChildItem -LiteralPath $scanRootAbsolute -Recurse -File

    foreach ($file in $files) {
        $extension = $file.Extension.ToLowerInvariant()
        $fileClass = switch ($extension) {
            { $_ -in '.msi', '.exe', '.msix', '.msixbundle', '.appx' } { 'installer'; break }
            { $_ -in '.ps1', '.psm1', '.bat', '.cmd', '.vbs', '.js', '.sh' } { 'script'; break }
            { $_ -in '.lnk', '.url' } { 'shortcut'; break }
            { $_ -in '.xml', '.json', '.ini', '.cfg', '.config', '.manifest', '.inf' } { 'configuration'; break }
            { $_ -in '.zip', '.cab', '.tar', '.gz', '.tgz' } { 'archive'; break }
            default { 'other' }
        }

        $dangerousIndicators = [System.Collections.Generic.List[string]]::new()
        $referencedDependencies = [System.Collections.Generic.List[string]]::new()
        $adjacentConfigs = [System.Collections.Generic.List[string]]::new()
        $rebootRequirements = [System.Collections.Generic.List[string]]::new()
        $applicationExecutables = [System.Collections.Generic.List[string]]::new()

        $isText = $extension -in '.ps1', '.psm1', '.bat', '.cmd', '.vbs', '.js', '.sh', '.xml', '.json', '.ini', '.cfg', '.config', '.txt', '.md'
        if ($isText -and $file.Length -le 5MB) {
            try {
                $content = [IO.File]::ReadAllText($file.FullName)
                foreach ($indicator in (Get-DangerousIndicators -TextContent $content)) {
                    $dangerousIndicators.Add($indicator)
                }
                if ($content -match 'reboot|restart|shutdown') {
                    $rebootRequirements.Add('content_mentions_reboot')
                }
                foreach ($match in [regex]::Matches($content, '\b[\w.-]+\.exe\b', 'IgnoreCase')) {
                    $applicationExecutables.Add([IO.Path]::GetFileName($match.Value))
                }
            }
            catch {}
        }

        if ($extension -eq '.lnk') {
            $shell = $null
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($file.FullName)
                if ($shortcut.TargetPath) {
                    $targetName = [IO.Path]::GetFileName($shortcut.TargetPath)
                    $referencedDependencies.Add($(if ($targetName) { $targetName } else { 'external_shortcut_target' }))
                }
            }
            catch {}
            finally {
                if ($shell) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
            }
        }
        elseif ($extension -eq '.url') {
            $referencedDependencies.Add('external_url_target')
        }

        foreach ($adjacent in (Get-ChildItem -LiteralPath $file.DirectoryName -File)) {
            if ($adjacent.Extension.ToLowerInvariant() -in '.xml', '.json', '.ini', '.cfg', '.config') {
                $adjacentConfigs.Add($adjacent.Name)
            }
            if ($fileClass -eq 'installer' -and $adjacent.Extension.ToLowerInvariant() -in '.ps1', '.psm1', '.bat', '.cmd') {
                try {
                    $scriptContent = [IO.File]::ReadAllText($adjacent.FullName)
                    foreach ($indicator in (Get-DangerousIndicators -TextContent $scriptContent)) {
                        $dangerousIndicators.Add($indicator)
                    }
                }
                catch {}
            }
        }

        $signatureStatus = 'NotSigned'
        $signatureSigner = $null
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
            $signatureStatus = $signature.Status.ToString()
            if ($signature.SignerCertificate) {
                $signatureSigner = $signature.SignerCertificate.Subject
            }
        }
        catch {
            $signatureStatus = 'UnknownError'
        }

        $versionInfo = [ordered]@{
            product_name = $null
            product_version = $null
            file_version = $null
            company_name = $null
        }
        if ($extension -in '.exe', '.dll') {
            try {
                $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
                $versionInfo.product_name = $version.ProductName
                $versionInfo.product_version = $version.ProductVersion
                $versionInfo.file_version = $version.FileVersion
                $versionInfo.company_name = $version.CompanyName
            }
            catch {}
        }

        $uniqueIndicators = @($dangerousIndicators | Select-Object -Unique)
        if ($fileClass -eq 'installer') {
            if ($uniqueIndicators -contains 'autologon') {
                $classification = 'requires_physical_cybernet'
            }
            elseif ($uniqueIndicators -contains 'reboot' -or $uniqueIndicators -contains 'services' -or $uniqueIndicators -contains 'account_changes') {
                $classification = 'requires_reboot_vm'
            }
            else {
                $classification = 'blocked_missing_evidence'
            }
        }
        else {
            $classification = 'inventory_only'
        }

        $packages.Add([ordered]@{
            relative_path = Get-SafeRelativePath -Root $scanRootAbsolute -FullName $file.FullName
            file_class = $fileClass
            size_bytes = [long]$file.Length
            sha256 = Get-FileSha256 -Path $file.FullName
            authenticode = [ordered]@{ status = $signatureStatus; signer = $signatureSigner }
            file_version_info = $versionInfo
            msi_info = $(if ($extension -eq '.msi') { Get-MsiInfo -Path $file.FullName } else { $null })
            archive_type = $(if ($fileClass -eq 'archive') { $extension.TrimStart('.') } elseif ($extension -in '.msix', '.msixbundle') { 'appx_bundle' } else { $null })
            referenced_dependencies = @($referencedDependencies | Select-Object -Unique)
            embedded_or_adjacent_configs = @($adjacentConfigs | Select-Object -Unique)
            likely_reboot_requirements = @($rebootRequirements | Select-Object -Unique)
            likely_application_executables = @($applicationExecutables | Select-Object -Unique)
            dangerous_indicators = $uniqueIndicators
            installer_arguments = $null
            classification = $classification
        })
    }

    $inventory = [ordered]@{
        schema_version = 'sas-local-package-inventory/v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        scan_root = 'operator-local-reference'
        packages = $packages.ToArray()
    }
}

$json = ConvertTo-Json $inventory -Depth 12
if ($OutputPath) {
    $parent = Split-Path -Path $OutputPath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
}

return $inventory
