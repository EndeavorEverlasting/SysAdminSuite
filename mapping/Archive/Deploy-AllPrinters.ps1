param(
  [Parameter(Mandatory)][string]$CsvPath,
  [string]$DomainSuffix = "nslijhs.net",
  [string]$AltUser,          # optional DOMAIN\user if your current token isn't local admin
  [SecureString]$AltPass     # optional password (SecureString to avoid plaintext exposure)
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
  # Extract plaintext only at the point of use; never store as string variable
  $plainPass = if ($AltPass) { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AltPass)) } else { $null }
  try {
    $create = @("/Create","/S",$Target,"/RU","INTERACTIVE","/RL","HIGHEST","/SC","ONCE","/ST","00:00",
                "/TN",$TaskName,"/TR","cmd.exe /c $Cmd","/F")
    if ($AltUser -and $plainPass){ $create = @("/Create","/S",$Target,"/U",$AltUser,"/P",$plainPass,"/RU","INTERACTIVE","/RL","HIGHEST","/SC","ONCE","/ST","00:00","/TN",$TaskName,"/TR","cmd.exe /c $Cmd","/F") }
    $createOut = schtasks @create 2>&1
    if ($LASTEXITCODE -ne 0) { throw "schtasks /Create failed (exit $LASTEXITCODE): $createOut" }
    $run = @("/Run","/S",$Target,"/TN",$TaskName)
    if ($AltUser -and $plainPass){ $run = @("/Run","/S",$Target,"/U",$AltUser,"/P",$plainPass,"/TN",$TaskName) }
    $runOut = schtasks @run 2>&1
    if ($LASTEXITCODE -ne 0) { throw "schtasks /Run failed (exit $LASTEXITCODE): $runOut" }
  } finally {
    if ($plainPass) { $plainPass = $null }
  }
}
function Wait-TaskComplete([string]$Target,[string]$TaskName,[int]$TimeoutSec=60){
  # Poll schtasks until the task is no longer Running, or timeout expires
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    Start-Sleep -Seconds 3
    $statusOut = schtasks /Query /S $Target /TN $TaskName /FO CSV /NH 2>&1
    if ($LASTEXITCODE -ne 0) { break }   # task may have been deleted already
    $status = ($statusOut | ConvertFrom-Csv -Header 'Name','NextRun','Status' | Select-Object -First 1).Status
  } while ($status -eq 'Running' -and (Get-Date) -lt $deadline)
}
function Remove-RemoteTask([string]$Target,[string]$TaskName){
  $plainPass = if ($AltPass) { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AltPass)) } else { $null }
  try {
    $del = @("/Delete","/S",$Target,"/TN",$TaskName,"/F")
    if ($AltUser -and $plainPass){ $del = @("/Delete","/S",$Target,"/U",$AltUser,"/P",$plainPass,"/TN",$TaskName,"/F") }
    schtasks @del | Out-Null
  } finally {
    if ($plainPass) { $plainPass = $null }
  }
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
      finally {
        # BUG-FIX: Wait for task to finish before deleting it
        Wait-TaskComplete $fqdn $task
        Remove-RemoteTask $fqdn $task
      }
    }
    finally {
      # BUG-FIX: Wait for task to finish before deleting it
      Wait-TaskComplete $Target $task
      Remove-RemoteTask $Target $task
    }

    if ($ok){ Add-Content $log "OK  $Target : $conn" }
  }
}
Write-Host "Done. Log: $log"
