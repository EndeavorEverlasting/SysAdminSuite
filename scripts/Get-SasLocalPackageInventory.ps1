<#
.SYNOPSIS
    Generates a read-only inventory of local packages in the reference tree.
.DESCRIPTION
    Analyzes installer files, scripts, shortcuts, and configurations without executing package code.
    Identifies file classes, versions, hashes, Authenticode signatures, and dangerous indicators.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ScanPath = "$PSScriptRoot\..\tech emulation\Alex",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$FixtureOnly
)

$ErrorActionPreference = "Stop"

function Get-FileSha256 {
    param([string]$Path)
    try {
        $hashObj = Get-FileHash -Path $Path -Algorithm SHA256
        return $hashObj.Hash.ToLowerInvariant()
    } catch {
        return "0" * 64
    }
}

function Get-MsiInfo {
    param([string]$Path)
    $msi = @{
        product_code = $null
        product_name = $null
        product_version = $null
        manufacturer = $null
    }
    try {
        $Installer = New-Object -ComObject WindowsInstaller.Installer
        $Database = $Installer.OpenDatabase($Path, 0) # 0 is ReadOnly
        $View = $Database.OpenView("SELECT Property, Value FROM Property")
        $View.Execute()
        while ($Record = $View.Fetch()) {
            $propName = $Record.StringData(1)
            $propVal = $Record.StringData(2)
            if ($propName -eq 'ProductCode') { $msi.product_code = $propVal }
            elseif ($propName -eq 'ProductName') { $msi.product_name = $propVal }
            elseif ($propName -eq 'ProductVersion') { $msi.product_version = $propVal }
            elseif ($propName -eq 'Manufacturer') { $msi.manufacturer = $propVal }
        }
        $View.Close()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Installer) | Out-Null
    } catch {
        # Silent fallback
    }
    return $msi
}

function Get-DangerousIndicators {
    param([string]$TextContent)
    $indicators = [System.Collections.Generic.List[string]]::new()
    
    if ($TextContent -match 'reg\.exe|reg\s+add|reg\s+delete|regedit|Registry|New-ItemProperty|Set-ItemProperty|Remove-ItemProperty') {
        $indicators.Add("registry_changes")
    }
    if ($TextContent -match 'sc\.exe|sc\s+create|sc\s+delete|sc\s+config|New-Service|Set-Service|Start-Service|Stop-Service|Remove-Service') {
        $indicators.Add("services")
    }
    if ($TextContent -match 'schtasks|New-ScheduledTask|Register-ScheduledTask|Unregister-ScheduledTask') {
        $indicators.Add("scheduled_tasks")
    }
    if ($TextContent -match 'reboot|restart-computer|shutdown\.exe|restart|/forcerestart|/norestart') {
        $indicators.Add("reboot")
    }
    if ($TextContent -match 'AutoLogon|DefaultPassword|DefaultUserName|AutoAdminLogon|Winlogon') {
        $indicators.Add("autologon")
    }
    if ($TextContent -match 'net\s+user|net\s+localgroup|New-LocalUser|Add-LocalGroupMember') {
        $indicators.Add("account_changes")
    }
    if ($TextContent -match 'netsh\s+advfirewall|New-NetFirewallRule|Set-NetFirewallRule') {
        $indicators.Add("firewall_changes")
    }
    if ($TextContent -match 'rmdir\s+/s\s+/q|Remove-Item\s+-Recurse|del\s+/f\s+/s\s+/q') {
        $indicators.Add("broad_deletion")
    }
    if ($TextContent -match 'del\s+%0|del\s+"%~f0"') {
        $indicators.Add("self_removal")
    }
    if ($TextContent -match '/q|/s|/qn|/qb|/silent|/norestart') {
        $indicators.Add("silent_switches")
    }

    return $indicators.ToArray()
}

if ($FixtureOnly) {
    Write-Verbose "Generating fixture-only mock inventory."
    $mockPackages = @(
        @{
            relative_path = "tech emulation/Alex/Installers/Epic/Satellite/EpicSatelliteSetup.exe"
            file_class = "installer"
            size_bytes = 12500000
            sha256 = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
            authenticode = @{
                status = "Valid"
                signer = "CN=Epic Systems Corporation, O=Epic Systems Corporation, L=Verona, S=Wisconsin, C=US"
            }
            file_version_info = @{
                product_name = "Epic Satellite Client"
                product_version = "2026.1.0"
                file_version = "2026.1.0.42"
                company_name = "Epic Systems Corporation"
            }
            msi_info = $null
            archive_type = $null
            referenced_dependencies = @()
            embedded_or_adjacent_configs = @()
            likely_reboot_requirements = @()
            likely_application_executables = @()
            dangerous_indicators = @("silent_switches")
            installer_arguments = @("/q", "/norestart")
            classification = "vm_candidate"
        },
        @{
            relative_path = "tech emulation/Alex/Installers/Allscripts/TWInstaller.exe"
            file_class = "installer"
            size_bytes = 85000000
            sha256 = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
            authenticode = @{
                status = "NotSigned"
                signer = $null
            }
            file_version_info = @{
                product_name = "Allscripts TouchWorks installer"
                product_version = "22.1.0"
                file_version = "22.1.0.100"
                company_name = "Allscripts"
            }
            msi_info = $null
            archive_type = $null
            referenced_dependencies = @()
            embedded_or_adjacent_configs = @()
            likely_reboot_requirements = @()
            likely_application_executables = @()
            dangerous_indicators = @()
            installer_arguments = $null
            classification = "blocked_missing_evidence"
        },
        @{
            relative_path = "tech emulation/Alex/Installers/AutoLogonSetup/NW_AutoLogon_Setup_x64.exe"
            file_class = "installer"
            size_bytes = 5400000
            sha256 = "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
            authenticode = @{
                status = "Valid"
                signer = "CN=Northwell Health, O=Northwell Health, C=US"
            }
            file_version_info = @{
                product_name = "Northwell AutoLogon Configurator"
                product_version = "1.2.0"
                file_version = "1.2.0.0"
                company_name = "Northwell Health"
            }
            msi_info = $null
            archive_type = $null
            referenced_dependencies = @()
            embedded_or_adjacent_configs = @()
            likely_reboot_requirements = @("reboot")
            likely_application_executables = @()
            dangerous_indicators = @("autologon", "reboot", "registry_changes")
            installer_arguments = @("/silent")
            classification = "requires_physical_cybernet"
        }
    )

    $inventory = @{
        schema_version = "sas-local-package-inventory/v1"
        generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        scan_root = "fixture-only"
        packages = $mockPackages
    }

    $json = ConvertTo-Json $inventory -Depth 10
    if ($OutputPath) {
        New-Item -ItemType File -Path $OutputPath -Force | Out-Null
        [System.IO.File]::WriteAllText($OutputPath, $json)
    }
    return $inventory
}

if (-not (Test-Path $ScanPath)) {
    throw "Scan path '$ScanPath' does not exist."
}

$scanRootAbs = (Resolve-Path $ScanPath).Path
$repoRoot = (git rev-parse --show-toplevel).Replace('/', '\')

$packages = [System.Collections.Generic.List[object]]::new()
$files = Get-ChildItem -Path $ScanPath -Recurse -File

foreach ($file in $files) {
    # 1. Path Calculation
    $relPath = $file.FullName
    if ($relPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relPath = $relPath.Substring($repoRoot.Length).TrimStart('\')
    }
    $relPath = $relPath.Replace('\', '/')

    # 2. File Class
    $ext = $file.Extension.ToLowerInvariant()
    $fileClass = "other"
    if ($ext -in '.msi', '.exe', '.msix', '.msixbundle', '.appx') {
        $fileClass = "installer"
    } elseif ($ext -in '.ps1', '.psm1', '.bat', '.cmd', '.vbs', '.js', '.sh') {
        $fileClass = "script"
    } elseif ($ext -in '.lnk', '.url') {
        $fileClass = "shortcut"
    } elseif ($ext -in '.xml', '.json', '.ini', '.cfg', '.config', '.manifest', '.inf') {
        $fileClass = "configuration"
    } elseif ($ext -in '.zip', '.cab', '.tar', '.gz', '.tgz') {
        $fileClass = "archive"
    }

    # 3. Basic Metadata
    $size = $file.Length
    $sha256 = Get-FileSha256 -Path $file.FullName

    # 4. Authenticode Signature
    $authStatus = "NotSigned"
    $authSigner = $null
    try {
        $sig = Get-AuthenticodeSignature -FilePath $file.FullName
        $authStatus = $sig.Status.ToString()
        if ($sig.SignerCertificate) {
            $authSigner = $sig.SignerCertificate.Subject
        }
    } catch {
        $authStatus = "UnknownError"
    }

    # 5. Version Info
    $viProduct = $null
    $viProductVer = $null
    $viFileVer = $null
    $viCompany = $null
    if ($ext -in '.exe', '.dll') {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
            $viProduct = $vi.ProductName
            $viProductVer = $vi.ProductVersion
            $viFileVer = $vi.FileVersion
            $viCompany = $vi.CompanyName
        } catch {}
    }
    $versionInfo = @{
        product_name = $viProduct
        product_version = $viProductVer
        file_version = $viFileVer
        company_name = $viCompany
    }

    # 6. MSI Properties (Read-Only COM)
    $msiInfo = $null
    if ($ext -eq '.msi') {
        $msiInfo = Get-MsiInfo -Path $file.FullName
    }

    # 7. Archive Type
    $archiveType = $null
    if ($fileClass -eq 'archive') {
        $archiveType = $ext.TrimStart('.')
    } elseif ($ext -in '.msixbundle', '.msix') {
        $archiveType = "appx_bundle"
    }

    # 8. Script/Config/Shortcuts Scanning
    $referencedDeps = [System.Collections.Generic.List[string]]::new()
    $embeddedConfigs = [System.Collections.Generic.List[string]]::new()
    $rebootReqs = [System.Collections.Generic.List[string]]::new()
    $appExes = [System.Collections.Generic.List[string]]::new()
    $dangerousInds = [System.Collections.Generic.List[string]]::new()
    $installerArgs = $null

    # If it is a text-based file, parse content
    $isText = $ext -in '.ps1', '.psm1', '.bat', '.cmd', '.vbs', '.js', '.sh', '.xml', '.json', '.ini', '.cfg', '.config', '.txt', '.md'
    if ($isText) {
        try {
            $content = [System.IO.File]::ReadAllText($file.FullName)
            
            # Dangerous indicators
            $dangerousInds.AddRange((Get-DangerousIndicators -TextContent $content))

            # Look for reboot cues
            if ($content -match 'reboot|restart|shutdown') {
                $rebootReqs.Add("Stated in content")
            }

            # Find executables mentioned in the text
            $matches = [regex]::Matches($content, '\b[\w-]+\.exe\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                if ($match.Value -ne $file.Name) {
                    $appExes.Add($match.Value)
                }
            }

            # Look for installer invocation pattern to extract installer arguments
            # e.g. installer.exe /S /qn
            # Only match if the exe is in the same folder or listed in installers
            $argsMatches = [regex]::Matches($content, '([\w-]+\.exe)\s+([^`\r\n&|;]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($am in $argsMatches) {
                $exeName = $am.Groups[1].Value
                $argStr = $am.Groups[2].Value.Trim()
                if ($argStr -match '/q|/s|/qn|/qb|/silent|/norestart|/S|/S\s+|/qn\s+') {
                    $argsList = [System.Collections.Generic.List[string]]::new()
                    $argStr -split '\s+' | ForEach-Object {
                        if ($_ -like '/*') { $argsList.Add($_) }
                    }
                    if ($argsList.Count -gt 0) {
                        $installerArgs = $argsList.ToArray()
                    }
                }
            }
        } catch {}
    }

    # If it is a shortcut, extract target
    if ($ext -eq '.lnk') {
        try {
            $sh = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($file.FullName)
            if ($lnk.TargetPath) {
                $appExes.Add($lnk.TargetPath)
                if ($lnk.Arguments) {
                    $referencedDeps.Add($lnk.Arguments)
                }
            }
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
        } catch {}
    } elseif ($ext -eq '.url') {
        try {
            $lines = Get-Content -Path $file.FullName
            foreach ($line in $lines) {
                if ($line -match '^URL=(.+)$') {
                    $referencedDeps.Add($matches[1])
                }
            }
        } catch {}
    }

    # Check for adjacent config file
    $fileDir = $file.DirectoryName
    if ($fileDir) {
        $adjacentFiles = Get-ChildItem -Path $fileDir -File
        foreach ($adj in $adjacentFiles) {
            if ($adj.Extension.ToLowerInvariant() -in '.xml', '.json', '.ini', '.cfg', '.config') {
                $embeddedConfigs.Add($adj.Name)
            }
        }
    }

    # 9. Argument and Classification determination
    if ($fileClass -eq 'installer') {
        # Check if we found arguments from adjacent scripts
        if ($null -eq $installerArgs) {
            if ($ext -eq '.msi') {
                # Default quiet/norestart arguments are safe to resolve for MSIs
                $installerArgs = @("/qn", "/norestart")
            } else {
                # For EXEs, do not guess
                $installerArgs = $null
            }
        }

        # Check dangerous indicators on the installer path directory level
        # E.g. scan if there are scripts in the same folder that indicate reboot or autologon
        $parentScripts = Get-ChildItem -Path $file.DirectoryName -Filter "*.*" -File
        foreach ($ps in $parentScripts) {
            if ($ps.Extension.ToLowerInvariant() -in '.ps1', '.psm1', '.bat', '.cmd') {
                try {
                    $psContent = [System.IO.File]::ReadAllText($ps.FullName)
                    $dangerousInds.AddRange((Get-DangerousIndicators -TextContent $psContent))
                } catch {}
            }
        }

        $allInds = $dangerousInds | Select-Object -Unique

        # Classify
        if ($allInds -contains 'autologon') {
            $classification = "requires_physical_cybernet"
        } elseif ($allInds -contains 'reboot' -or $allInds -contains 'services') {
            $classification = "requires_reboot_vm"
        } elseif ($null -eq $installerArgs) {
            $classification = "blocked_missing_evidence"
        } else {
            $classification = "vm_candidate"
        }
    } else {
        $classification = "inventory_only"
    }

    $packages.Add(@{
        relative_path = $relPath
        file_class = $fileClass
        size_bytes = $size
        sha256 = $sha256
        authenticode = @{
            status = $authStatus
            signer = $authSigner
        }
        file_version_info = $versionInfo
        msi_info = $msiInfo
        archive_type = $archiveType
        referenced_dependencies = ($referencedDeps | Select-Object -Unique | Where-Object {$_})
        embedded_or_adjacent_configs = ($embeddedConfigs | Select-Object -Unique | Where-Object {$_})
        likely_reboot_requirements = ($rebootReqs | Select-Object -Unique | Where-Object {$_})
        likely_application_executables = ($appExes | Select-Object -Unique | Where-Object {$_})
        dangerous_indicators = ($dangerousInds | Select-Object -Unique | Where-Object {$_})
        installer_arguments = $installerArgs
        classification = $classification
    })
}

$inventory = @{
    schema_version = "sas-local-package-inventory/v1"
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    scan_root = $(
        $scanRootRel = $scanRootAbs
        if ($scanRootRel.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $scanRootRel = $scanRootRel.Substring($repoRoot.Length).TrimStart('\')
        }
        $scanRootRel.Replace('\', '/')
    )
    packages = $packages.ToArray()
}

$json = ConvertTo-Json $inventory -Depth 10
if ($OutputPath) {
    $parentDir = Split-Path -Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $OutputPath -Force | Out-Null
    [System.IO.File]::WriteAllText($OutputPath, $json)
}

return $inventory
