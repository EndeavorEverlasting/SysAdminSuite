<#
.SYNOPSIS
    Tests access to a UNC share and lists its top-level contents.

.DESCRIPTION
    Validates that a UNC share is reachable via Test-Path, then returns
    the top-level directory listing. Useful for quick admin-share reachability
    checks before deploying files to remote hosts.

.PARAMETER SharePath
    UNC path to the share (e.g. \\HOST\C$). Default: \\LPW003ASI037\C$.

.EXAMPLE
    Invoke-FileShare -SharePath '\\PRINTSRV\C$'
    # Lists top-level contents of \\PRINTSRV\C$ if reachable.
#>
function Invoke-FileShare {
    [CmdletBinding()]
    param(
        [string]$SharePath = '\\LPW003ASI037\C$'
    )

    if (-not (Test-Path -LiteralPath $SharePath)) {
        throw "Cannot access share: $SharePath — check network/firewall/credentials."
    }

    Get-ChildItem -LiteralPath $SharePath
}