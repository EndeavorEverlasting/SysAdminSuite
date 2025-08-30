' MapWL244_ENT06X.vbs  –  runs at logon
Option Explicit
Const QUEUE = "\\SWBPNSHPS01V\WL244-ENT06X"
Const IP    = "10.137.67.158"
Const PORT  = "IP_" & IP
Const PRN   = "WL244-ENT06X"        ' display name users will see

Dim net : Set net = CreateObject("WScript.Network")
Dim sh  : Set sh  = CreateObject("WScript.Shell")
On Error Resume Next

'--- 1. try normal queue ------------------------------------------------
net.AddWindowsPrinterConnection QUEUE
If Err.Number = 0 Then WScript.Quit 0

'--- 2. fallback to raw TCP/IP port -------------------------------------
Err.Clear
sh.Run "cscript //nologo %windir%\system32\printing_admin_scripts\prnport.vbs " _
       & "-a -r " & PORT & " -h " & IP & " -o raw -n 9100", 0, True

sh.Run "rundll32 printui.dll,PrintUIEntry /if /b """ & PRN & """ /r " _
       & PORT & " /m ""Xerox V4 Class Driver"" /z /q", 0, True
