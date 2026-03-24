' Map-Printer-PerUser.vbs — per-user mappings, idempotent
Option Explicit
Dim shell, net, q, printers, defaultQ
Set shell = CreateObject("WScript.Shell")
Set net   = CreateObject("WScript.Network")

' 1) Disable "Let Windows manage my default printer" for current user
' BUG-FIX: Limit On Error Resume Next to only the RegWrite call; check Err.Number after
On Error Resume Next
Err.Clear
shell.RegWrite "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode", 1, "REG_DWORD"
If Err.Number <> 0 Then
  WScript.Echo "WARNING: RegWrite failed (" & Err.Number & "): " & Err.Description
  Err.Clear
End If
On Error GoTo 0

' 2) EDIT ME: queues to add (per-user) and the default
printers = Array( _
  "\\SWBPMHXPS01V\EL082-MST03X", _
  "\\SWBPHHHPS01V\EL082-MST15" _
)
defaultQ = "\\SWBPHHHPS01V\EL082-MST15"

' 3) Add the printers (+ re-run safe), then set the default
' BUG-FIX: Check Err.Number after each AddWindowsPrinterConnection and SetDefaultPrinter
For Each q In printers
  On Error Resume Next
  Err.Clear
  net.AddWindowsPrinterConnection q
  If Err.Number <> 0 Then
    WScript.Echo "ERROR: AddWindowsPrinterConnection failed for '" & q & "' (" & Err.Number & "): " & Err.Description
    Err.Clear
  End If
  On Error GoTo 0
Next

On Error Resume Next
Err.Clear
net.SetDefaultPrinter defaultQ
If Err.Number <> 0 Then
  WScript.Echo "ERROR: SetDefaultPrinter failed for '" & defaultQ & "' (" & Err.Number & "): " & Err.Description
  Err.Clear
  On Error GoTo 0
  WScript.Quit 1
End If
On Error GoTo 0

WScript.Quit 0
