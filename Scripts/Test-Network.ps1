function Test-Network {
    [CmdletBinding()]
    param(
        [string]$Host = '8.8.8.8'
    )

    Test-Connection -ComputerName $Host -Count 2 -ErrorAction SilentlyContinue
}
