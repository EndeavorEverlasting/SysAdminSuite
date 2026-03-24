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

' BUG-FIX: Removed global "On Error Resume Next" — it silently swallowed all errors.
' Error handling is now scoped per-connection so failures are visible.
Dim i
Dim failCount : failCount = 0
Dim summary : summary = ""
For i = 0 To UBound(Q)
  On Error Resume Next
  net.AddWindowsPrinterConnection Q(i)
  If Err.Number <> 0 Then
    summary = summary & "FAIL: " & Q(i) & " (" & Err.Description & ")" & vbCrLf
    failCount = failCount + 1
    Err.Clear
  Else
    summary = summary & "OK:   " & Q(i) & vbCrLf
  End If
  On Error GoTo 0
Next

' Optional: make the first one default
' net.SetDefaultPrinter Q(0)

' Emit summary before self-deleting so failures are visible
WScript.Echo summary
If failCount > 0 Then
  WScript.Echo failCount & " printer(s) failed to map. See above."
End If

' BUG-FIX: Only self-delete when all mappings succeeded so failed runs can be retried
If failCount = 0 Then
  CreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName, True
End If
