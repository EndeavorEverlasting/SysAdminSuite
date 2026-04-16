<#
.SYNOPSIS
    Adds a single per-user printer connection by UNC path.

.DESCRIPTION
    Lightweight helper that wraps Add-Printer -ConnectionName.
    For machine-wide (SYSTEM-context) deployments use the workers in
    Mapping\Workers\ instead.
    Supports -WhatIf for dry-run testing.

.PARAMETER PrinterPath
    Full UNC path to the print queue, e.g. \\PRINTSRV\QueueName.

.EXAMPLE
    Map-Printer -PrinterPath '\\SWBPNHPHPS01V\LS111-WCC67'
    # Adds the per-user printer connection.

.EXAMPLE
    Map-Printer -PrinterPath '\\SWBPNHPHPS01V\LS111-WCC67' -WhatIf
    # Dry-run: shows what would happen without making changes.
#>
function Map-Printer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PrinterPath
    )

    if ($PSCmdlet.ShouldProcess($PrinterPath, 'Add-Printer -ConnectionName')) {
        Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop
        Write-Host "Mapped printer: $PrinterPath"
    }
}