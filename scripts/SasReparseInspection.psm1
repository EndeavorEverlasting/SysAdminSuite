#Requires -Version 5.1
Set-StrictMode -Version 2.0

# Bounded Windows reparse-point inspection for canonical-path admission.
# Only the OneDrive/Cloud Files placeholder family is classified as safely
# inspectable. Junctions, symlinks, and every unknown tag remain unsafe so
# the canonical resolver keeps its fail-closed posture.

function Get-SasFileSystemReparseTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not ('SasReparseTagReader534V1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SasReparseTagReader534V1 {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    private static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle hDevice, uint dwIoControlCode, IntPtr lpInBuffer, uint nInBufferSize, byte[] lpOutBuffer, uint nOutBufferSize, out uint lpBytesReturned, IntPtr lpOverlapped);
    public static uint GetReparseTag(string path) {
        const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        const uint FSCTL_GET_REPARSE_POINT = 0x000900A8;
        using (SafeFileHandle handle = CreateFileW(path, 0, 7, IntPtr.Zero, 3, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero)) {
            if (handle.IsInvalid) { throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed for reparse inspection: " + path); }
            byte[] buffer = new byte[16384];
            uint returned;
            if (!DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, IntPtr.Zero, 0, buffer, (uint)buffer.Length, out returned, IntPtr.Zero)) { throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "FSCTL_GET_REPARSE_POINT failed: " + path); }
            return BitConverter.ToUInt32(buffer, 0);
        }
    }
}
'@ -ErrorAction Stop
    }
    try {
        return [uint32][SasReparseTagReader534V1]::GetReparseTag($Path)
    } catch {
        return $null
    }
}

function Resolve-SasReparseTagClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uint32]$Tag
    )

    # OneDrive/Cloud Files placeholder family: 0x9000X01A (X = 0..F).
    # IO_REPARSE_TAG_CLOUD is 0x9000001A; bits 12-15 select the placeholder
    # variant. Junctions (IO_REPARSE_TAG_MOUNT_POINT 0xA0000003), symlinks
    # (IO_REPARSE_TAG_SYMLINK 0xA000000C), legacy OneDrive tags, and every
    # other tag stay unsafe for canonical admission. The L suffix keeps the
    # wide hex literals typed as Int64 instead of wrapping to negative Int32.
    if (([uint64]$Tag -band [uint64]0xFFFF0FFFL) -eq [uint64]0x9000001AL) {
        return 'ONEDRIVE_CLOUD_PLACEHOLDER'
    }
    return 'UNSAFE'
}

function Test-SasCanonicalReparseSafety {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $observed = New-Object 'System.Collections.Generic.List[string]'
    try {
        $full = [IO.Path]::GetFullPath($Path)
    } catch {
        return [pscustomobject][ordered]@{ classification = 'UNKNOWN'; observed_tags = @() }
    }
    $drive = [IO.Path]::GetPathRoot($full)
    $relative = $full.Substring($drive.Length).TrimEnd('\')
    $components = @($relative -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $prefix = $drive.TrimEnd('\')
    foreach ($component in $components) {
        $prefix = $prefix + '\' + $component
        $item = $null
        try { $item = Get-Item -LiteralPath $prefix -Force -ErrorAction Stop } catch { continue }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { continue }
        $tag = Get-SasFileSystemReparseTag -Path $prefix
        if ($null -eq $tag) {
            return [pscustomobject][ordered]@{ classification = 'UNKNOWN'; observed_tags = @($observed) }
        }
        [void]$observed.Add(('0x{0:x8}' -f [uint32]$tag))
        if ((Resolve-SasReparseTagClassification -Tag ([uint32]$tag)) -ne 'ONEDRIVE_CLOUD_PLACEHOLDER') {
            return [pscustomobject][ordered]@{ classification = 'UNSAFE'; observed_tags = @($observed) }
        }
    }
    if ($observed.Count -eq 0) {
        return [pscustomobject][ordered]@{ classification = 'NONE'; observed_tags = @() }
    }
    return [pscustomobject][ordered]@{ classification = 'ONEDRIVE_CLOUD_PLACEHOLDER'; observed_tags = @($observed) }
}

Export-ModuleMember -Function Get-SasFileSystemReparseTag, Resolve-SasReparseTagClassification, Test-SasCanonicalReparseSafety
