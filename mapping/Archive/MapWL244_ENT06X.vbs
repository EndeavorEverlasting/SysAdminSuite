'MapWL244_ENT06X.vbs – maps \\SWBPNSHPS01V\WL244-ENT06X
'                       or falls back to IP_10.137.67.158,
'                       using Xerox Global Print Driver PCL6 V5.860.8.0.
Option Explicit

Const QUEUE = ""\\SWBPNSHPS01V\WL244-ENT06X""
Const IP    = ""10.137.67.158""
Const PORT  = ""IP_"" & IP
Const PRN   = ""WL244-ENT06X""
Const DRV   = ""Xerox Global Print Driver PCL6 V5.860.8.0""   ' ← exact driver name

Dim net : Set net = CreateObject(""WScript.Network"")
Dim sh  : Set sh  = CreateObject(""WScript.Shell"")
On Error Resume Next

'──────────────────────────────────────────────────────────────
' 1) Try the normal print-server queue
'──────────────────────────────────────────────────────────────
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then SelfDeleteAndQuit

'──────────────────────────────────────────────────────────────
' 2) Create Standard TCP/IP port via WMI  (no prnport.vbs needed)
'──────────────────────────────────────────────────────────────
Err.Clear
Dim svc : Set svc = GetObject(""winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2"")
Dim p   : Set p   = svc.Get(""Win32_TCPIPPrinterPort"").SpawnInstance_
p.Name        = PORT
p.Protocol    = 1            ' RAW
p.HostAddress = IP
p.PortNumber  = 9100
p.SNMPEnabled = False
p.Put_

'──────────────────────────────────────────────────────────────
' 3) Add the printer on that port
'──────────────────────────────────────────────────────────────
sh.Run ""rundll32 printui.dll,PrintUIEntry /if /b """""" & PRN & _
       """""" /r "" & PORT & "" /m """""" & DRV & """""" /z /q"", 0, True

SelfDeleteAndQuit

'──────────────────────────────────────────────────────────────
Sub SelfDeleteAndQuit
    ' Remove script from Startup after successful mapping.
    On Error Resume Next
    sh.DeleteFile WScript.ScriptFullName
    WScript.Quit 0
End Sub