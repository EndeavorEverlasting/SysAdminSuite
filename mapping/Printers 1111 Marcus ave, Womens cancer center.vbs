ON ERROR RESUME NEXT
Set objNetwork = WScript.CreateObject("WScript.Network") 

objNetwork.AddWindowsPrinterConnection "\\SWBPNHPHPS01V\LS111-WCC50"

objNetwork.SetDefaultPrinter "\\SWBPNHPHPS01V\LS111-WCC50"

'Most of the time, Project Managers do not want a default printer set
'It is best to allow users to set their own default printer
'But if there is a need, remove the single-quote at the beginning of the line
'and enter the proper print server and queue between the double-quotes
'objNetwork.SetDefaultPrinter "\\SYKPLHHPRT02V\100B1FOODNUTR01"
'wscript.echo "Done!"


WScript.quit

'Update list of print queues in objNetwork.AddWindowsPrinterConnection statements
'Also update SetDefaultPrinter statement

'To deploy to other machines over the network, copy to
'    \\{computername}\c$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup