Set-StrictMode -Version Latest

function Test-SasIpLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $parsed = $null
    return [System.Net.IPAddress]::TryParse($Value.Trim().Trim([char[]]'[]'), [ref]$parsed)
}

function ConvertTo-SasLdapFilterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Value.ToCharArray()) {
        switch ([int][char]$character) {
            0  { [void]$builder.Append('\00') }
            40 { [void]$builder.Append('\28') }
            41 { [void]$builder.Append('\29') }
            42 { [void]$builder.Append('\2a') }
            92 { [void]$builder.Append('\5c') }
            default { [void]$builder.Append($character) }
        }
    }
    return $builder.ToString()
}

function Resolve-SasNorthwellTargetComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$DnsSuffix = 'nslijhs.net'
    )

    $name = $ComputerName.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Target computer name cannot be blank.'
    }
    if ($name -match '^[\\/]{2}' -or $name -match '^[a-zA-Z]+://' -or $name -match '[\\/]') {
        throw "Target '$ComputerName' must be a Windows hostname or FQDN, not a path or URL."
    }
    if (Test-SasIpLiteral -Value $name) {
        throw "Target '$ComputerName' is an IP address. Northwell workstation targets must be specified by hostname/FQDN."
    }
    if ($name -notmatch '^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$') {
        throw "Target '$ComputerName' is not a valid hostname/FQDN."
    }

    if ($name.Contains('.')) {
        return $name
    }
    if ([string]::IsNullOrWhiteSpace($DnsSuffix)) {
        return $name
    }
    return "$name.$($DnsSuffix.Trim('.'))"
}

function Resolve-SasPrinterQueueFromDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$QueueName
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop
        $rootDse = [ADSI]'LDAP://RootDSE'
        $namingContext = [string]$rootDse.defaultNamingContext
        if ([string]::IsNullOrWhiteSpace($namingContext)) {
            throw 'Active Directory defaultNamingContext is unavailable.'
        }

        $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$namingContext")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $escaped = ConvertTo-SasLdapFilterValue -Value $QueueName
        $searcher.Filter = "(&(objectCategory=printQueue)(|(printerName=$escaped)(name=$escaped)(uNCName=*\5c$escaped)))"
        $searcher.PageSize = 500
        [void]$searcher.PropertiesToLoad.Add('uNCName')
        [void]$searcher.PropertiesToLoad.Add('printerName')

        $found = New-Object System.Collections.Generic.List[string]
        foreach ($result in $searcher.FindAll()) {
            if (-not $result.Properties['uncname'] -or $result.Properties['uncname'].Count -eq 0) { continue }
            $unc = [string]$result.Properties['uncname'][0]
            if ($unc -notmatch '^\\\\[^\\]+\\([^\\]+)$') { continue }
            if (-not $Matches[1].Equals($QueueName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $found.Add($unc)
        }

        return @($found | Sort-Object -Unique)
    }
    catch {
        throw "Active Directory printer-queue lookup failed for '$QueueName': $($_.Exception.Message)"
    }
}

function ConvertTo-SasNorthwellPrinterUnc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Printer,

        [string]$PrintServer,

        [scriptblock]$DirectoryResolver
    )

    $value = $Printer.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw 'Printer queue cannot be blank.'
    }
    if ($value -match '^[a-zA-Z]+://') {
        throw "Printer '$Printer' is a URL. Northwell mapping requires a shared Windows queue, not IPP/HTTP/direct-IP printing."
    }

    if ($value.StartsWith('//')) {
        $value = '\\' + $value.Substring(2).Replace('/', '\')
    }

    if ($value.StartsWith('\\')) {
        if ($value -notmatch '^\\\\([^\\]+)\\([^\\]+)$') {
            throw "Printer '$Printer' must be exactly \\server\queue (no IP, port, URL, or extra path)."
        }
        $server = $Matches[1]
        $queue = $Matches[2]
        if (Test-SasIpLiteral -Value $server) {
            throw "Printer '$Printer' uses an IP address as the print server. Northwell printers must be mapped by shared queue name."
        }
        if (Test-SasIpLiteral -Value $queue) {
            throw "Printer '$Printer' looks like a direct-IP mapping. Northwell printers must be mapped by queue name."
        }
        return "\\$server\$queue"
    }

    if ($value -match '[\\/]') {
        throw "Printer '$Printer' is ambiguous. Use a queue name only or \\server\queue."
    }
    if (Test-SasIpLiteral -Value $value) {
        throw "Printer '$Printer' is an IP address. Northwell printers must be mapped by queue name."
    }

    if (-not [string]::IsNullOrWhiteSpace($PrintServer)) {
        $server = $PrintServer.Trim().TrimStart([char[]]'\/')
        if ([string]::IsNullOrWhiteSpace($server) -or $server -match '[\\/]' -or $server -match '^[a-zA-Z]+://' -or (Test-SasIpLiteral -Value $server)) {
            throw "PrintServer '$PrintServer' must be a server hostname/FQDN, never an IP address or path."
        }
        return "\\$server\$value"
    }

    $matches = if ($DirectoryResolver) {
        @(& $DirectoryResolver $value)
    }
    else {
        @(Resolve-SasPrinterQueueFromDirectory -QueueName $value)
    }
    $matches = @($matches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    if ($matches.Count -eq 0) {
        throw "Queue '$value' was not uniquely published in Active Directory. Pass the full \\server\queue path or add -PrintServer <server>."
    }
    if ($matches.Count -gt 1) {
        throw "Queue '$value' is ambiguous in Active Directory: $($matches -join ', '). Pass the full \\server\queue path."
    }

    return ConvertTo-SasNorthwellPrinterUnc -Printer $matches[0]
}

Export-ModuleMember -Function @(
    'Test-SasIpLiteral',
    'Resolve-SasNorthwellTargetComputer',
    'Resolve-SasPrinterQueueFromDirectory',
    'ConvertTo-SasNorthwellPrinterUnc'
)
