' MapWL244_ENT06X.vbs – maps queue or falls back to IP, uses Microsoft IPP Class Driver
Option Explicit
Const QUEUE = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP    = "10.137.67.158"
Const PORT  = "IP_" & IP
Const PRN   = "WL244-ENT06X"
Const DRV   = "Microsoft IPP Class Driver"   ' built-in, always present

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")
On Error Resume Next

'--- 1. Try server queue -------------------------------------------------
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then SelfDeleteAndQuit

'--- 2. Create Standard TCP/IP port via WMI ------------------------------
Err.Clear
Dim svc : Set svc = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
Dim p   : Set p   = svc.Get("Win32_TCPIPPrinterPort").SpawnInstance_
p.Name        = PORT
p.Protocol    = 1        ' RAW
p.HostAddress = IP
p.PortNumber  = 9100
p.SNMPEnabled = False
p.Put_

'--- 3. Add printer on that port -----------------------------------------
sh.Run "rundll32 printui.dll,PrintUIEntry /if /b """ & PRN & """ /r " _
       & PORT & " /m """ & DRV & """ /z /q", 0, True

SelfDeleteAndQuit

'-----------------------------------------------------------------------
Sub SelfDeleteAndQuit
    ' Remove the script from Startup after first success
    sh.DeleteFile WScript.ScriptFullName
    WScript.Quit 0
End Sub
