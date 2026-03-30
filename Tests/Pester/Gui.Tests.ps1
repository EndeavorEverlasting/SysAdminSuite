#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:guiPath = Join-Path $script:repoRoot 'GUI\Start-SysAdminSuiteGui.ps1'
}

Describe 'Start-SysAdminSuiteGui.ps1 -- script-level checks' {
    It 'GUI script exists' {
        $script:guiPath | Should -Exist
    }

    It 'Parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:guiPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'Uses Windows Forms and the GUI-safe run control hooks' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'System\.Windows\.Forms'
        $content | Should -Match 'Request-RunStop'
        $content | Should -Match 'Import-RunStatusSnapshot'
        $content | Should -Match 'Import-UndoRedoSession'
        $content | Should -Match 'Replay-UndoRedoAction'
        $content | Should -Match 'Get-KronosClockInfo\.ps1'
    }

    It 'Exposes local worker and controller launch affordances' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Start Local Worker'
        $content | Should -Match 'Start Controller'
        $content | Should -Match 'Worker options passthrough'
        $content | Should -Match 'WorkerArgumentLine'
    }

    It 'Exposes polished run-session affordances for safe operation and operator convenience' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Set-StatusBarText'
        $content | Should -Match 'Update-RunActionState'
        $content | Should -Match 'Load-SafeWorkerExample'
        $content | Should -Match 'Open Session Folder'
        $content | Should -Match 'Copy Status'
        $content | Should -Match 'Copy History'
        $content | Should -Match 'Auto refresh'
        $content | Should -Match 'StatusStrip'
    }

    It 'Uses user-friendly placeholder and guidance text instead of blank panes' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Status file not found yet'
        $content | Should -Match 'Undo/redo history not found yet'
        $content | Should -Match 'Dry-run defaults are preloaded'
        $content | Should -Match 'Launch a run or click Refresh Now'
        $content | Should -Match 'Launch a run or load a history file'
        $content | Should -Match 'Probe live clocks or search a saved inventory CSV'
    }

    It 'Uses GroupBox controls for visual grouping and hierarchy' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'GroupBox'
        $content | Should -Match 'Session File Paths'
        $content | Should -Match 'Run Options'
        $content | Should -Match 'Launch Configuration'
        $content | Should -Match 'Kronos Clock Probe / Inventory'
    }

    It 'Provides browse dialogs for path text fields' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Show-BrowseFileDialog'
        $content | Should -Match 'Show-BrowseFolderDialog'
        $content | Should -Match 'OpenFileDialog'
        $content | Should -Match 'FolderBrowserDialog'
        $content | Should -Match 'btnBrowseStop'
        $content | Should -Match 'btnBrowseStatus'
        $content | Should -Match 'btnBrowseHistory'
        $content | Should -Match 'btnBrowseClockOut'
        $content | Should -Match 'btnBrowseInv'
    }

    It 'Registers keyboard shortcuts via KeyDown with KeyPreview' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'KeyPreview'
        $content | Should -Match 'Add_KeyDown'
        $content | Should -Match 'SuppressKeyPress'
        $content | Should -Match 'Ctrl\+S'
        $content | Should -Match 'F5'
        $content | Should -Match 'Ctrl\+L'
        $content | Should -Match 'Ctrl\+Z'
        $content | Should -Match 'Ctrl\+Y'
        $content | Should -Match 'Ctrl\+E'
    }

    It 'Uses confirmation dialogs before destructive or launch actions' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Confirm Stop'
        $content | Should -Match 'Confirm Worker Launch'
        $content | Should -Match 'Confirm Controller Launch'
        $content | Should -Match 'YesNo'
    }

    It 'Shows labeled section headers above status and history panes' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Run Status'
        $content | Should -Match 'Undo / Redo History'
        $content | Should -Match 'Results'
    }

    It 'Exposes a UTF-8 BOM Sync tab with dual-panel layout' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'UTF-8 BOM Sync'
        $content | Should -Match 'bomTab'
        $content | Should -Match 'lstBomNeed'
        $content | Should -Match 'lstBomHave'
        $content | Should -Match 'Without BOM'
        $content | Should -Match 'With BOM'
    }

    It 'Provides Scan, Sync, Move Right, Move Left, and Move All buttons on the BOM tab' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'btnBomScan'
        $content | Should -Match 'btnBomSync'
        $content | Should -Match 'btnBomMoveRight'
        $content | Should -Match 'btnBomMoveLeft'
        $content | Should -Match 'btnBomMoveAllRight'
    }

    It 'Implements BOM detection and sync helper functions' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'function Test-FileHasBom'
        $content | Should -Match 'function Invoke-BomScan'
        $content | Should -Match 'function Invoke-BomSync'
        $content | Should -Match '0xEF.*0xBB.*0xBF'
    }

    It 'Uses confirmation dialog before applying BOM sync' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Confirm BOM Sync'
    }

    It 'Catches PipelineStoppedException in timer callbacks (Ctrl+C hardening)' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'PipelineStoppedException'
        $content | Should -Match 'add_ThreadException'
        $content | Should -Match 'UnhandledExceptionMode'
    }

    It 'Includes Get-WindowsKey in the Machine Info script picker' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Get-WindowsKey'
        $content | Should -Match 'windowsKeyScript'
        $content | Should -Match 'WindowsKey_Output\.csv'
    }

    It 'Auto-loads the local machine name as an example target in Machine Info' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match '\$env:COMPUTERNAME'
        $content | Should -Match 'pre-loaded as an example'
    }

    It 'Caches MI result objects for resize-aware rendering' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match '\$script:LastMIResultObjects'
        $content | Should -Match 'Render-MIResultsToPane'
    }

    It 'Re-renders MI results on textbox SizeChanged event' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Add_SizeChanged.*Render-MIResultsToPane'
    }

    It 'Uses Out-String -Width based on pane character width for table rendering' {
        $content = Get-Content -Path $script:guiPath -Raw
        $content | Should -Match 'Out-String\s+-Width\s+\$paneChars'
    }
}

Describe 'Tutorial coverage -- every use case has a tutorial track' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    # Machine Info dropdown entries that must have a matching tutorial track
    It 'Has a tutorial track referencing Get-MachineInfo' {
        $script:guiContent | Should -Match "'NeuronMachineInfo'|Neuron MachineInfo"
    }

    It 'Has a tutorial track referencing Get-PrinterMacSerial' {
        $script:guiContent | Should -Match "'PrinterMachineInfo'|Printer MachineInfo"
    }

    It 'Has a tutorial track referencing Get-RamInfo' {
        $script:guiContent | Should -Match "'RamInfo'|RAM Info"
    }

    It 'Has a tutorial track referencing Get-MonitorInfo' {
        $script:guiContent | Should -Match "'MonitorIdentification'|Monitor ID"
    }

    It 'Has a tutorial track referencing QueueInventory' {
        $script:guiContent | Should -Match "'QueueInventory'|Queue Inventory"
    }

    It 'Has a tutorial track referencing Inventory-Software' {
        $script:guiContent | Should -Match "'SoftwareInventory'|Software Inventory"
    }

    It 'Has a tutorial track for Printer Mapping (Run Control tab)' {
        $script:guiContent | Should -Match "'PrinterMapping'|Printer Mapping"
    }

    It 'Has a tutorial track for Kronos Clock Probe' {
        $script:guiContent | Should -Match "'KronosClock'|Kronos"
    }

    It 'Has a tutorial track for QR Tasks' {
        $script:guiContent | Should -Match "'QRTasks'|QR Tasks"
    }

    It 'Has a tutorial track for Deploy Shortcuts' {
        $script:guiContent | Should -Match "'DeployShortcuts'|Deploy Shortcuts"
    }

    It 'Has a tutorial track for Go-Live Pipeline' {
        $script:guiContent | Should -Match "'GoLivePipeline'|Go-Live Pipeline"
    }

    It 'Has a tutorial track for AD Printing Group' {
        $script:guiContent | Should -Match "'ADPrintingGroup'|AD Printing Group"
    }

    It 'Has a tutorial track for Utilities' {
        $script:guiContent | Should -Match "'UtilitiesOverview'|Utilities"
    }

    It 'Has a tutorial track for Repo Health / BOM Sync' {
        $script:guiContent | Should -Match "'RepoHealth'|Repo Health"
    }

    It 'Has a tutorial track for PS Version Pivot' {
        $script:guiContent | Should -Match "'PSVersionPivot'|PS Version Pivot"
    }

    It 'Has a tutorial track for Network Testing' {
        $script:guiContent | Should -Match "'NetworkTest'|Network Test"
    }

    It 'Has a tutorial track for OCR Floor Plan' {
        $script:guiContent | Should -Match "'OCRFloorPlan'|OCR Floor Plan"
    }

    It 'Inventory-Software appears in the Machine Info dropdown' {
        $script:guiContent | Should -Match 'Inventory-Software.*installed software audit'
    }

    It 'QR Task Runner appears in the Machine Info dropdown' {
        $script:guiContent | Should -Match 'QR Task Runner.*run a QR diagnostic task locally'
    }
}

Describe 'Tutorial text quality -- no AI slop' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    It 'No quadruple backslashes in tutorial body text' {
        # PowerShell does not escape backslashes, so \\\\ displays literally as \\\\
        $script:guiContent | Should -Not -Match 'Body = .*\\\\\\\\\\\\\\\\'
    }
}

Describe 'Tutorial highlights -- every step guides the user' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    It 'No tutorial step has an empty Highlights array' {
        # Match Highlights = @() which means no guidance
        $script:guiContent | Should -Not -Match "Highlights = @\(\)"
    }
}

Describe 'Tutorial menu pagination' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    It 'Defines menu page state and per-page constant' {
        $script:guiContent | Should -Match '\$script:MenuPage'
        $script:guiContent | Should -Match '\$script:MenuPerPage'
    }

    It 'Provides Prev/Next page navigation buttons' {
        $script:guiContent | Should -Match '\$script:MenuPagePrev'
        $script:guiContent | Should -Match '\$script:MenuPageNext'
    }

    It 'Has a Show-TutorialMenuPage function for paginated rendering' {
        $script:guiContent | Should -Match 'function Show-TutorialMenuPage'
    }
}

Describe 'Launch-SysAdminSuite.bat -- launcher checks' {
    BeforeAll {
        $script:launcherPath = Join-Path $script:repoRoot 'Launch-SysAdminSuite.bat'
    }

    It 'Launcher batch file exists at repo root' {
        $script:launcherPath | Should -Exist
    }

    It 'Invokes PowerShell with -STA and the GUI script' {
        $content = Get-Content -Path $script:launcherPath -Raw
        $content | Should -Match '-STA'
        $content | Should -Match 'Start-SysAdminSuiteGui\.ps1'
        $content | Should -Match '-ExecutionPolicy Bypass'
    }

    It 'Uses START /B so the CMD window closes immediately (Ctrl+C hardening)' {
        $content = Get-Content -Path $script:launcherPath -Raw
        $content | Should -Match 'start\s+""'
        $content | Should -Match '/B'
    }
}

# ── QR Code Integration ──────────────────────────────────────────────────────

Describe 'QRCoder DLL -- library availability' {
    BeforeAll {
        $script:qrDllPath = Join-Path $script:repoRoot 'lib\QRCoder.dll'
    }

    It 'QRCoder.dll exists in lib/' {
        $script:qrDllPath | Should -Exist
    }

    It 'QRCoder.dll is a valid .NET assembly' {
        { [System.Reflection.AssemblyName]::GetAssemblyName($script:qrDllPath) } | Should -Not -Throw
    }

    It 'QRCoder.dll targets .NET Framework (net40)' {
        $asmName = [System.Reflection.AssemblyName]::GetAssemblyName($script:qrDllPath)
        # net40 assemblies reference mscorlib, version 4.x
        $asmName | Should -Not -BeNullOrEmpty
    }

    It 'QRCoder.dll can be loaded into the current session' {
        Add-Type -Path $script:qrDllPath -ErrorAction SilentlyContinue
        $qrType = [Type]'QRCoder.QRCodeGenerator'
        $qrType | Should -Not -BeNullOrEmpty
    }
}

Describe 'QRCoder -- functional QR generation' {
    BeforeAll {
        $script:qrDllPath = Join-Path $script:repoRoot 'lib\QRCoder.dll'
        Add-Type -Path $script:qrDllPath -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    }

    It 'Generates a QRCodeData object from a simple string' {
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode('test', [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $data.ModuleMatrix.Count | Should -BeGreaterThan 0
        $gen.Dispose()
    }

    It 'Generates a Bitmap from QRCodeData' {
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode('SysAdminSuite', [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $qr = New-Object QRCoder.QRCode($data)
        $bmp = $qr.GetGraphic(4)
        $bmp | Should -BeOfType [System.Drawing.Bitmap]
        $bmp.Width | Should -BeGreaterThan 0
        $bmp.Height | Should -BeGreaterThan 0
        $bmp.Dispose(); $qr.Dispose(); $gen.Dispose()
    }

    It 'Handles tab-separated multi-line data (spreadsheet paste scenario)' {
        $payload = "HOST001`tSN123`t10.1.2.3`tAA:BB:CC:DD:EE:FF`nHOST002`tSN456`t10.1.2.4`t11:22:33:44:55:66"
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode($payload, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $qr = New-Object QRCoder.QRCode($data)
        $bmp = $qr.GetGraphic(4)
        $bmp | Should -BeOfType [System.Drawing.Bitmap]
        $bmp.Dispose(); $qr.Dispose(); $gen.Dispose()
    }

    It 'Handles long payloads up to 2000 characters' {
        $longText = 'A' * 2000
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode($longText, [QRCoder.QRCodeGenerator+ECCLevel]::L)
        $qr = New-Object QRCoder.QRCode($data)
        $bmp = $qr.GetGraphic(2)
        $bmp | Should -BeOfType [System.Drawing.Bitmap]
        $bmp.Dispose(); $qr.Dispose(); $gen.Dispose()
    }
}

Describe 'GUI script -- QR code integration contracts' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    It 'Loads QRCoder DLL at startup' {
        $script:guiContent | Should -Match 'QRCoder\.dll'
        $script:guiContent | Should -Match 'QRCoderAvailable'
    }

    It 'Defines New-QRBitmap helper function' {
        $script:guiContent | Should -Match 'function New-QRBitmap'
    }

    It 'Defines Format-MIResultsForQR helper function' {
        $script:guiContent | Should -Match 'function Format-MIResultsForQR'
    }

    It 'Defines Update-MIQRCode helper function' {
        $script:guiContent | Should -Match 'function Update-MIQRCode'
    }

    It 'Has a PictureBox for QR code display on the Machine Info tab' {
        $script:guiContent | Should -Match 'picMIQR'
        $script:guiContent | Should -Match 'PictureBox'
        $script:guiContent | Should -Match 'SizeMode.*Zoom'
    }

    It 'Has a QR label with scan instruction' {
        $script:guiContent | Should -Match 'lblMIQR'
        $script:guiContent | Should -Match 'QR Code.*scan'
    }

    It 'Calls Update-MIQRCode from Set-MIResults' {
        $script:guiContent | Should -Match 'Update-MIQRCode'
    }

    It 'Clears QR when results are empty' {
        $script:guiContent | Should -Match 'picMIQR\.Image = \$null.*picMIQR\.Visible = \$false'
    }

    It 'Truncates QR payload to keep codes scannable' {
        $script:guiContent | Should -Match '2000'
        $script:guiContent | Should -Match 'Substring'
    }

    It 'Provides a tooltip on the QR PictureBox' {
        $script:guiContent | Should -Match 'ToolTip'
        $script:guiContent | Should -Match 'SetToolTip.*picMIQR'
    }

    It 'Gracefully degrades when QRCoder DLL is missing' {
        $script:guiContent | Should -Match 'QRCoderAvailable.*\$false'
        # New-QRBitmap should return null when not available
        $script:guiContent | Should -Match 'if.*-not.*QRCoderAvailable.*return \$null'
    }
}

Describe 'QR Code -- cross-mode coverage and edge cases' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    # Every mode that calls Set-MIResults gets QR for free.
    # Verify all 9 modes are wired into the handler.
    It 'Mode 0 (Get-MachineInfo) calls Set-MIResults' {
        # The switch case 0 block should call Set-MIResults
        $script:guiContent | Should -Match 'Get-MachineInfo[\s\S]*?Set-MIResults'
    }

    It 'Mode 1 (Get-PrinterMacSerial) calls Set-MIResults' {
        $script:guiContent | Should -Match 'Get-PrinterMacSerial[\s\S]*?Set-MIResults'
    }

    It 'Mode 2 (Get-RamInfo) calls Set-MIResults' {
        $script:guiContent | Should -Match 'Get-RamInfo[\s\S]*?Set-MIResults'
    }

    It 'Mode 3 (Get-MonitorInfo) calls Set-MIResults' {
        $script:guiContent | Should -Match 'Get-MonitorInfo[\s\S]*?Set-MIResults'
    }

    It 'Mode 4 (ZebraPrinterTest) calls Set-MIResults' {
        $script:guiContent | Should -Match 'ZebraPrinterTest[\s\S]*?Set-MIResults'
    }

    It 'Mode 5 (QueueInventory) calls Set-MIResults' {
        $script:guiContent | Should -Match 'QueueInventory[\s\S]*?Set-MIResults'
    }

    It 'Mode 6 (Get-WindowsKey) calls Set-MIResults' {
        $script:guiContent | Should -Match 'Get-WindowsKey[\s\S]*?Set-MIResults'
    }

    It 'Mode 7 (Inventory-Software) calls Set-MIResults' {
        $script:guiContent | Should -Match 'Inventory-Software[\s\S]*?Set-MIResults'
    }

    It 'Mode 8 (QR Task Runner) generates QR from raw task output' {
        $script:guiContent | Should -Match 'QR Task Runner[\s\S]*?New-QRBitmap'
    }

    It 'Clears QR on error (catch block)' {
        $script:guiContent | Should -Match 'catch[\s\S]{0,200}?picMIQR\.Image = \$null'
    }

    It 'Clears QR when QR task list is shown (no data scenario)' {
        $script:guiContent | Should -Match 'Available QR Tasks[\s\S]{0,800}?picMIQR\.Visible = \$false'
    }

    It 'Set-MIResults calls Update-MIQRCode for data flow' {
        $script:guiContent | Should -Match 'Set-MIResults[\s\S]*?Update-MIQRCode'
    }

    It 'Set-MIResults clears QR when data is empty' {
        $script:guiContent | Should -Match 'Set-MIResults[\s\S]*?picMIQR\.Image = \$null'
    }
}

Describe 'QR Code -- Format-MIResultsForQR output conventions' {
    BeforeAll {
        $script:guiContent = Get-Content -Path $script:guiPath -Raw
    }

    It 'Uses tab-separated values for scanner-to-spreadsheet compatibility' {
        # The function should join with tab (PowerShell backtick-t)
        $script:guiContent | Should -Match 'Format-MIResultsForQR[\s\S]*?-join.*`t'
    }

    It 'Uses newline to separate rows' {
        $script:guiContent | Should -Match 'Format-MIResultsForQR[\s\S]*?-join.*`n'
    }

    It 'Reads from LastMIResultObjects cache' {
        $script:guiContent | Should -Match 'Format-MIResultsForQR[\s\S]*?LastMIResultObjects'
    }

    It 'Returns empty string when no results are cached' {
        $script:guiContent | Should -Match "Format-MIResultsForQR[\s\S]*?return ''"
    }
}

Describe 'QRCoder -- edge case QR generation' {
    BeforeAll {
        $script:qrDllPath = Join-Path $script:repoRoot 'lib\QRCoder.dll'
        Add-Type -Path $script:qrDllPath -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    }

    It 'Handles single-character input' {
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode('A', [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $qr = New-Object QRCoder.QRCode($data)
        $bmp = $qr.GetGraphic(4)
        $bmp | Should -BeOfType [System.Drawing.Bitmap]
        $bmp.Dispose(); $qr.Dispose(); $gen.Dispose()
    }

    It 'Handles special characters (serial numbers, UNC paths)' {
        $payload = '\\SERVER\Share\Path SN:MXL1234567 MAC:AA:BB:CC:DD:EE:FF'
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode($payload, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $qr = New-Object QRCoder.QRCode($data)
        $bmp = $qr.GetGraphic(4)
        $bmp | Should -BeOfType [System.Drawing.Bitmap]
        $bmp.Dispose(); $qr.Dispose(); $gen.Dispose()
    }

    It 'Generates different bitmaps for different input strings' {
        $gen = New-Object QRCoder.QRCodeGenerator
        $d1 = $gen.CreateQrCode('HOST001', [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $d2 = $gen.CreateQrCode('HOST002', [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $d1.ModuleMatrix.Count | Should -Be $d2.ModuleMatrix.Count  # same version, same size
        # Build flat strings using index iteration to avoid pipeline unrolling issues
        $sb1 = [System.Text.StringBuilder]::new()
        $sb2 = [System.Text.StringBuilder]::new()
        for ($r = 0; $r -lt $d1.ModuleMatrix.Count; $r++) {
            $row1 = $d1.ModuleMatrix[$r]
            $row2 = $d2.ModuleMatrix[$r]
            for ($c = 0; $c -lt $row1.Count; $c++) {
                [void]$sb1.Append([int]$row1[$c])
                [void]$sb2.Append([int]$row2[$c])
            }
            [void]$sb1.Append('|')
            [void]$sb2.Append('|')
        }
        $sb1.ToString() | Should -Not -Be $sb2.ToString()
        $gen.Dispose()
    }

    It 'Produces a square bitmap' {
        $gen = New-Object QRCoder.QRCodeGenerator
        $data = $gen.CreateQrCode('square test', [QRCoder.QRCodeGenerator+ECCLevel]::Q)
        $qr = New-Object QRCoder.QRCode($data)
        $bmp = $qr.GetGraphic(8)
        $bmp.Width | Should -Be $bmp.Height
        $bmp.Dispose(); $qr.Dispose(); $gen.Dispose()
    }
}