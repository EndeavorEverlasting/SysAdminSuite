' MapWL244_ENT06X-IPP_Driver.vbs – maps queue or falls back to IP, uses Microsoft IPP Class Driver
Option Explicit
Const QUEUE = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP    = "10.137.67.158"
' BUG-FIX: Const cannot use expressions in VBScript; PORT is now a runtime variable
Const PRN   = "WL244-ENT06X"
Const DRV   = "Microsoft IPP Class Driver"   ' built-in, always present
Dim PORT : PORT = "IP_" & IP

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")

'--- 1. Try server queue -------------------------------------------------
On Error Resume Next
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then
    Err.Clear
    On Error GoTo 0
    SelfDeleteAndQuit
End If
Err.Clear
On Error GoTo 0

'--- 2. Create Standard TCP/IP port via WMI ------------------------------
On Error Resume Next
Dim svc : Set svc = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
Dim p   : Set p   = svc.Get("Win32_TCPIPPrinterPort").SpawnInstance_
p.Name        = PORT
p.Protocol    = 1        ' RAW
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

'--- 3. Add printer on that port -----------------------------------------
Dim rc
On Error Resume Next
rc = sh.Run("rundll32 printui.dll,PrintUIEntry /if /b """ & PRN & """ /r " _
       & PORT & " /m """ & DRV & """ /z /q", 0, True)
On Error GoTo 0
' BUG-FIX: Only self-delete on success
If rc = 0 Then
    SelfDeleteAndQuit
Else
    WScript.Echo "ERROR: rundll32 failed (exit " & rc & ") for printer '" & PRN & "' on port '" & PORT & "'"
    WScript.Quit rc
End If

'-----------------------------------------------------------------------
Sub SelfDeleteAndQuit
    ' BUG-FIX: sh is WScript.Shell which has no DeleteFile; use FileSystemObject instead
    Dim fso : Set fso = CreateObject("Scripting.FileSystemObject")
    On Error Resume Next
    fso.DeleteFile WScript.ScriptFullName
    On Error GoTo 0
    WScript.Quit 0
End Sub
