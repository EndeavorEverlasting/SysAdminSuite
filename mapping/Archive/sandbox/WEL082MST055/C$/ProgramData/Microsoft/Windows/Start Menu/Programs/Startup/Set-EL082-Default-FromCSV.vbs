Option Explicit
Dim net:Set net=CreateObject("WScript.Network")
Dim sh :Set sh =CreateObject("WScript.Shell")
Dim fso:Set fso=CreateObject("Scripting.FileSystemObject")

Dim host: host = UCase(net.ComputerName)
Dim svr : svr  = "SWBPHHHPS01V" ' change if needed

' BUG-FIX: Check RegWrite result so we know if the registry change failed
On Error Resume Next
Err.Clear
sh.RegWrite "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode", 1, "REG_DWORD"
If Err.Number <> 0 Then
  WScript.Echo "WARNING: RegWrite failed (" & Err.Number & "): " & Err.Description
  Err.Clear
End If
On Error GoTo 0

Dim csv : csv = "C:\ProgramData\EL082\el082_defaults.csv"
If Not fso.FileExists(csv) Then WScript.Quit 0

' BUG-FIX: Wrap OpenTextFile in error handling
Dim ts, line, parts, h, s, wantShare: wantShare = ""
On Error Resume Next
Err.Clear
Set ts = fso.OpenTextFile(csv, 1)
If Err.Number <> 0 Then
  WScript.Echo "ERROR: Cannot open CSV (" & Err.Number & "): " & Err.Description
  WScript.Quit 1
End If
On Error GoTo 0

If Not ts.AtEndOfStream Then ts.ReadLine ' header
Do While Not ts.AtEndOfStream
  line = Trim(ts.ReadLine)
  If Len(line)>0 Then
    ' BUG-FIX: Use a simple CSV-aware split that respects quoted fields
    parts = ParseCsvLine(line)
    If UBound(parts) >= 1 Then
      h = UCase(Trim(parts(0))) : s = Trim(parts(1))
      If h = host Then wantShare = s : Exit Do
      If h = "*" And wantShare = "" Then wantShare = s
    End If
  End If
Loop
ts.Close

If wantShare = "" Then WScript.Quit 0
Dim display: display = wantShare & " on " & svr
' BUG-FIX: Check SetDefaultPrinter result
On Error Resume Next
Err.Clear
net.SetDefaultPrinter display
If Err.Number <> 0 Then
  WScript.Echo "ERROR: SetDefaultPrinter failed for '" & display & "' (" & Err.Number & "): " & Err.Description
  Err.Clear
  On Error GoTo 0
  WScript.Quit 1
End If
On Error GoTo 0


' --- CSV-aware line parser (handles quoted fields with embedded commas) ---
Function ParseCsvLine(ByVal sLine)
  Dim result, cur, i, ch, inQuote, fieldCount
  ReDim result(0)
  cur = "" : inQuote = False : fieldCount = 0
  For i = 1 To Len(sLine)
    ch = Mid(sLine, i, 1)
    If inQuote Then
      If ch = """" Then
        If i < Len(sLine) And Mid(sLine, i+1, 1) = """" Then
          cur = cur & """" : i = i  ' escaped quote
        Else
          inQuote = False
        End If
      Else
        cur = cur & ch
      End If
    Else
      If ch = """" Then
        inQuote = True
      ElseIf ch = "," Then
        ReDim Preserve result(fieldCount)
        result(fieldCount) = cur : fieldCount = fieldCount + 1 : cur = ""
      Else
        cur = cur & ch
      End If
    End If
  Next
  ReDim Preserve result(fieldCount)
  result(fieldCount) = cur
  ParseCsvLine = result
End Function