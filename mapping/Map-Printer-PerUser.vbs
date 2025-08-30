' Map-Printer-PerUser.vbs — per-user mappings, idempotent
Option Explicit
Dim shell, net, q, printers, defaultQ
Set shell = CreateObject("WScript.Shell")
Set net   = CreateObject("WScript.Network")

' 1) Disable "Let Windows manage my default printer" for current user
On Error Resume Next
shell.RegWrite "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode", 1, "REG_DWORD"

' 2) EDIT ME: queues to add (per-user) and the default
printers = Array( _
  "\\SWBPMHXPS01V\EL082-MST03X", _
  "\\SWBPHHHPS01V\EL082-MST15" _
)
defaultQ = "\\SWBPHHHPS01V\EL082-MST15"

' 3) Add the printers (+ re-run safe), then set the default
For Each q In printers
  net.AddWindowsPrinterConnection q
Next
net.SetDefaultPrinter defaultQ
WScript.Quit 0
