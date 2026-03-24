'MapWL244_ENT06X.vbs – maps \\SWBPNSHPS01V\WL244-ENT06X
'                       or falls back to IP_10.137.67.158,
'                       using Xerox Global Print Driver PCL6 V5.860.8.0.
Option Explicit

Const QUEUE = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP    = "10.137.67.158"
' BUG-FIX: Const cannot use expressions in VBScript; PORT is now a runtime variable
Const PRN   = "WL244-ENT06X"
Const DRV   = "Xerox Global Print Driver PCL6 V5.860.8.0"   ' exact driver name
Dim PORT : PORT = "IP_" & IP

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")

'──────────────────────────────────────────────────────────────
' 1) Try the normal print-server queue
'──────────────────────────────────────────────────────────────
On Error Resume Next
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then
    Err.Clear
    On Error GoTo 0
    SelfDeleteAndQuit
End If
Err.Clear
On Error GoTo 0

'──────────────────────────────────────────────────────────────
' 2) Create Standard TCP/IP port via WMI  (no prnport.vbs needed)
'──────────────────────────────────────────────────────────────
On Error Resume Next
Dim svc : Set svc = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
Dim p   : Set p   = svc.Get("Win32_TCPIPPrinterPort").SpawnInstance_
p.Name        = PORT
p.Protocol    = 1            ' RAW
p.HostAddress = IP
p.PortNumber  = 9100
p.SNMPEnabled = False
p.Put_
' BUG-FIX: Check for WMI port creation failure before proceeding
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not create TCP/IP port '" & PORT & "': " & Err.Description & " (" & Err.Number & ")"
    Err.Clear
    On Error GoTo 0
    WScript.Quit 1
End If
Err.Clear
On Error GoTo 0

'──────────────────────────────────────────────────────────────
' 3) Add the printer on that port
'──────────────────────────────────────────────────────────────
' BUG-FIX: Capture return code and only self-delete on success
Dim rc
rc = sh.Run("rundll32 printui.dll,PrintUIEntry /if /b """ & PRN & _
       """ /r " & PORT & " /m """ & DRV & """ /z /q", 0, True)
If rc = 0 Then
    SelfDeleteAndQuit
Else
    WScript.Echo "ERROR: rundll32 failed (exit " & rc & ") for printer '" & PRN & "' on port '" & PORT & "'"
    WScript.Quit rc
End If

'──────────────────────────────────────────────────────────────
Sub SelfDeleteAndQuit
    ' BUG-FIX: sh is WScript.Shell which has no DeleteFile; use FileSystemObject instead
    Dim fso : Set fso = CreateObject("Scripting.FileSystemObject")
    On Error Resume Next
    fso.DeleteFile WScript.ScriptFullName
    On Error GoTo 0
    WScript.Quit 0
End Sub