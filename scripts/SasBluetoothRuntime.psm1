$ErrorActionPreference='Stop'

function Get-SasBluetoothHash([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','') }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Get-SasBluetoothCapabilities {
    $admin=$false
    if($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage') {
        $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    $services=@(Get-Service BluetoothUserService_* -ErrorAction SilentlyContinue | Select-Object Name,@{n='Status';e={[string]$_.Status}},@{n='StartType';e={[string]$_.StartType}})
    [pscustomobject]@{
        Schema='sas-bluetooth-capabilities/v1'
        LanguageMode=[string]$ExecutionContext.SessionState.LanguageMode
        PowerShellVersion=[string]$PSVersionTable.PSVersion
        Elevated=$admin
        UserServices=$services
        ServiceSelection=if($services.Count -eq 1){'SINGLE_INSTANCE'}else{'EXACT_SERVICE_NAME_REQUIRED'}
        PreparedRuntimePresent=(Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\runtime\SasBluetoothPairing.dll'))
        PairingContext='INTENDED_INTERACTIVE_USER_SESSION'
        AdminRepairs='REQUIRE_EXISTING_ADMIN_OR_DELEGATED_SERVICE_RIGHTS'
        SecurityPolicy='NO_UAC_OR_MACHINE_POLICY_CHANGES'
    }
}

function New-SasBluetoothHelper([string]$Destination) {
    if($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){throw 'CONSTRAINED_LANGUAGE: native helper requires approved host policy.'}
    $winmd=@(Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\UnionMetadata\*\Windows.winmd" -ErrorAction SilentlyContinue | Where-Object {$_.Directory.Name -match '^\d+\.\d+\.\d+\.\d+$'} | Sort-Object @{e={[version]$_.Directory.Name}} -Descending | Select-Object -First 1)
    if($winmd.Count -ne 1){throw 'PREPARED_RUNTIME_REQUIRED: compile a portable bundle on a Windows SDK preparation host.'}
    $framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
    $gac=Join-Path $env:SystemRoot 'Microsoft.NET\assembly\GAC_MSIL'
    $refs=@($winmd[0].FullName,(Join-Path $framework 'System.Runtime.WindowsRuntime.dll'),(Join-Path $gac 'System.Runtime\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Runtime.dll'),(Join-Path $gac 'System.Runtime.InteropServices.WindowsRuntime\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Runtime.InteropServices.WindowsRuntime.dll'))
    foreach($ref in $refs){if(-not (Test-Path -LiteralPath $ref)){throw 'NATIVE_RUNTIME_PREREQUISITE_MISSING'}}
    $args=@('/nologo','/target:library',('/out:'+$Destination))+@($refs|ForEach-Object {'/r:'+$_})+@(Join-Path $PSScriptRoot 'SasBluetoothPairing.cs')
    $output=& (Join-Path $framework 'csc.exe') @args 2>&1
    if($LASTEXITCODE -ne 0){throw ('NATIVE_HELPER_BUILD_FAILED: '+($output -join [Environment]::NewLine))}
    Get-SasBluetoothHash $Destination
}

function Test-SasBluetoothBundle([string]$Root) {
    $manifestPath=Join-Path $Root 'bluetooth-bundle.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if($manifest.Schema -ne 'sas-bluetooth-bundle/v1'){throw 'INVALID_BUNDLE_SCHEMA'}
    $required=@('scripts/SasBluetoothRuntime.psm1','scripts/Add-BluetoothMouse.ps1','scripts/SasBluetooth.ps1','scripts/SasBluetoothPairing.cs','scripts/Invoke-BluetoothPeripheralRecovery.ps1','scripts/Install-BluetoothPeripheralRelease.ps1','Install-BluetoothPeripheralRelease.cmd','runtime/SasBluetoothPairing.dll')
    $names=@($manifest.Files|ForEach-Object {$_.Path})
    foreach($name in $required){if($names -notcontains $name){throw "BUNDLE_ENTRY_MISSING: $name"}}
    foreach($entry in $manifest.Files) {
        if([IO.Path]::IsPathRooted($entry.Path) -or $entry.Path -match '(^|[\\/])\.\.([\\/]|$)'){throw 'UNSAFE_BUNDLE_PATH'}
        $path=Join-Path $Root $entry.Path
        if((Get-SasBluetoothHash $path) -ne $entry.SHA256){throw ('BUNDLE_HASH_MISMATCH: '+$entry.Path)}
    }

    # Fail if a prepared bundle contains extra executables, duplicate manifest
    # entries or directory links. Hashes must cover the entire executable set.
    if(@($names | Group-Object | Where-Object {$_.Count -gt 1}).Count) {
        throw 'BUNDLE_DUPLICATE_ENTRY'
    }
    $prefix=[IO.Path]::GetFullPath($Root).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $declared=@($names)+@('bluetooth-bundle.json')
    foreach($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)) {
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'BUNDLE_REPARSE_POINT'
        }
        if(-not $item.PSIsContainer) {
            $relative=$item.FullName.Substring($prefix.Length).Replace([char]92,[char]47)
            if($declared -cnotcontains $relative) {
                throw ('BUNDLE_UNLISTED_FILE: '+$relative)
            }
        }
    }
    return $true
}

function Import-SasBluetoothHelper([string]$BuildRoot) {
    $root=Split-Path $PSScriptRoot -Parent
    $manifest=Join-Path $root 'bluetooth-bundle.json'
    if(Test-Path -LiteralPath $manifest) {
        $null=Test-SasBluetoothBundle $root
        $dll=Join-Path $root 'runtime\SasBluetoothPairing.dll'
    } else {
        $dll=Join-Path $BuildRoot 'SasBluetoothPairing.dll'
        $null=New-SasBluetoothHelper $dll
    }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    if(-not ('SasBluetoothPairing' -as [type])){Add-Type -Path $dll}
}

Export-ModuleMember -Function Get-SasBluetoothHash,Get-SasBluetoothCapabilities,New-SasBluetoothHelper,Test-SasBluetoothBundle,Import-SasBluetoothHelper
