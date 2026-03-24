Option Explicit

Dim objNetwork, objPrinterPath, objShell, pingRc
Set objNetwork = CreateObject("WScript.Network")
Set objShell = CreateObject("WScript.Shell")

' Fallback via IP path
objPrinterPath = "\\10.137.67.158\WL244-ENT06X"

' BUG-FIX: Perform a quick connectivity check before attempting AddWindowsPrinterConnection
'          to avoid hanging if the target is unreachable.
pingRc = objShell.Run("cmd /c ping -n 2 -w 1000 10.137.67.158 >nul 2>&1", 0, True)
If pingRc <> 0 Then
    ' BUG-FIX: Replaced Unicode emoji with plain ASCII markers for cross-locale compatibility
    objShell.Popup "[ERROR] Printer host unreachable (ping failed). Cannot map: " & objPrinterPath, 10, "Mapping Error", 16
    WScript.Quit 1
End If

' Add printer
On Error Resume Next
Err.Clear
objNetwork.AddWindowsPrinterConnection objPrinterPath
If Err.Number <> 0 Then
    ' BUG-FIX: Replaced Unicode emoji with plain ASCII markers for cross-locale compatibility
    objShell.Popup "[ERROR] Failed to map printer via IP: " & objPrinterPath & vbCrLf & "Error: " & Err.Description, 10, "Mapping Error", 16
    Err.Clear
    On Error GoTo 0
    WScript.Quit 1
Else
    objShell.Popup "[OK] Printer mapped successfully via IP: " & objPrinterPath, 3, "Mapping Success", 64
End If
On Error GoTo 0

WScript.Quit 0
