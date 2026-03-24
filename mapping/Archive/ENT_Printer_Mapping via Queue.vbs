' BUG-FIX: Removed global "ON ERROR RESUME NEXT" — it silently swallowed all errors.
' Error handling is now scoped around the WScript.Network creation and the connection call.

' Scope error handling around COM object creation only
On Error Resume Next
Set objNetwork = WScript.CreateObject("WScript.Network")
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not create WScript.Network: " & Err.Description
    Err.Clear
    WScript.Quit 1
End If
On Error GoTo 0

' Scope error handling around the printer connection call only
On Error Resume Next
objNetwork.AddWindowsPrinterConnection "\\swbpnsxps01v\WL244-ENT06X"
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not add printer connection: " & Err.Description
    Err.Clear
End If
On Error GoTo 0

'Most of the time, Project Managers do not want a default printer set.
'It is best to allow users to set their own default printer.
'But if there is a need, remove the single-quote at the beginning of the line
'and enter the proper print server and queue between the double-quotes:
'objNetwork.SetDefaultPrinter "\\swbpnsxps01v\WL244-ENT06X"

WScript.quit

'Update list of print queues in objNetwork.AddWindowsPrinterConnection statements.
'Also update SetDefaultPrinter statement if used.

'To deploy to other machines over the network, copy to:
'    \\{computername}\c$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup