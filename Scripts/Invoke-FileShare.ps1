function Invoke-FileShare {
    [CmdletBinding()]
    param(
        [string]$SharePath = "\\LPW003ASI037\c$"
    )

    if (-not (Test-Path $SharePath)) {
        throw "Cannot access share $SharePath"
    }

    Get-ChildItem $SharePath
}
