' MapWL244_ENT06X-PlainJane.vbs  –  runs at logon
Option Explicit
Const QUEUE = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP    = "10.137.67.158"
' BUG-FIX: Const cannot use expressions in VBScript; PORT is now a runtime variable
Const PRN   = "WL244-ENT06X"        ' display name users will see
Dim PORT : PORT = "IP_" & IP

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")

'--- 1. try normal queue ------------------------------------------------
On Error Resume Next
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then
    Err.Clear
    On Error GoTo 0
    WScript.Quit 0
End If
Err.Clear
On Error GoTo 0

'--- 2. fallback to raw TCP/IP port -------------------------------------
' BUG-FIX: Use locale-independent path for prnport.vbs
' BUG-FIX: Capture sh.Run return code and check for failure
Dim rc1
rc1 = sh.Run("cscript //nologo ""%windir%\System32\spool\tools\prnport.vbs"" " _
       & "-a -r " & PORT & " -h " & IP & " -o raw -n 9100", 0, True)
If rc1 <> 0 Then
    WScript.Echo "ERROR: prnport.vbs failed (exit " & rc1 & ") for port '" & PORT & "' on IP " & IP
    WScript.Quit rc1
End If

Dim rc2
rc2 = sh.Run("rundll32 printui.dll,PrintUIEntry /if /b """ & PRN & """ /r " _
       & PORT & " /m ""Xerox V4 Class Driver"" /z /q", 0, True)
If rc2 <> 0 Then
    WScript.Echo "ERROR: rundll32 failed (exit " & rc2 & ") for printer '" & PRN & "' on port '" & PORT & "'"
    WScript.Quit rc2
End If

WScript.Quit 0
