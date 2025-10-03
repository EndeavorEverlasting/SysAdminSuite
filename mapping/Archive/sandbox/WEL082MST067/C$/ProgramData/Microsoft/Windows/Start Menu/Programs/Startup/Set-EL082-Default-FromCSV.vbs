Option Explicit
Dim net:Set net=CreateObject("WScript.Network")
Dim sh :Set sh =CreateObject("WScript.Shell")
Dim fso:Set fso=CreateObject("Scripting.FileSystemObject")

Dim host: host = UCase(net.ComputerName)
Dim svr : svr  = "SWBPHHHPS01V" ' change if needed

On Error Resume Next
sh.RegWrite "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode", 1, "REG_DWORD"
On Error GoTo 0

Dim csv : csv = "C:\ProgramData\EL082\el082_defaults.csv"
If Not fso.FileExists(csv) Then WScript.Quit 0

Dim ts, line, parts, h, s, wantShare: wantShare = ""
Set ts = fso.OpenTextFile(csv, 1)
If Not ts.AtEndOfStream Then ts.ReadLine ' header
Do While Not ts.AtEndOfStream
  line = Trim(ts.ReadLine)
  If Len(line)>0 Then
    parts = Split(line, ",")
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
On Error Resume Next
net.SetDefaultPrinter display
On Error GoTo 0
