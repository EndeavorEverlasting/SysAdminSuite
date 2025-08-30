' Map all EL082 printers, then delete this script
Option Explicit
Dim net : Set net = CreateObject("WScript.Network")
Dim Q : Q = Array( _
  "\\SWBPHHHPS01V\EL082-MST17", _
  "\\SWBPHHHPS01V\EL082-MST18", _
  "\\SWBPHHHPS01V\EL082-MST19", _
  "\\SWBPHHHPS01V\EL082-MST20", _
  "\\SWBPHHHPS01V\EL082-MST21", _
  "\\SWBPHHHPS01V\EL082-MST22", _
  "\\SWBPHHHPS01V\EL082-MST23", _
  "\\SWBPHHHPS01V\EL082-MST24", _
  "\\SWBPHHHPS01V\EL082-MST25" _
)

On Error Resume Next
Dim i
For i = 0 To UBound(Q)
  net.AddWindowsPrinterConnection Q(i)
Next

' Optional: make the first one default
' net.SetDefaultPrinter Q(0)

' Self-delete if it ran from Startup
CreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName, True
