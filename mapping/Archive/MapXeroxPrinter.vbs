' MapXeroxPrinter.vbs  –  maps \\SWBPNSHPS01V\WL244-ENT06X
'                       or creates TCP/IP port (10.137.67.158)
'                       but names the printer **WL244-ENT06X** either way.

Option Explicit

Const QUEUE      = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP         = "10.137.67.158"
' BUG-FIX: Const cannot use expressions in VBScript; PORT is now a runtime variable
Const PRNNAME    = "WL244-ENT06X"              ' consistent display name
Const DRIVER     = "Xerox V4 Class Driver"     ' adjust to exact driver label
Const LOCATION   = "244 Westchester - ENT 06X"
Dim PORT : PORT = "IP_" & IP                   ' IP_10.137.67.158

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")

'──────────────────────────────────────────────────────────────
' 1) Try the regular server share
'──────────────────────────────────────────────────────────────
On Error Resume Next
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then
    Err.Clear
    On Error GoTo 0
    GoSub SetExtras
    WScript.Quit 0
End If
Err.Clear  ' share failed - fall back to TCP/IP
On Error GoTo 0
WScript.Echo "Shared queue unavailable. Falling back to IP port..."

'──────────────────────────────────────────────────────────────
' 2) Build a Standard TCP/IP port if it doesn't exist
' BUG-FIX: Use locale-independent path for prnport.vbs
' BUG-FIX: Capture sh.Run return code and check for failure
'──────────────────────────────────────────────────────────────
Dim rcPort
rcPort = sh.Run("cscript //nologo ""%windir%\System32\spool\tools\prnport.vbs"" " & _
       "-a -r " & PORT & " -h " & IP & " -o raw -n 9100", 0, True)
If rcPort <> 0 Then
    WScript.Echo "ERROR: prnport.vbs failed (exit " & rcPort & ") for port '" & PORT & "' on IP " & IP
    WScript.Quit rcPort
End If

'──────────────────────────────────────────────────────────────
' 3) Add the printer on that port (named WL244-ENT06X)
' BUG-FIX: Capture sh.Run return code; check it instead of Err.Number
'──────────────────────────────────────────────────────────────
Dim rcPrn
rcPrn = sh.Run("rundll32 printui.dll,PrintUIEntry /if "                 & _
       "/b """ & PRNNAME & """ "                               & _
       "/r "  & PORT & " "                                     & _
       "/m """ & DRIVER & """ /z /q", 0, True)

If rcPrn = 0 Then GoSub SetExtras

WScript.Quit rcPrn

'──────────────────────────────────────────────────────────────
' Subroutine: add location/comment (optional but handy)
'──────────────────────────────────────────────────────────────
SetExtras:
    sh.Run "rundll32 printui.dll,PrintUIEntry /Xs /n " & _
           """" & PRNNAME & """ comment """ & PRNNAME & """", 0, True
    sh.Run "rundll32 printui.dll,PrintUIEntry /Xs /n " & _
           """" & PRNNAME & """ location """ & LOCATION & """", 0, True
Return
