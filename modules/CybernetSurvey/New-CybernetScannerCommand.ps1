#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CybernetPortProfile {
    param([string]$ProfilePath)

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        throw "Port profile not found: $ProfilePath"
    }

    $json = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    $portProfile = $json.profiles.CybernetWindowsEndpoint
    if (-not $portProfile) {
        throw 'CybernetWindowsEndpoint profile missing from port profile JSON'
    }

    return $portProfile
}

function New-CybernetNaabuCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [object]$PortProfile
    )

    $ports = ($PortProfile.ports | ForEach-Object { [string]$_ }) -join ','

    # CDN exclusion (-ec) mirrors Config/cybernet-naabu-profiles.json windows_selected doctrine:
    # it caps CDN/cloud-edge hosts to avoid wasteful probing. Record-only; never executed here.
    $excludeCdn = $false
    if ($PortProfile.PSObject.Properties.Name -contains 'excludeCdn') {
        $excludeCdn = [bool]$PortProfile.excludeCdn
    }
    $ecFlag = if ($excludeCdn) { ' -ec' } else { '' }

    $summaryFile = "$OutputFile.summary.json"
    $command = "bash survey/sas-run-packet-probe.sh --site cybernet --list $TargetFile --out $OutputFile --summary $summaryFile"
    $auditCommand = "naabu -list $TargetFile -p $ports -rate $($PortProfile.defaultRate) -c $($PortProfile.defaultConcurrency) -retries $($PortProfile.retries) -timeout $($PortProfile.timeoutMs)$ecFlag -json -silent -duc -o $OutputFile"

    return [pscustomobject]@{
        Scanner      = 'PacketProbe'
        Command      = $command
        AuditCommand = $auditCommand
        TargetFile   = $TargetFile
        OutputFile   = $OutputFile
    }
}

function New-CybernetNmapHostDiscoveryCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    $command = "nmap -sn -iL $TargetFile -oX $OutputFile"

    return [pscustomobject]@{
        Scanner    = 'Nmap'
        Command    = $command
        TargetFile = $TargetFile
        OutputFile = $OutputFile
    }
}

function New-CybernetNmapSelectedPortCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [object]$PortProfile
    )

    $ports = ($PortProfile.ports | ForEach-Object { [string]$_ }) -join ','
    $command = "nmap -p $ports --open -iL $TargetFile -oX $OutputFile"

    return [pscustomobject]@{
        Scanner    = 'Nmap'
        Command    = $command
        TargetFile = $TargetFile
        OutputFile = $OutputFile
    }
}

function New-CybernetScannerCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFile,

        [Parameter(Mandatory = $true)]
        [string]$SurveyOutDir,

        [string]$PortProfilePath
    )

    if (-not $PortProfilePath) {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $PortProfilePath = Join-Path $repoRoot 'Config/cybernet-port-profile.json'
    }

    $portProfile = Get-CybernetPortProfile -ProfilePath $PortProfilePath

    $naabuOut = Join-Path $SurveyOutDir 'CybernetSurvey_Naabu.jsonl'
    $nmapSnOut = Join-Path $SurveyOutDir 'CybernetSurvey_NmapHostDiscovery.xml'
    $nmapPortOut = Join-Path $SurveyOutDir 'CybernetSurvey_NmapPorts.xml'

    return @(
        (New-CybernetNaabuCommand -TargetFile $TargetFile -OutputFile $naabuOut -PortProfile $portProfile)
        (New-CybernetNmapHostDiscoveryCommand -TargetFile $TargetFile -OutputFile $nmapSnOut)
        (New-CybernetNmapSelectedPortCommand -TargetFile $TargetFile -OutputFile $nmapPortOut -PortProfile $portProfile)
    )
}
