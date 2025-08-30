param(
  [Parameter(Mandatory)][string]$CsvPath,
  [string]$DomainSuffix = "nslijhs.net",
  [string]$AltUser,   # optional DOMAIN\user if your current token isn't local admin
  [string]$AltPass    # optional password
)

# === EDIT if needed ===
$Printers = @(
  "\\SWBPNSHPS01\WPV522-PED01",
  "\\SWBPNSHPS01\WPV522-PED02",
  "\\SWBPNSHPS01\WPV522-PED03",
  "\\SWBPNSHPS01\WPV522-PED04"
)
# ======================

function New-RemoteTask([string]$Target,[string]$TaskName,[string]$Cmd){
  $create = @("/Create","/S",$Target,"/RU","SYSTEM","/RL","HIGHEST","/SC","ONCE","/ST","00:00",
              "/TN",$TaskName,"/TR","cmd.exe /c $Cmd","/F")
  if ($AltUser){ $create = @("/Create","/S",$Target,"/U",$AltUser,"/P",$AltPass,"/RU","SYSTEM","/RL","HIGHEST","/SC","ONCE","/ST","00:00","/TN",$TaskName,"/TR","cmd.exe /c $Cmd","/F") }
  schtasks @create | Out-Null
  $run = @("/Run","/S",$Target,"/TN",$TaskName)
  if ($AltUser){ $run = @("/Run","/S",$Target,"/U",$AltUser,"/P",$AltPass,"/TN",$TaskName) }
  schtasks @run | Out-Null
}
function Remove-RemoteTask([string]$Target,[string]$TaskName){
  $del = @("/Delete","/S",$Target,"/TN",$TaskName,"/F")
  if ($AltUser){ $del = @("/Delete","/S",$Target,"/U",$AltUser,"/P",$AltPass,"/TN",$TaskName,"/F") }
  schtasks @del | Out-Null
}

$rows = Import-Csv $CsvPath
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$log = Join-Path $PSScriptRoot "printer_deploy_$stamp.log"

foreach ($r in $rows){
  $Target = $r.Hostname.Trim()
  if (-not $Target){ continue }
  Write-Host "==> $Target"

  foreach ($conn in $Printers){
    $task = "Map_$($Target)_$($conn.Split('\')[-1])_$stamp"
    $cmd  = "rundll32 printui.dll,PrintUIEntry /in /q /n `"$conn`""

    $ok = $false
    try { New-RemoteTask $Target $task $cmd; $ok = $true }
    catch {
      # retry with FQDN
      $fqdn = "$Target.$DomainSuffix"
      try { New-RemoteTask $fqdn $task $cmd; $ok = $true }
      catch { Add-Content $log "ERR $Target : $conn : $($_.Exception.Message)" }
      finally { Remove-RemoteTask $fqdn $task }
    }
    finally { Remove-RemoteTask $Target $task }

    if ($ok){ Add-Content $log "OK  $Target : $conn" }
  }
}
Write-Host "Done. Log: $log"
