#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'scripts\SasBoundedNative.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Missing bounded-native module: $modulePath"
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-FixtureNativeResult {
    param(
        [Parameter(Mandatory = $true)][bool]$TimedOut,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [string]$Output = '',
        [string]$Error = ''
    )
    [pscustomobject][ordered]@{
        process_id = 4242
        exit_code = $ExitCode
        timed_out = $TimedOut
        timeout_seconds = $TimeoutSeconds
        child_tree_termination_attempted = $TimedOut
        child_tree_terminated = $TimedOut
        output = $Output
        error = $Error
        started_utc = '2026-08-18T19:55:00.0000000Z'
        completed_utc = '2026-08-18T19:56:00.0000000Z'
    }
}

function Set-FixtureQueue {
    param(
        [Parameter(Mandatory = $true)]$Module,
        [Parameter(Mandatory = $true)][object[]]$Results
    )
    & $Module {
        param($FixtureResults)
        $script:SasBoundedNativeFixtureQueue = New-Object System.Collections.Queue
        $script:SasBoundedNativeObservedTimeouts = New-Object System.Collections.Generic.List[int]
        foreach ($item in @($FixtureResults)) {
            $script:SasBoundedNativeFixtureQueue.Enqueue($item)
        }
        $fixtureBody = {
            param(
                [Parameter(Mandatory = $true)][string]$ScriptText,
                [ValidateRange(1,300)][int]$TimeoutSeconds = 30
            )
            $script:SasBoundedNativeObservedTimeouts.Add([int]$TimeoutSeconds)
            if ($script:SasBoundedNativeFixtureQueue.Count -eq 0) {
                throw 'Fixture queue exhausted.'
            }
            return $script:SasBoundedNativeFixtureQueue.Dequeue()
        }
        Set-Item -Path Function:script:Invoke-SasBoundedPowerShell -Value $fixtureBody -Force
    } $Results
}

function Get-FixtureObservedTimeouts {
    param([Parameter(Mandatory = $true)]$Module)
    & $Module {
        [pscustomobject][ordered]@{
            count = [int]$script:SasBoundedNativeObservedTimeouts.Count
            values = @($script:SasBoundedNativeObservedTimeouts | ForEach-Object { [int]$_ })
        }
    }
}

$module = Import-Module $modulePath -Force -PassThru
$fakeSchtasks = 'C:\Windows\System32\schtasks.exe'
$target = 'sample001.example.invalid'
$probeTask = 'SysAdminSuite-AutoLogonS4UProbe-0123456789abcdef0123456789abcdef'
$installTask = 'SysAdminSuite-AutoLogonS4UInstall-fedcba9876543210fedcba9876543210'

# 1. Exact S4U task create gets a dedicated minimum 60-second bound.
Set-FixtureQueue -Module $module -Results @(
    (New-FixtureNativeResult -TimedOut:$false -ExitCode 0 -TimeoutSeconds 60 -Output 'SUCCESS')
)
$normal = Invoke-SasBoundedNative -FilePath $fakeSchtasks -Arguments @(
    '/Create','/S',$target,'/RU','EXAMPLE\operator','/NP','/SC','ONCE','/ST','23:59',
    '/TN',$probeTask,'/TR','powershell.exe -File C:\probe.ps1','/RL','HIGHEST','/F'
) -TimeoutSeconds 30
Assert-True (-not [bool]$normal.timed_out) 'Normal S4U create unexpectedly timed out.'
Assert-True ([int]$normal.timeout_seconds -eq 60) 'S4U create did not receive the 60-second effective bound.'
Assert-True ([int]$normal.requested_timeout_seconds -eq 30) 'S4U create lost the caller-requested timeout.'
Assert-True ([string]$normal.timeout_policy -eq 's4u_task_create_minimum_60') 'S4U create timeout policy was not recorded.'
Assert-True (-not [bool]$normal.reconciled_after_timeout) 'Normal S4U create was incorrectly marked reconciled.'
$normalObserved = Get-FixtureObservedTimeouts -Module $module
Assert-True ([int]$normalObserved.count -eq 1 -and [int]$normalObserved.values[0] -eq 60) 'Normal S4U create did not invoke the bounded child with 60 seconds.'

# 2. A controller timeout may be reconciled only by querying the exact unique task identity.
Set-FixtureQueue -Module $module -Results @(
    (New-FixtureNativeResult -TimedOut:$true -ExitCode -1 -TimeoutSeconds 60 -Error 'Timed out after 60 seconds.'),
    (New-FixtureNativeResult -TimedOut:$false -ExitCode 0 -TimeoutSeconds 30 -Output 'TaskName: exact S4U task')
)
$reconciled = Invoke-SasBoundedNative -FilePath $fakeSchtasks -Arguments @(
    '/Create','/S',$target,'/RU','EXAMPLE\operator','/NP','/SC','ONCE','/ST','23:59',
    '/TN',$installTask,'/TR','powershell.exe -File C:\install.ps1','/RL','HIGHEST','/F'
) -TimeoutSeconds 30
Assert-True (-not [bool]$reconciled.timed_out) 'Exact-task reconciliation did not convert the ambiguous controller timeout to success.'
Assert-True ([int]$reconciled.exit_code -eq 0) 'Reconciled S4U create did not return success.'
Assert-True ([bool]$reconciled.initial_timed_out) 'Reconciled S4U create lost the initial timeout fact.'
Assert-True ([bool]$reconciled.reconciled_after_timeout) 'Reconciled S4U create did not record reconciliation.'
Assert-True ($null -ne $reconciled.reconciliation) 'Reconciled S4U create did not preserve the exact query result.'
Assert-True ([string]$reconciled.reconciliation.arguments[0] -eq '/Query') 'Reconciliation did not use Task Scheduler query.'
Assert-True ([string]$reconciled.reconciliation.arguments[2] -eq $target) 'Reconciliation changed the target identity.'
Assert-True ([string]$reconciled.reconciliation.arguments[4] -eq $installTask) 'Reconciliation changed the exact task identity.'
$reconcileObserved = Get-FixtureObservedTimeouts -Module $module
Assert-True ([int]$reconcileObserved.count -eq 2) 'Reconciled create did not perform exactly one create and one query native call.'
Assert-True ([int]$reconcileObserved.values[0] -eq 60 -and [int]$reconcileObserved.values[1] -eq 30) 'Reconciliation bounds were not 60 seconds for create and 30 seconds for exact query.'

# 3. If exact task existence is not proven, the original timeout remains a hard failure signal.
Set-FixtureQueue -Module $module -Results @(
    (New-FixtureNativeResult -TimedOut:$true -ExitCode -1 -TimeoutSeconds 60 -Error 'Timed out after 60 seconds.'),
    (New-FixtureNativeResult -TimedOut:$false -ExitCode 1 -TimeoutSeconds 30 -Error 'ERROR: The system cannot find the file specified.')
)
$absent = Invoke-SasBoundedNative -FilePath $fakeSchtasks -Arguments @(
    '/Create','/S',$target,'/RU','EXAMPLE\operator','/NP','/SC','ONCE','/ST','23:59',
    '/TN',$probeTask,'/TR','powershell.exe -File C:\probe.ps1','/RL','HIGHEST','/F'
) -TimeoutSeconds 30
Assert-True ([bool]$absent.timed_out) 'Unproven S4U create was incorrectly converted to success.'
Assert-True ([int]$absent.exit_code -eq -1) 'Unproven S4U create lost the original timeout exit code.'
Assert-True (-not [bool]$absent.reconciled_after_timeout) 'Absent exact task was incorrectly marked reconciled.'
Assert-True ($null -ne $absent.reconciliation -and [int]$absent.reconciliation.exit_code -eq 1) 'Unproven S4U create did not preserve reconciliation evidence.'

# 4. The policy must not expand generic scheduler creates or S4U non-create operations.
Set-FixtureQueue -Module $module -Results @(
    (New-FixtureNativeResult -TimedOut:$false -ExitCode 0 -TimeoutSeconds 30 -Output 'SUCCESS')
)
$generic = Invoke-SasBoundedNative -FilePath $fakeSchtasks -Arguments @(
    '/Create','/S',$target,'/TN','UnrelatedTask','/TR','cmd.exe /c exit 0','/SC','ONCE','/ST','23:59','/F'
) -TimeoutSeconds 30
Assert-True ([int]$generic.timeout_seconds -eq 30) 'Generic scheduler create was incorrectly expanded to the S4U bound.'
Assert-True ([string]$generic.timeout_policy -eq 'requested') 'Generic scheduler create received the S4U timeout policy.'

Set-FixtureQueue -Module $module -Results @(
    (New-FixtureNativeResult -TimedOut:$false -ExitCode 0 -TimeoutSeconds 30 -Output 'SUCCESS')
)
$delete = Invoke-SasBoundedNative -FilePath $fakeSchtasks -Arguments @(
    '/Delete','/S',$target,'/TN',$probeTask,'/F'
) -TimeoutSeconds 30
Assert-True ([int]$delete.timeout_seconds -eq 30) 'S4U delete was incorrectly expanded to the create-only bound.'
Assert-True ([string]$delete.timeout_policy -eq 'requested') 'S4U delete received the create-only timeout policy.'

Write-Host 'PASS: bounded S4U task create timeout and exact-task reconciliation contracts'