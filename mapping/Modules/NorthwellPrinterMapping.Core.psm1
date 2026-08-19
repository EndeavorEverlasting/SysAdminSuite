Set-StrictMode -Version Latest

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:TargetResolutionModule = Join-Path $script:RepoRoot 'scripts\SasTargetNameResolution.psm1'
if (-not (Test-Path -LiteralPath $script:TargetResolutionModule)) {
    throw "Canonical target-resolution module not found: $script:TargetResolutionModule"
}
Import-Module $script:TargetResolutionModule -Force -ErrorAction Stop

function Test-SasIpLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $parsed = $null
    return [System.Net.IPAddress]::TryParse($Value.Trim().Trim([char[]]'[]'), [ref]$parsed)
}

function Test-SasHostnameValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $name = $Value.Trim()
    return $name -match '^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'
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

        [string]$DnsSuffix = 'nslijhs.net',

        [scriptblock]$CanonicalResolver
    )

    $name = $ComputerName.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Target computer name cannot be blank.'
    }
    if ($name -match '^[\\/]{2}' -or $name -match '^[a-zA-Z]+://' -or $name -match '[\\/]') {
        throw "Target '$ComputerName' must be a Windows hostname or FQDN, not a path or URL."
    }
    if (Test-SasIpLiteral -Value $name) {
        throw "Target '$ComputerName' is an IP address. Northwell workstation targets must be specified by hostname/FQDN."
    }
    if (-not (Test-SasHostnameValue -Value $name)) {
        throw "Target '$ComputerName' is not a valid hostname/FQDN."
    }

    $suffix = $DnsSuffix.Trim().Trim('.')
    if ($CanonicalResolver) {
        $resolution = & $CanonicalResolver $name $suffix
    }
    else {
        $resolution = Resolve-SasCanonicalTargetFqdn -TargetName $name -SuffixCandidates @($suffix)
    }

    if ($null -eq $resolution) {
        throw "Target '$ComputerName' did not resolve to one canonical FQDN."
    }

    $fqdn = [string]$resolution.fqdn
    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        throw "Target '$ComputerName' did not resolve to one canonical FQDN."
    }
    $fqdn = $fqdn.Trim().TrimEnd('.').ToLowerInvariant()

    $inputShort = $name.Split('.')[0]
    $resolvedShort = $fqdn.Split('.')[0]
    if (-not $resolvedShort.Equals($inputShort, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'DNS resolved the supplied name to a different canonical host identity. Stop before target mutation.'
    }
    if ($name.Contains('.') -and -not $fqdn.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'DNS resolved the supplied FQDN to a different canonical host identity. Stop before target mutation.'
    }

    if (-not [string]::IsNullOrWhiteSpace($suffix)) {
        $approvedSuffix = ".{0}" -f $suffix
        if (-not $fqdn.EndsWith($approvedSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Target '$ComputerName' resolved outside the approved Northwell DNS suffix '$suffix'. Stop before target mutation."
        }
    }

    return $fqdn
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
        if (-not (Test-SasHostnameValue -Value $server)) {
            throw "Printer '$Printer' contains an invalid print-server hostname. Use \\server\queue with a hostname/FQDN, never an IP or port."
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
        if ([string]::IsNullOrWhiteSpace($server) -or (Test-SasIpLiteral -Value $server) -or -not (Test-SasHostnameValue -Value $server)) {
            throw "PrintServer '$PrintServer' must be a server hostname/FQDN, never an IP address, port, or path."
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

function Split-SasNorthwellPrinterBatchField {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    $items = @(
        ([string]$Value) -split '\s*;\s*' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($items.Count -eq 0) {
        throw "$Label cannot be blank. Use semicolons inside a CSV cell when listing more than one value."
    }
    return $items
}

function ConvertTo-SasNorthwellPrinterBatchGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [scriptblock]$PrinterResolver
    )

    if (@($Rows).Count -eq 0) {
        throw 'Northwell printer batch contains no data rows.'
    }

    $groups = New-Object System.Collections.Generic.List[object]
    $rowNumber = 1
    foreach ($row in @($Rows)) {
        $rowNumber++
        foreach ($required in @('ComputerName','PrintServer','QueueName')) {
            if ($null -eq $row.PSObject.Properties[$required]) {
                throw "Northwell printer batch is missing required CSV column '$required'."
            }
        }

        $computers = @(Split-SasNorthwellPrinterBatchField -Value ([string]$row.ComputerName) -Label "Row $rowNumber ComputerName")
        $queues = @(Split-SasNorthwellPrinterBatchField -Value ([string]$row.QueueName) -Label "Row $rowNumber QueueName")
        $server = ([string]$row.PrintServer).Trim()

        foreach ($computer in $computers) {
            if ($computer -match '(?i)(REPLACE-WITH|EXAMPLE|PC-HOSTNAME)') {
                throw "Row $rowNumber still contains the example ComputerName '$computer'. Replace it with a real Northwell hostname before mapping."
            }
        }

        $resolvedPrinters = @(
            foreach ($queue in $queues) {
                if ($PrinterResolver) {
                    & $PrinterResolver $queue $server
                }
                elseif ([string]::IsNullOrWhiteSpace($server)) {
                    ConvertTo-SasNorthwellPrinterUnc -Printer $queue
                }
                else {
                    ConvertTo-SasNorthwellPrinterUnc -Printer $queue -PrintServer $server
                }
            }
        )
        $resolvedPrinters = @($resolvedPrinters | Sort-Object -Unique)

        $groups.Add([pscustomobject][ordered]@{
            RowNumber = $rowNumber
            Computers = @($computers | Sort-Object -Unique)
            Printers = $resolvedPrinters
            PrintServer = if ([string]::IsNullOrWhiteSpace($server)) { $null } else { $server }
        })
    }

    return @($groups)
}

function New-SasNorthwellPrinterRunToken {
    [CmdletBinding()]
    param()

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $unique = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return "$timestamp-$unique"
}

function New-SasNorthwellPrinterTaskCreateArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$RemoteLauncherLocal
    )

    return @(
        '/Create','/F','/S',$Computer,'/RU','SYSTEM','/RL','HIGHEST',
        '/SC','ONSTART','/TN',$TaskName,'/TR',$RemoteLauncherLocal
    )
}

function Assert-SasNorthwellPrinterStatusProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Status,
        [Parameter(Mandatory)][string[]]$RequestedPrinters
    )

    $successProperty = $Status.PSObject.Properties['Success']
    $success = ($null -ne $successProperty -and [bool]$successProperty.Value)
    if (-not $success) {
        $errorProperty = $Status.PSObject.Properties['Error']
        if ($null -ne $errorProperty -and -not [string]::IsNullOrWhiteSpace([string]$errorProperty.Value)) {
            throw [string]$errorProperty.Value
        }

        $missingProperty = $Status.PSObject.Properties['Missing']
        $missing = if ($null -ne $missingProperty) { @($missingProperty.Value) } else { @() }
        if ($missing.Count -gt 0) {
            throw ('Missing machine-wide queue(s): ' + ($missing -join ', '))
        }
        throw 'Agent returned Success=false without a more specific error.'
    }

    $identityProperty = $Status.PSObject.Properties['Identity']
    $identity = if ($null -ne $identityProperty) { [string]$identityProperty.Value } else { '' }
    if ($identity -notmatch 'SYSTEM$') {
        throw "Remote worker did not run as SYSTEM (identity: $identity)."
    }

    $machineWideProperty = $Status.PSObject.Properties['MachineWideUNC']
    $machineWide = if ($null -ne $machineWideProperty) { @($machineWideProperty.Value) } else { @() }
    $verified = @(
        $machineWide |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $missingControllerProof = @(
        $RequestedPrinters |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Where-Object { $verified -notcontains $_ }
    )
    if ($missingControllerProof.Count -gt 0) {
        throw "Status.json did not prove requested machine-wide connection(s): $($missingControllerProof -join ', ')"
    }

    return [pscustomobject]@{
        Identity = $identity
        VerifiedMachineWide = $verified
    }
}

Export-ModuleMember -Function @(
    'Test-SasIpLiteral',
    'Resolve-SasNorthwellTargetComputer',
    'Resolve-SasPrinterQueueFromDirectory',
    'ConvertTo-SasNorthwellPrinterUnc',
    'Split-SasNorthwellPrinterBatchField',
    'ConvertTo-SasNorthwellPrinterBatchGroups',
    'New-SasNorthwellPrinterRunToken',
    'New-SasNorthwellPrinterTaskCreateArguments',
    'Assert-SasNorthwellPrinterStatusProof'
)
