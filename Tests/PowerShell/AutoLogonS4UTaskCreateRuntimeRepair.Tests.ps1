#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$repairScript = Join-Path $repoRoot 'scripts\Repair-SasBoundedNativeS4UCreateRuntime.ps1'
if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) {
    throw "Missing S4U create-timeout repair script: $repairScript"
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-OldBoundedNativeFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('crlf','lf')][string]$LineEnding
    )
    $text = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
function Invoke-SasBoundedPowerShell {
    param([string]$ScriptText,[int]$TimeoutSeconds = 30)
    throw 'fixture bounded child not configured'
}
function Invoke-SasBoundedNative {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )
    $run = Invoke-SasBoundedPowerShell -ScriptText 'old' -TimeoutSeconds $TimeoutSeconds
    [pscustomobject]@{
        file_path=$FilePath; arguments=@($Arguments); process_id=$run.process_id; exit_code=$run.exit_code
        timed_out=$run.timed_out; timeout_seconds=$run.timeout_seconds; child_tree_termination_attempted=$run.child_tree_termination_attempted
        child_tree_terminated=$run.child_tree_terminated; output=$run.output; error=$run.error; started_utc=$run.started_utc; completed_utc=$run.completed_utc
    }
}
function Test-SasBoundedPath { param([string]$Path) return $false }
Export-ModuleMember -Function Invoke-SasBoundedNative,Invoke-SasBoundedPowerShell,Test-SasBoundedPath
'@
    $text = $text.Replace("`r`n","`n").Replace("`r","`n")
    if ($LineEnding -eq 'crlf') { $text = $text.Replace("`n","`r`n") }
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function New-FixtureNativeResult {
    param([bool]$TimedOut,[int]$ExitCode,[int]$TimeoutSeconds,[string]$Output='',[string]$Error='')
    [pscustomobject][ordered]@{
        process_id=7331; exit_code=$ExitCode; timed_out=$TimedOut; timeout_seconds=$TimeoutSeconds
        child_tree_termination_attempted=$TimedOut; child_tree_terminated=$TimedOut
        output=$Output; error=$Error
        started_utc='2026-08-18T20:00:00.0000000Z'; completed_utc='2026-08-18T20:01:00.0000000Z'
    }
}

function Configure-FixtureModule {
    param([Parameter(Mandatory = $true)]$Module,[Parameter(Mandatory = $true)][object[]]$Results)
    & $Module {
        param($FixtureResults)
        $script:SasRepairFixtureQueue = New-Object System.Collections.Queue
        $script:SasRepairObservedTimeouts = New-Object System.Collections.Generic.List[int]
        foreach ($item in @($FixtureResults)) { $script:SasRepairFixtureQueue.Enqueue($item) }
        function Invoke-SasBoundedPowerShell {
            param([string]$ScriptText,[int]$TimeoutSeconds = 30)
            $script:SasRepairObservedTimeouts.Add([int]$TimeoutSeconds)
            if ($script:SasRepairFixtureQueue.Count -eq 0) { throw 'repair fixture queue exhausted' }
            return $script:SasRepairFixtureQueue.Dequeue()
        }
    } $Results
}

foreach ($ending in @('crlf','lf')) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('sas-s4u-create-repair-' + $ending + '-' + [guid]::NewGuid().ToString('N'))
    $scripts = Join-Path $root 'scripts'
    $evidenceOne = Join-Path $root 'evidence-one'
    $evidenceTwo = Join-Path $root 'evidence-two'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null

    try {
        $fixture = Join-Path $scripts 'SasBoundedNative.psm1'
        New-OldBoundedNativeFixture -Path $fixture -LineEnding $ending

        $first = & $repairScript -RuntimeRoot $root -EvidenceRoot $evidenceOne -ConfirmRepair -PassThru
        Assert-True ([string]$first.classification -eq 'AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_APPLIED') "$ending repair was not applied."
        Assert-True ([bool]$first.changed) "$ending repair did not report a change."
        Assert-True ([bool]$first.powershell_parse_passed) "$ending repaired module did not parse."
        Assert-True ([bool]$first.semantic_verification) "$ending repaired module lost semantic verification."
        Assert-True ([int]$first.s4u_create_minimum_timeout_seconds -eq 60) "$ending repair did not record the 60-second create floor."
        Assert-True ([bool]$first.exact_query_reconciliation) "$ending repair did not record exact-query reconciliation."
        Assert-True (-not [bool]$first.git_performed -and -not [bool]$first.network_activity_performed -and -not [bool]$first.target_contact_performed -and -not [bool]$first.target_mutation_performed) "$ending repair exceeded its local-only boundary."
        Assert-True (Test-Path -LiteralPath (Join-Path $evidenceOne 'SasBoundedNative.before.psm1') -PathType Leaf) "$ending repair backup is missing."
        Assert-True (Test-Path -LiteralPath (Join-Path $evidenceOne 's4u-create-timeout-runtime-repair-result.json') -PathType Leaf) "$ending repair evidence is missing."

        $repaired = [IO.File]::ReadAllText($fixture)
        foreach ($marker in @(
            "`$timeoutPolicy = 's4u_task_create_minimum_60'",
            'reconciled_after_timeout = $true',
            "'^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$'",
            "'/Query','/S',`$s4uCreateTarget,'/TN',`$s4uCreateTaskName"
        )) {
            Assert-True ($repaired.Contains($marker)) "$ending repaired module missing marker: $marker"
        }

        $module = Import-Module $fixture -Force -PassThru
        Configure-FixtureModule -Module $module -Results @(
            (New-FixtureNativeResult -TimedOut:$true -ExitCode -1 -TimeoutSeconds 60 -Error 'Timed out after 60 seconds.'),
            (New-FixtureNativeResult -TimedOut:$false -ExitCode 0 -TimeoutSeconds 30 -Output 'exact task exists')
        )
        $task = 'SysAdminSuite-AutoLogonS4UProbe-0123456789abcdef0123456789abcdef'
        $run = Invoke-SasBoundedNative -FilePath 'C:\Windows\System32\schtasks.exe' -Arguments @(
            '/Create','/S','fixture.example.invalid','/TN',$task,'/TR','powershell.exe -File C:\probe.ps1','/SC','ONCE','/ST','23:59','/F'
        ) -TimeoutSeconds 30
        Assert-True ([bool]$run.reconciled_after_timeout) "$ending repaired module did not reconcile the exact timed-out task."
        Assert-True (-not [bool]$run.timed_out -and [int]$run.exit_code -eq 0) "$ending repaired module did not return reconciled success."
        $observed = @(& $module { @($script:SasRepairObservedTimeouts) })
        Assert-True ($observed.Count -eq 2 -and [int]$observed[0] -eq 60 -and [int]$observed[1] -eq 30) "$ending repaired module did not preserve the 60/30 bounded sequence."
        Remove-Module $module -Force

        $second = & $repairScript -RuntimeRoot $root -EvidenceRoot $evidenceTwo -ConfirmRepair -PassThru
        Assert-True ([string]$second.classification -eq 'AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_ALREADY_PRESENT') "$ending second repair was not idempotent."
        Assert-True (-not [bool]$second.changed) "$ending second repair reported an unexpected change."
        Assert-True ([bool]$second.semantic_verification) "$ending second repair lost semantic verification."

        Write-Host "PASS: $ending S4U create-timeout runtime repair, exact reconciliation, and idempotence"
    }
    finally {
        Get-Module | Where-Object { $_.Path -eq (Join-Path $scripts 'SasBoundedNative.psm1') } | Remove-Module -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $root -PathType Container) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host 'PASS: protected S4U task create runtime repair contracts'