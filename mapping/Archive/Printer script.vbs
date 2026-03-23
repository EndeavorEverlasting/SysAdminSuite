ON ERROR RESUME NEXT
Set objNetwork = WScript.CreateObject("WScript.Network") 


objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU01"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU03"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU04"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU05"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU06"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU07"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU08"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU09"
objNetwork.AddWindowsPrinterConnection "\\SWBPNSHPS01V\NY135-NEU11"


'Most of the time, Project Managers do not want a default printer set
'It is best to allow users to set their own default printer
'But if there is a need, remove the single-quote at the beginning of the line
'and enter the proper print server and queue between the double-quotes
'wscript.echo "Done!"


WScript.quit

'Update list of print queues in objNetwork.AddWindowsPrinterConnection statements
'Also update SetDefaultPrinter statement

'To deploy to other machines over the network, copy to
'    \\{computername}\c$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup