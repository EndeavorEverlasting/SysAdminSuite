' BUG-FIX: Removed global "ON ERROR RESUME NEXT" — it silently swallowed all errors.
' Error handling is now scoped around the connection call only.
Set objNetwork = WScript.CreateObject("WScript.Network")

' BUG-FIX: Replaced hardcoded IP "10.137.67.158" with the print server hostname.
' IPs can change; hostnames are stable and resolve via DNS.
' Update the queue name below to match your environment.
ON ERROR RESUME NEXT
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01\WL244-ENT06X"
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not add printer connection: " & Err.Description
    Err.Clear
End If
ON ERROR GOTO 0

'Most of the time, Project Managers do not want a default printer set.
'It is best to allow users to set their own default printer.
'But if there is a need, remove the single-quote at the beginning of the line
'and enter the proper print server and queue between the double-quotes:
'objNetwork.SetDefaultPrinter "\\SWBPNSHPS01\WL244-ENT06X"

WScript.quit

'Update list of print queues in objNetwork.AddWindowsPrinterConnection statements.
'Also update SetDefaultPrinter statement if used.

'To deploy to other machines over the network, copy to:
'    \\{computername}\c$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup