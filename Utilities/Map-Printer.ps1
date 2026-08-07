<#
.SYNOPSIS
    Adds a single per-user printer connection by UNC path.

.DESCRIPTION
    Lightweight helper that wraps Add-Printer -ConnectionName.

    IMPORTANT: This is a PER-USER helper. It does not satisfy the Northwell
    shared/multi-user PC requirement. For Northwell field printer mapping use:
      .\mapping\Invoke-NorthwellPrinterMapping.ps1

    The Northwell entrypoint validates queue-name inputs, rejects printer IP
    mappings, runs the remote action as SYSTEM, uses PrintUIEntry /ga, and
    verifies the per-computer connection under HKLM.

    For other machine-wide (SYSTEM-context) deployments, use the workers in
    mapping\Workers\ instead.
    Supports -WhatIf for dry-run testing.

.PARAMETER PrinterPath
    Full UNC path to the print queue, e.g. \\PRINTSRV\QueueName.

.EXAMPLE
    Map-Printer -PrinterPath '\\SWBPNHPHPS01V\LS111-WCC67'
    # Adds the per-user printer connection. NOT the Northwell multi-user path.

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

    Write-Warning 'Map-Printer is per-user only. For Northwell shared/multi-user PCs use mapping\Invoke-NorthwellPrinterMapping.ps1.'

    if ($PSCmdlet.ShouldProcess($PrinterPath, 'Add-Printer -ConnectionName')) {
        Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop
        Write-Host "Mapped per-user printer: $PrinterPath"
    }
}
