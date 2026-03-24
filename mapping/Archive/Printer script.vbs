' Printer script.vbs — maps shared print queues for NY135-NEU site
' BUG-FIX: Removed global ON ERROR RESUME NEXT; replaced with localized error handling
' BUG-FIX: Updated comment block — SetDefaultPrinter is not called in this script (by design)
Option Explicit

Dim objNetwork, q, failCount, printers
Dim i

' BUG-FIX: Localized error handling around CreateObject
On Error Resume Next
Err.Clear
Set objNetwork = WScript.CreateObject("WScript.Network")
If Err.Number <> 0 Then
  WScript.Echo "FATAL: Could not create WScript.Network (" & Err.Number & "): " & Err.Description
  WScript.Quit 1
End If
On Error GoTo 0

printers = Array( _
  "\\SWBPNSHPS01V\NY135-NEU01", _
  "\\SWBPNSHPS01V\NY135-NEU03", _
  "\\SWBPNSHPS01V\NY135-NEU04", _
  "\\SWBPNSHPS01V\NY135-NEU05", _
  "\\SWBPNSHPS01V\NY135-NEU06", _
  "\\SWBPNSHPS01V\NY135-NEU07", _
  "\\SWBPNSHPS01V\NY135-NEU08", _
  "\\SWBPNSHPS01V\NY135-NEU09", _
  "\\SWBPNSHPS01V\NY135-NEU11" _
)

failCount = 0
For i = 0 To UBound(printers)
  q = printers(i)
  On Error Resume Next
  Err.Clear
  objNetwork.AddWindowsPrinterConnection q
  If Err.Number <> 0 Then
    WScript.Echo "ERROR: Failed to add '" & q & "' (" & Err.Number & "): " & Err.Description
    failCount = failCount + 1
    Err.Clear
  End If
  On Error GoTo 0
Next

' Most of the time, Project Managers do not want a default printer set.
' It is best to allow users to set their own default printer.
' To set a default, uncomment and update the line below:
' objNetwork.SetDefaultPrinter "\\SWBPNSHPS01V\NY135-NEU01"

If failCount > 0 Then
  WScript.Echo failCount & " printer(s) failed to map."
  WScript.Quit 1
End If

WScript.Quit 0

'Update list of print queues in objNetwork.AddWindowsPrinterConnection statements
'To deploy to other machines over the network, copy to
'    \\{computername}\c$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup