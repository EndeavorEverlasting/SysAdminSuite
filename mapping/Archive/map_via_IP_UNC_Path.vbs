Option Explicit

Dim objNetwork, objPrinterPath, objShell
Set objNetwork = CreateObject("WScript.Network")
Set objShell = CreateObject("WScript.Shell")

' Fallback via IP path
objPrinterPath = "\\10.137.67.158\WL244-ENT06X"

' Add printer
On Error Resume Next
objNetwork.AddWindowsPrinterConnection objPrinterPath
If Err.Number <> 0 Then
    objShell.Popup "❌ Failed to map printer via IP: " & objPrinterPath & vbCrLf & "Error: " & Err.Description, 10, "Mapping Error", 16
Else
    objShell.Popup "✅ Printer mapped successfully via IP: " & objPrinterPath, 3, "Mapping Success", 64
End If
On Error GoTo 0
