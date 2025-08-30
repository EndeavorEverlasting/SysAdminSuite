' MapXeroxPrinter.vbs  –  maps \\SWBPNSHPS01V\WL244-ENT06X
'                       or creates TCP/IP port (10.137.67.158)
'                       but names the printer **WL244-ENT06X** either way.

Option Explicit

Const QUEUE      = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP         = "10.137.67.158"
Const PORT       = "IP_" & IP                  ' IP_10.137.67.158
Const PRNNAME    = "WL244-ENT06X"              ' ← consistent display name
Const DRIVER     = "Xerox V4 Class Driver"     ' adjust to exact driver label
Const LOCATION   = "244 Westchester – ENT 06X"

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")

On Error Resume Next

'──────────────────────────────────────────────────────────────
' 1) Try the regular server share
'──────────────────────────────────────────────────────────────
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then GoSub SetExtras : WScript.Quit 0

Err.Clear  ' share failed ─ fall back to TCP/IP
WScript.Echo "Shared queue unavailable. Falling back to IP port..."

'──────────────────────────────────────────────────────────────
' 2) Build a Standard TCP/IP port if it doesn't exist
'──────────────────────────────────────────────────────────────
sh.Run "cscript //nologo ""%windir%\System32\printing_admin_scripts\en-US\prnport.vbs"" " & _
       "-a -r " & PORT & " -h " & IP & " -o raw -n 9100", 0, True

'──────────────────────────────────────────────────────────────
' 3) Add the printer on that port (named WL244-ENT06X)
'──────────────────────────────────────────────────────────────
sh.Run "rundll32 printui.dll,PrintUIEntry /if "                 & _
       "/b """ & PRNNAME & """ "                               & _
       "/r "  & PORT & " "                                     & _
       "/m """ & DRIVER & """ /z /q", 0, True

If Err.Number = 0 Then GoSub SetExtras

WScript.Quit 0

'──────────────────────────────────────────────────────────────
' Subroutine: add location/comment (optional but handy)
'──────────────────────────────────────────────────────────────
SetExtras:
    sh.Run "rundll32 printui.dll,PrintUIEntry /Xs /n " & _
           """" & PRNNAME & """ comment """ & PRNNAME & """", 0, True
    sh.Run "rundll32 printui.dll,PrintUIEntry /Xs /n " & _
           """" & PRNNAME & """ location """ & LOCATION & """", 0, True
Return
