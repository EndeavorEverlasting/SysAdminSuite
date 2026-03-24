#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline unit tests for Utilities\ scripts.
    All tests run without network access, AD, or real printers.
    Safe to run on any machine -- no side effects.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'Utilities\Test-Network.ps1')
    . (Join-Path $repoRoot 'Utilities\Map-Printer.ps1')
    . (Join-Path $repoRoot 'Utilities\Invoke-FileShare.ps1')
    . (Join-Path $repoRoot 'Utilities\Invoke-UndoRedo.ps1')
    . (Join-Path $repoRoot 'Utilities\Invoke-RunControl.ps1')
}

Describe 'Test-Network' {
    Context 'Parameter contract' {
        It 'Has a ComputerName parameter (not $Host)' {
            $cmd = Get-Command Test-Network
            $cmd.Parameters.Keys | Should -Contain 'ComputerName'
            $cmd.Parameters.Keys | Should -Not -Contain 'Host'
        }

        It 'Accepts multiple targets via array' {
            $cmd = Get-Command Test-Network
            $cmd.Parameters['ComputerName'].ParameterType | Should -Be ([string[]])
        }

        It 'Returns one result object per target' {
            # Mock Test-Connection so no real network call is made
            Mock Test-Connection { $true }

            $results = Test-Network -ComputerName 'fake-host-1','fake-host-2'
            $results.Count | Should -Be 2
            $results[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $results[0].PSObject.Properties.Name | Should -Contain 'Reachable'
        }
    }

    Context 'Offline safety' {
        It 'Does not throw when host is unreachable' {
            Mock Test-Connection { $false }
            { Test-Network -ComputerName '192.0.2.1' } | Should -Not -Throw
        }

        It 'Returns Reachable=$false for unreachable host' {
            Mock Test-Connection { $false }
            $r = Test-Network -ComputerName '192.0.2.1'
            $r.Reachable | Should -Be $false
        }
    }
}

Describe 'Map-Printer' {
    Context 'WhatIf / dry-run support' {
        It 'Supports ShouldProcess (-WhatIf)' {
            $cmd = Get-Command Map-Printer
            $cmd.Parameters.Keys | Should -Contain 'WhatIf'
        }

        It 'Does NOT call Add-Printer when -WhatIf is set' {
            Mock Add-Printer { throw 'Should not be called' }
            { Map-Printer -PrinterPath '\\FAKE\Queue' -WhatIf } | Should -Not -Throw
            Should -Invoke Add-Printer -Times 0
        }
    }

    Context 'Parameter validation' {
        It 'Requires PrinterPath' {
            $cmd = Get-Command Map-Printer
            $cmd.Parameters['PrinterPath'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }
    }
}

Describe 'Invoke-FileShare' {
    Context 'Error handling' {
        It 'Throws a descriptive error when share is unreachable' {
            Mock Test-Path { $false }
            { Invoke-FileShare -SharePath '\\FAKE\C$' } | Should -Throw -ExpectedMessage '*Cannot access share*'
        }

        It 'Calls Get-ChildItem when share is reachable' {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @([pscustomobject]@{ Name='file.txt' }) }
            $result = Invoke-FileShare -SharePath '\\FAKE\C$'
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke Get-ChildItem -Times 1
        }
    }
}

Describe 'Invoke-UndoRedo' {
    Context 'Session and action records' {
        It 'Creates a session with undo/redo/history stacks' {
            $session = New-UndoRedoSession
            $session.PSObject.Properties.Name | Should -Contain 'UndoStack'
            $session.PSObject.Properties.Name | Should -Contain 'RedoStack'
            $session.PSObject.Properties.Name | Should -Contain 'History'
        }

        It 'Supports WhatIf through ShouldProcess' {
            $cmd = Get-Command Invoke-UndoRedo
            $cmd.Parameters.Keys | Should -Contain 'WhatIf'
        }
    }

    Context 'Stack movement' {
        It 'Executes, undoes, and redoes an action record' {
            $script:steps = @()
            $session = New-UndoRedoSession
            $action = New-UndoRedoActionRecord -Name 'Demo action' -Target 'demo-target' -Do {
                param($ctx)
                $script:steps += "do:$($ctx.Target)"
            } -Undo {
                param($ctx)
                $script:steps += "undo:$($ctx.Target)"
            }

            Invoke-UndoRedo -Session $session -Action $action | Out-Null
            $session.UndoStack.Count | Should -Be 1
            $session.RedoStack.Count | Should -Be 0

            Invoke-UndoRedo -Session $session -Undo | Out-Null
            $session.UndoStack.Count | Should -Be 0
            $session.RedoStack.Count | Should -Be 1

            Invoke-UndoRedo -Session $session -Redo | Out-Null
            $session.UndoStack.Count | Should -Be 1
            $session.RedoStack.Count | Should -Be 0
            $script:steps | Should -Be @('do:demo-target','undo:demo-target','do:demo-target')
            $session.History.Count | Should -Be 3
        }
    }

    Context 'Helper constructors' {
        It 'Builds printer action metadata' {
            $action = New-PrinterUndoRedoAction -Operation Add -PrinterPath '\\PRINTSRV\Queue01'
            $action.Metadata.Kind | Should -Be 'Printer'
            $action.Metadata.PrinterPath | Should -Be '\\PRINTSRV\Queue01'
        }

        It 'Builds scheduled task action metadata' {
            $action = New-ScheduledTaskUndoRedoAction -Operation Create -TaskName 'SysAdminSuite_Demo' -TaskCommand 'powershell.exe -NoProfile -Command exit 0'
            $action.Metadata.Kind | Should -Be 'ScheduledTask'
            $action.Target | Should -Be 'SysAdminSuite_Demo'
        }

        It 'Exports a serializable undo/redo session summary' {
            $session = New-UndoRedoSession
            $action = New-UndoRedoActionRecord -Name 'Serializable action' -Target 'demo-target' -Do {
                param($ctx)
            } -Undo {
                param($ctx)
            } -Metadata @{ Kind = 'Demo' }

            Invoke-UndoRedo -Session $session -Action $action | Out-Null
            $path = Join-Path $TestDrive 'UndoRedo.json'
            $summary = Export-UndoRedoSessionSummary -Session $session -Path $path

            $path | Should -Exist
            $summary.UndoCount | Should -Be 1
            $summary.UndoStack[0].Target | Should -Be 'demo-target'
        }

        It 'Imports a serialized undo/redo session for GUI replay' {
            $session = New-UndoRedoSession
            $action = New-UndoRedoActionRecord -Name 'Serializable action' -Target 'demo-target' -Do {
                param($ctx)
            } -Undo {
                param($ctx)
            } -Metadata @{ Kind = 'Demo' }

            Invoke-UndoRedo -Session $session -Action $action | Out-Null
            $path = Join-Path $TestDrive 'ImportedUndoRedo.json'
            Export-UndoRedoSessionSummary -Session $session -Path $path | Out-Null

            $imported = Import-UndoRedoSession -Path $path
            $imported.UndoStack.Count | Should -Be 1
            $imported.UndoStack[0].Target | Should -Be 'demo-target'
            $imported.ImportedFromPath | Should -Be $path
        }

        It 'Replays undo and redo on imported sessions when the action type is supported' {
            $script:steps = @()
            $session = New-UndoRedoSession
            $action = New-UndoRedoActionRecord -Name 'Replayable action' -Target 'replay-target' -Do {
                param($ctx)
                $script:steps += 'do'
            } -Undo {
                param($ctx)
                $script:steps += 'undo'
            } -Metadata @{ Kind = 'Demo' }

            Invoke-UndoRedo -Session $session -Action $action | Out-Null
            $summary = Get-UndoRedoSessionSummary -Session $session
            $summary.UndoStack[0].Metadata = @{ Kind = 'Unknown' }

            $imported = Import-UndoRedoSession -SummaryObject $summary
            { Replay-UndoRedoAction -Session $imported -Operation Undo } | Should -Throw 'Replay is not supported*'
        }

        It 'Replays supported imported printer actions' {
            Mock Add-Printer {}
            Mock Remove-Printer {}
            Mock Get-Printer { $null }

            $session = New-UndoRedoSession
            $action = New-PrinterUndoRedoAction -Operation Add -PrinterPath '\\PRINTSRV\Queue01'

            Invoke-UndoRedo -Session $session -Action $action | Out-Null
            $summary = Get-UndoRedoSessionSummary -Session $session
            $imported = Import-UndoRedoSession -SummaryObject $summary

            Replay-UndoRedoAction -Session $imported -Operation Undo | Out-Null
            Replay-UndoRedoAction -Session $imported -Operation Redo | Out-Null

            Should -Invoke Remove-Printer -Times 1 -Exactly
            Should -Invoke Add-Printer -Times 2 -Exactly
        }
    }
}

Describe 'Invoke-RunControl' {
    Context 'Stop signal handling' {
        It 'Creates and reads a JSON stop signal' {
            $path = Join-Path $TestDrive 'Stop.json'

            $created = Request-RunStop -Path $path -Reason 'GUI stop button' -RequestedBy 'Tester'
            $readBack = Test-RunStopRequested -Path $path

            $path | Should -Exist
            $created.Reason | Should -Be 'GUI stop button'
            $readBack.Reason | Should -Be 'GUI stop button'
            $readBack.RequestedBy | Should -Be 'Tester'
        }

        It 'Treats a plain-text stop file as a valid stop request' {
            $path = Join-Path $TestDrive 'Stop.txt'
            Set-Content -LiteralPath $path -Value 'stop now' -Encoding UTF8

            $signal = Test-RunStopRequested -Path $path

            $signal | Should -Not -BeNullOrEmpty
            $signal.Reason | Should -Be 'stop now'
        }
    }

    Context 'Status snapshot handling' {
        It 'Exports and imports a status snapshot for GUI polling' {
            $path = Join-Path $TestDrive 'status.json'

            Export-RunStatusSnapshot -Path $path -State 'Stopping' -Stage 'AddQueue' -Message 'Partial artifacts emitted.' -Data @{ Host = 'WKS001'; Percent = 50 } | Out-Null
            $snapshot = Import-RunStatusSnapshot -Path $path

            $path | Should -Exist
            $snapshot.State | Should -Be 'Stopping'
            $snapshot.Stage | Should -Be 'AddQueue'
            $snapshot.Message | Should -Be 'Partial artifacts emitted.'
            $snapshot.Data.Host | Should -Be 'WKS001'
            $snapshot.Data.Percent | Should -Be 50
        }
    }
}

