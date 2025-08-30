' Map *all* EL082 printers on this PC and set the correct default based on hostname.
' - Idempotent: safe to run repeatedly (at Startup or manually).
' - Maps every queue: MST17..MST24 from print server SWBPHHHPS01V
' - Sets default per the table below; others default to MST17.

Option Explicit

Dim net : Set net = CreateObject("WScript.Network")
Dim fso : Set fso = CreateObject("Scripting.FileSystemObject")

Const PRINT_SERVER = "\\SWBPHHHPS01V"

' ---- All queues to map on every PC ----
Dim queues : queues = Array( _
  "EL082-MST17", _
  "EL082-MST18", _
  "EL082-MST19", _
  "EL082-MST20", _
  "EL082-MST21", _
  "EL082-MST22", _
  "EL082-MST23", _
  "EL082-MST24" _
)

' ---- Default mapping rules ----
' MST051–MST054  -> MST17  (range)
' MST055         -> MST20
' MST057         -> MST24
' MST058         -> MST18
' MST061         -> MST19
' MST063         -> MST21
' MST066         -> MST22
' MST067         -> MST23
' All others     -> MST17

Dim hostname : hostname = UCase(net.ComputerName)
Dim tail : tail = TailNumber(hostname)
Dim defaultQueue : defaultQueue
defaultQueue = "EL082-MST17"  ' sensible fallback

If tail >= 51 And tail <= 54 Then
  defaultQueue = "EL082-MST17"
ElseIf tail = 55 Then
  defaultQueue = "EL082-MST20"
ElseIf tail = 57 Then
  defaultQueue = "EL082-MST24"
ElseIf tail = 58 Then
  defaultQueue = "EL082-MST18"
ElseIf tail = 61 Then
  defaultQueue = "EL082-MST19"
ElseIf tail = 63 Then
  defaultQueue = "EL082-MST21"
ElseIf tail = 66 Then
  defaultQueue = "EL082-MST22"
ElseIf tail = 67 Then
  defaultQueue = "EL082-MST23"
End If

' ---- Map every queue ----
Dim i, share
For i = LBound(queues) To UBound(queues)
  share = PRINT_SERVER & "\" & queues(i)
  MapPrinter share  ' ignore "already exists"
Next

' ---- Ensure the default queue exists, then set it ----
Dim defaultShare : defaultShare = PRINT_SERVER & "\" & defaultQueue
MapPrinter defaultShare
On Error Resume Next
net.SetDefaultPrinter defaultShare
On Error GoTo 0

' ---- Optional: write a tiny log to %TEMP% ----
Dim logPath : logPath = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%TEMP%") & "\EL082-PrinterMap.log"
Dim ts
On Error Resume Next
Set ts = fso.OpenTextFile(logPath, 8, True)
If Err.Number = 0 Then
  ts.WriteLine Now & " | Host=" & hostname & " tail=" & tail & " default=" & defaultShare
  ts.Close
End If
On Error GoTo 0

' ========= helpers =========
Sub MapPrinter(prnShare)
  On Error Resume Next
  net.AddWindowsPrinterConnection prnShare
  ' Clear benign errors (e.g., already connected)
  Err.Clear
  On Error GoTo 0
End Sub

Function TailNumber(s)
  ' Return the integer suffix at end of string (e.g., "WEL082MST055" -> 55).
  ' If none found, returns -1.
  Dim i, ch
  For i = Len(s) To 1 Step -1
    ch = Mid(s, i, 1)
    If ch < "0" Or ch > "9" Then
      If i < Len(s) Then
        TailNumber = CInt(Mid(s, i+1))
      Else
        TailNumber = -1
      End If
      Exit Function
    End If
  Next
  ' String ended with digits only
  TailNumber = CInt(s)
End Function
