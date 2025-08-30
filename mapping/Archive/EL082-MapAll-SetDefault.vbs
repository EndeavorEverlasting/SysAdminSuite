' EL082-MapAll-SetDefault.vbs  (no-trace)
' Maps ALL EL082 printers and sets default based on hostname tail (MST###).
' Safe to run repeatedly; standard user context is fine.

Option Explicit
Const PRINT_SERVER = "\\SWBPHHHPS01V"  ' <--- change if different

Dim queues : queues = Array( _
  "EL082-MST17", "EL082-MST18", "EL082-MST19", "EL082-MST20", _
  "EL082-MST21", "EL082-MST22", "EL082-MST23", "EL082-MST24" _
)

Dim shell : Set shell = CreateObject("WScript.Shell")
Dim net   : Set net   = CreateObject("WScript.Network")

' Disable "Let Windows manage my default printer" (per-user, no identity stored)
On Error Resume Next
shell.RegWrite "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode", 1, "REG_DWORD"
On Error GoTo 0

Dim host : host = UCase(net.ComputerName)
Dim tail : tail = TailNumber(host)

Dim desiredDefault : desiredDefault = "EL082-MST17" ' fallback
If tail >= 51 And tail <= 54 Then
  desiredDefault = "EL082-MST17"
ElseIf tail = 55 Then
  desiredDefault = "EL082-MST20"
ElseIf tail = 57 Then
  desiredDefault = "EL082-MST24"
ElseIf tail = 58 Then
  desiredDefault = "EL082-MST18"
ElseIf tail = 61 Then
  desiredDefault = "EL082-MST19"
ElseIf tail = 63 Then
  desiredDefault = "EL082-MST21"
ElseIf tail = 66 Then
  desiredDefault = "EL082-MST22"
ElseIf tail = 67 Then
  desiredDefault = "EL082-MST23"
End If

Dim i, share
For i = LBound(queues) To UBound(queues)
  share = PRINT_SERVER & "\" & queues(i)
  MapPrinter share
Next

Dim defaultShare : defaultShare = PRINT_SERVER & "\" & desiredDefault
MapPrinter defaultShare
SetDefault defaultShare

' ===== Helpers =====
Sub MapPrinter(prnShare)
  Dim cmd : cmd = "rundll32 printui.dll,PrintUIEntry /in /q /n """ & prnShare & """"
  shell.Run cmd, 0, True
  On Error Resume Next
  net.AddWindowsPrinterConnection prnShare
  Err.Clear
  On Error GoTo 0
End Sub

Sub SetDefault(prnShare)
  On Error Resume Next
  shell.RegWrite "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode", 1, "REG_DWORD"
  On Error GoTo 0
  Dim cmd : cmd = "rundll32 printui.dll,PrintUIEntry /y /q /n """ & prnShare & """"
  shell.Run cmd, 0, True
  On Error Resume Next
  net.SetDefaultPrinter prnShare
  On Error GoTo 0
End Sub

Function TailNumber(s)
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
  TailNumber = CInt(s)
End Function
