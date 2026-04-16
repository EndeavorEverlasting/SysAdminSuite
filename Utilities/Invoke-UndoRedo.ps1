<#
.SYNOPSIS
    Foundation for reversible admin actions with in-memory undo/redo stacks.

.DESCRIPTION
    Stores forward and reverse scriptblocks in an action record, tracks stack
    movement, and captures optional probe snapshots before/after execution.
    Intended as a thin wrapper for future GUI workflows; persistence can be
    added later without changing the action shape.
#>

function New-UndoRedoSession {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName = 'SysAdminSuite.UndoRedo.Session'
        UndoStack  = [System.Collections.Generic.List[object]]::new()
        RedoStack  = [System.Collections.Generic.List[object]]::new()
        History    = [System.Collections.Generic.List[object]]::new()
    }
}

function New-UndoRedoActionRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,
        [Parameter(Mandatory)][scriptblock]$Do,
        [Parameter(Mandatory)][scriptblock]$Undo,
        [scriptblock]$Redo,
        [scriptblock]$Probe,
        [hashtable]$Metadata = @{}
    )

    [pscustomobject]@{
        PSTypeName     = 'SysAdminSuite.UndoRedo.ActionRecord'
        Id             = [guid]::NewGuid().Guid
        Name           = $Name
        Target         = $Target
        Status         = 'Pending'
        Metadata       = $Metadata
        CreatedAt      = Get-Date
        ExecutedAt     = $null
        UndoneAt       = $null
        RedoneAt       = $null
        BeforeState    = $null
        AfterState     = $null
        LastKnownState = $null
        Do             = $Do
        Undo           = $Undo
        Redo           = if ($Redo) { $Redo } else { $Do }
        Probe          = $Probe
    }
}

function Add-UndoRedoHistoryEntry {
    param([psobject]$Session,[string]$Event,[psobject]$Action)

    $Session.History.Add([pscustomobject]@{
        Timestamp = Get-Date
        Event     = $Event
        ActionId  = $Action.Id
        Name      = $Action.Name
        Target    = $Action.Target
        Status    = $Action.Status
    })
}

function Get-UndoRedoActionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Action
    )

    [pscustomobject]@{
        Id             = $Action.Id
        Name           = $Action.Name
        Target         = $Action.Target
        Status         = $Action.Status
        Metadata       = $Action.Metadata
        CreatedAt      = $Action.CreatedAt
        ExecutedAt     = $Action.ExecutedAt
        UndoneAt       = $Action.UndoneAt
        RedoneAt       = $Action.RedoneAt
        BeforeState    = $Action.BeforeState
        AfterState     = $Action.AfterState
        LastKnownState = $Action.LastKnownState
    }
}

function Get-UndoRedoSessionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Session
    )

    foreach ($required in 'UndoStack','RedoStack','History') {
        if (-not $Session.PSObject.Properties[$required]) {
            throw "Session is missing property '$required'."
        }
    }

    [pscustomobject]@{
        GeneratedAt = Get-Date
        UndoCount   = $Session.UndoStack.Count
        RedoCount   = $Session.RedoStack.Count
        HistoryCount= $Session.History.Count
        UndoStack   = @($Session.UndoStack | ForEach-Object { Get-UndoRedoActionSummary -Action $_ })
        RedoStack   = @($Session.RedoStack | ForEach-Object { Get-UndoRedoActionSummary -Action $_ })
        History     = @($Session.History)
    }
}

function Export-UndoRedoSessionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Session,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $summary = Get-UndoRedoSessionSummary -Session $Session
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $summary
}

function ConvertTo-UndoRedoHashtable {
    param($InputObject)

    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }

    $table = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $value = $prop.Value
        if ($null -eq $value) {
            $table[$prop.Name] = $null
        } elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            $items = @()
            foreach ($item in $value) {
                if ($item -is [pscustomobject] -or $item -is [hashtable]) {
                    $items += ,(ConvertTo-UndoRedoHashtable -InputObject $item)
                } else {
                    $items += ,$item
                }
            }
            $table[$prop.Name] = $items
        } elseif ($value -is [pscustomobject]) {
            $table[$prop.Name] = ConvertTo-UndoRedoHashtable -InputObject $value
        } else {
            $table[$prop.Name] = $value
        }
    }
    return $table
}

function New-MachineWidePrinterUndoRedoAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Add','Remove')][string]$Operation,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PrinterPath,
        [string]$Source = 'ImportedSession'
    )

    $normalizedPrinter = $PrinterPath.Trim().ToLower()
    $probe = {
        param($ctx)
        $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
        $present = $false
        if (Test-Path -LiteralPath $key) {
            $targets = Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $item = Get-ItemProperty $_.PSPath
                    if ($item.Server -and $item.Printer) { "\\$($item.Server)\$($item.Printer)".ToLower() }
                } catch { }
            }
            $present = @($targets) -contains $ctx.Target
        }
        [pscustomobject]@{ Target = $ctx.Target; Present = $present }
    }

    if ($Operation -eq 'Add') {
        $do = { param($ctx) Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/ga','/n',$ctx.Target) -NoNewWindow -Wait }
        $undo = { param($ctx) Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/gd','/n',$ctx.Target) -NoNewWindow -Wait }
    } else {
        $do = { param($ctx) Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/gd','/n',$ctx.Target) -NoNewWindow -Wait }
        $undo = { param($ctx) Start-Process rundll32.exe -ArgumentList @('printui.dll,PrintUIEntry','/ga','/n',$ctx.Target) -NoNewWindow -Wait }
    }

    New-UndoRedoActionRecord -Name "$Operation machine-wide printer" -Target $normalizedPrinter -Do $do -Undo $undo -Probe $probe -Metadata @{
        Kind       = 'Printer'
        Mode       = 'MachineWide'
        Operation  = $Operation
        PrinterPath= $normalizedPrinter
        Source     = $Source
    }
}

function New-PrinterUndoRedoAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Add','Remove')][string]$Operation,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PrinterPath
    )

    $probe = { param($ctx) Get-Printer -Name $ctx.Target -ErrorAction SilentlyContinue | Select-Object -First 1 Name,DriverName,PortName }
    if ($Operation -eq 'Add') {
        $do = { param($ctx) Add-Printer -ConnectionName $ctx.Target -ErrorAction Stop | Out-Null }
        $undo = { param($ctx) Remove-Printer -Name $ctx.Target -ErrorAction Stop }
    } else {
        $do = { param($ctx) Remove-Printer -Name $ctx.Target -ErrorAction Stop }
        $undo = { param($ctx) Add-Printer -ConnectionName $ctx.Target -ErrorAction Stop | Out-Null }
    }

    New-UndoRedoActionRecord -Name "$Operation printer" -Target $PrinterPath -Do $do -Undo $undo -Probe $probe -Metadata @{
        Kind       = 'Printer'
        Operation  = $Operation
        PrinterPath= $PrinterPath
    }
}

function New-ScheduledTaskUndoRedoAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Create','Delete')][string]$Operation,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TaskName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TaskCommand,
        [string]$ComputerName = $env:COMPUTERNAME,
        [datetime]$StartTime = (Get-Date).AddMinutes(1),
        [string]$RunAs = 'SYSTEM'
    )

    $probe = {
        param($ctx)
        $m = $ctx.Metadata
        $out = & schtasks.exe /Query /S $m.ComputerName /TN $ctx.Target /FO LIST 2>$null
        if ($LASTEXITCODE -eq 0) { $out -join [Environment]::NewLine } else { $null }
    }
    $create = {
        param($ctx)
        $m = $ctx.Metadata
        & schtasks.exe /Create /S $m.ComputerName /RU $m.RunAs /SC ONCE /SD $m.StartDate /ST $m.StartTime /TN $ctx.Target /TR $m.TaskCommand /RL HIGHEST /F | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "schtasks /Create failed for $($ctx.Target) on $($m.ComputerName)." }
    }
    $delete = {
        param($ctx)
        $m = $ctx.Metadata
        & schtasks.exe /Delete /S $m.ComputerName /TN $ctx.Target /F | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "schtasks /Delete failed for $($ctx.Target) on $($m.ComputerName)." }
    }

    $metadata = @{
        Kind        = 'ScheduledTask'
        Operation   = $Operation
        ComputerName= $ComputerName
        TaskCommand = $TaskCommand
        RunAs       = $RunAs
        StartDate   = $StartTime.ToString('yyyy-MM-dd')
        StartTime   = $StartTime.ToString('HH:mm')
    }

    if ($Operation -eq 'Create') {
        New-UndoRedoActionRecord -Name 'Create scheduled task' -Target $TaskName -Do $create -Undo $delete -Probe $probe -Metadata $metadata
    } else {
        New-UndoRedoActionRecord -Name 'Delete scheduled task' -Target $TaskName -Do $delete -Undo $create -Probe $probe -Metadata $metadata
    }
}

function Restore-UndoRedoActionRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$ActionSummary
    )

    $metadata = ConvertTo-UndoRedoHashtable -InputObject $ActionSummary.Metadata
    $replaySupported = $true

    $printerMode = if ($metadata.ContainsKey('Mode')) { $metadata['Mode'] } else { $null }

    if ($metadata.Kind -eq 'Printer' -and $printerMode -eq 'MachineWide') {
        $source = if ($metadata.ContainsKey('Source') -and $metadata.Source) { $metadata.Source } else { 'ImportedSession' }
        $action = New-MachineWidePrinterUndoRedoAction -Operation $metadata.Operation -PrinterPath $ActionSummary.Target -Source $source
    } elseif ($metadata.Kind -eq 'Printer') {
        $printerPath = if ($metadata.PrinterPath) { $metadata.PrinterPath } else { $ActionSummary.Target }
        $action = New-PrinterUndoRedoAction -Operation $metadata.Operation -PrinterPath $printerPath
    } elseif ($metadata.Kind -eq 'ScheduledTask') {
        $taskName = if ($metadata.TaskName) { $metadata.TaskName } else { $ActionSummary.Target }
        $startTime = (Get-Date).AddMinutes(1)
        if ($metadata.StartDate -and $metadata.StartTime) {
            try {
                $startTime = [datetime]::ParseExact(
                    ('{0} {1}' -f $metadata.StartDate, $metadata.StartTime),
                    'yyyy-MM-dd HH:mm',
                    [System.Globalization.CultureInfo]::InvariantCulture
                )
            } catch { }
        }
        $action = New-ScheduledTaskUndoRedoAction -Operation $metadata.Operation -TaskName $taskName -TaskCommand $metadata.TaskCommand -ComputerName $metadata.ComputerName -StartTime $startTime -RunAs ($(if ($metadata.RunAs) { $metadata.RunAs } else { 'SYSTEM' }))
    } else {
        $replaySupported = $false
        $message = "Replay is not supported for imported action '$($ActionSummary.Name)' targeting '$($ActionSummary.Target)'."
        $action = New-UndoRedoActionRecord -Name $ActionSummary.Name -Target $ActionSummary.Target -Do { param($ctx) throw $ctx.Metadata.ReplayError } -Undo { param($ctx) throw $ctx.Metadata.ReplayError } -Redo { param($ctx) throw $ctx.Metadata.ReplayError } -Metadata ($metadata + @{ ReplayError = $message })
    }

    $action.Id = $ActionSummary.Id
    $action.Status = $ActionSummary.Status
    $action.CreatedAt = $ActionSummary.CreatedAt
    $action.ExecutedAt = $ActionSummary.ExecutedAt
    $action.UndoneAt = $ActionSummary.UndoneAt
    $action.RedoneAt = $ActionSummary.RedoneAt
    $action.BeforeState = $ActionSummary.BeforeState
    $action.AfterState = $ActionSummary.AfterState
    $action.LastKnownState = $ActionSummary.LastKnownState
    $action.Metadata = $metadata
    $action | Add-Member -NotePropertyName ReplaySupported -NotePropertyValue $replaySupported -Force
    return $action
}

function Import-UndoRedoSession {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(ParameterSetName='Path', Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(ParameterSetName='Object', Mandatory)][psobject]$SummaryObject
    )

    $summary = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } else {
        $SummaryObject
    }

    $session = New-UndoRedoSession
    foreach ($entry in @($summary.UndoStack)) {
        $session.UndoStack.Add((Restore-UndoRedoActionRecord -ActionSummary $entry))
    }
    foreach ($entry in @($summary.RedoStack)) {
        $session.RedoStack.Add((Restore-UndoRedoActionRecord -ActionSummary $entry))
    }
    foreach ($entry in @($summary.History)) {
        $session.History.Add([pscustomobject]@{
            Timestamp = $entry.Timestamp
            Event     = $entry.Event
            ActionId  = $entry.ActionId
            Name      = $entry.Name
            Target    = $entry.Target
            Status    = $entry.Status
        })
    }

    $session | Add-Member -NotePropertyName ImportedFromPath -NotePropertyValue ($(if ($Path) { $Path } else { $null })) -Force
    return $session
}

function Replay-UndoRedoAction {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Session,
        [ValidateSet('Undo','Redo')][string]$Operation,
        [string]$ActionId
    )

    if ($Operation -eq 'Undo') {
        if ($Session.UndoStack.Count -eq 0) { throw 'Undo stack is empty.' }
        $top = $Session.UndoStack[$Session.UndoStack.Count - 1]
        if ($ActionId -and $top.Id -ne $ActionId) {
            throw "Only the top undo entry can be replayed safely. Requested=$ActionId Top=$($top.Id)"
        }
        if (-not $top.ReplaySupported) {
            throw "Replay is not supported for action '$($top.Name)'."
        }
        return Invoke-UndoRedo -Session $Session -Undo -WhatIf:$WhatIfPreference
    }

    if ($Session.RedoStack.Count -eq 0) { throw 'Redo stack is empty.' }
    $top = $Session.RedoStack[$Session.RedoStack.Count - 1]
    if ($ActionId -and $top.Id -ne $ActionId) {
        throw "Only the top redo entry can be replayed safely. Requested=$ActionId Top=$($top.Id)"
    }
    if (-not $top.ReplaySupported) {
        throw "Replay is not supported for action '$($top.Name)'."
    }
    Invoke-UndoRedo -Session $Session -Redo -WhatIf:$WhatIfPreference
}

function Invoke-UndoRedo {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Session,
        [Parameter(ParameterSetName='Execute', Mandatory)][psobject]$Action,
        [Parameter(ParameterSetName='Undo', Mandatory)][switch]$Undo,
        [Parameter(ParameterSetName='Redo', Mandatory)][switch]$Redo
    )

    foreach ($required in 'UndoStack','RedoStack','History') {
        if (-not $Session.PSObject.Properties[$required]) { throw "Session is missing property '$required'." }
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Execute' {
            if ($PSCmdlet.ShouldProcess($Action.Target, "Execute $($Action.Name)")) {
                if ($Action.Probe) { $Action.BeforeState = & $Action.Probe $Action }
                & $Action.Do $Action
                if ($Action.Probe) {
                    $Action.AfterState = & $Action.Probe $Action
                    $Action.LastKnownState = $Action.AfterState
                }
                $Action.Status = 'Done'
                $Action.ExecutedAt = Get-Date
                $Session.UndoStack.Add($Action)
                $Session.RedoStack.Clear()
                Add-UndoRedoHistoryEntry -Session $Session -Event 'Execute' -Action $Action
                return $Action
            }
        }
        'Undo' {
            if ($Session.UndoStack.Count -eq 0) { throw 'Undo stack is empty.' }
            $index = $Session.UndoStack.Count - 1
            $entry = $Session.UndoStack[$index]
            if ($PSCmdlet.ShouldProcess($entry.Target, "Undo $($entry.Name)")) {
                & $entry.Undo $entry
                if ($entry.Probe) { $entry.LastKnownState = & $entry.Probe $entry }
                $entry.Status = 'Undone'
                $entry.UndoneAt = Get-Date
                $Session.UndoStack.RemoveAt($index)
                $Session.RedoStack.Add($entry)
                Add-UndoRedoHistoryEntry -Session $Session -Event 'Undo' -Action $entry
                return $entry
            }
        }
        'Redo' {
            if ($Session.RedoStack.Count -eq 0) { throw 'Redo stack is empty.' }
            $index = $Session.RedoStack.Count - 1
            $entry = $Session.RedoStack[$index]
            if ($PSCmdlet.ShouldProcess($entry.Target, "Redo $($entry.Name)")) {
                & $entry.Redo $entry
                if ($entry.Probe) { $entry.LastKnownState = & $entry.Probe $entry }
                $entry.Status = 'Done'
                $entry.RedoneAt = Get-Date
                $Session.RedoStack.RemoveAt($index)
                $Session.UndoStack.Add($entry)
                Add-UndoRedoHistoryEntry -Session $Session -Event 'Redo' -Action $entry
                return $entry
            }
        }
    }
}