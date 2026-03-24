' Save as PrinterConfig.vbs
Option Explicit

Dim networkObj, computerName

Set networkObj = CreateObject("WScript.Network")
computerName = networkObj.ComputerName

WScript.Echo "Configuring printers for: " & computerName

' Configure based on computer type
If IsWorkstation(computerName) Then
    ConfigureWorkstationPrinters
ElseIf IsLaptop(computerName) Then
    ConfigureLaptopPrinters
Else
    WScript.Echo "Computer name '" & computerName & "' does not match expected pattern."
End If

WScript.Echo "Printer configuration complete!"

' Functions
Function IsWorkstation(name)
    IsWorkstation = (name = "WEL082MST039") Or (name = "WEL082MST040") Or _
                   (name = "WEL082MST041") Or (name = "WEL082MST042")
End Function

Function IsLaptop(name)
    IsLaptop = (name = "LEL082MST003") Or (name = "LEL082MST004") Or _
              (name = "LEL082MST005")
End Function

Sub ConfigureWorkstationPrinters()
    Dim printers(1, 1)
    
    ' Printer path, is default
    printers(0, 0) = "\\SWBPMHXPS01V\EL082-MST03X"
    printers(0, 1) = True
    printers(1, 0) = "\\SYKPHHHPS01V\EL082-MST15"
    printers(1, 1) = False
    
    Dim i
    For i = 0 To UBound(printers)
        If AddNetworkPrinter(printers(i, 0)) Then
            If printers(i, 1) Then
                SetDefaultPrinter printers(i, 0)
            End If
        End If
    Next
End Sub

Sub ConfigureLaptopPrinters()
    Dim printers(3)
    printers(0) = "\\SYKPHHHPS01V\EL082-MST15"
    printers(1) = "\\SWBPMHXPS01V\EL082-MST03X"
    printers(2) = "\\SYKPHHHPS01V\EL082-MST13"
    printers(3) = "\\SYKPHHHPS01V\EL082-MST14"
    
    Dim i
    For i = 0 To UBound(printers)
        AddNetworkPrinter printers(i)
    Next
End Sub

Function AddNetworkPrinter(printerPath)
    On Error Resume Next
    ' BUG-FIX: Call Err.Clear before the operation so prior errors don't cause false failures
    Err.Clear

    WScript.Echo "Adding printer: " & printerPath
    networkObj.AddWindowsPrinterConnection printerPath

    If Err.Number = 0 Then
        WScript.Echo "Successfully added: " & printerPath
        AddNetworkPrinter = True
    Else
        WScript.Echo "Error adding printer " & printerPath & ": " & Err.Description
        AddNetworkPrinter = False
    End If
    Err.Clear

    On Error GoTo 0
End Function

Sub SetDefaultPrinter(printerPath)
    On Error Resume Next
    ' BUG-FIX: Call Err.Clear before the operation so prior errors don't cause false failures
    Err.Clear

    WScript.Echo "Setting default printer: " & printerPath
    networkObj.SetDefaultPrinter printerPath

    If Err.Number = 0 Then
        WScript.Echo "Default printer set successfully"
    Else
        WScript.Echo "Error setting default printer: " & Err.Description
    End If
    Err.Clear

    On Error GoTo 0
End Sub