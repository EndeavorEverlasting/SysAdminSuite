<#
.SYNOPSIS
    Tests access to a UNC share and lists its top-level contents.

.DESCRIPTION
    Validates that a UNC share is reachable via Test-Path, then returns
    the top-level directory listing. Useful for quick admin-share reachability
    checks before deploying files to remote hosts.

.PARAMETER SharePath
    UNC path to the share (e.g. \\HOST\C$). Defaults to FILE_SHARE_PATH env var when set.

.EXAMPLE
    Invoke-FileShare -SharePath '\\PRINTSRV\C$'
    # Lists top-level contents of \\PRINTSRV\C$ if reachable.
#>
function Invoke-FileShare {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$SharePath = $env:FILE_SHARE_PATH
    )

    if (-not (Test-Path -LiteralPath $SharePath)) {
        throw "Cannot access share: $SharePath -- check network/firewall/credentials."
    }

    Get-ChildItem -LiteralPath $SharePath
}