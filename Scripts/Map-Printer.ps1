function Map-Printer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrinterPath
    )

    Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop
    Write-Host "Mapped printer $PrinterPath"
}
