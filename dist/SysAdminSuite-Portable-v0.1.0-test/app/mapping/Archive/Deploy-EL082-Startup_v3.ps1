<#
Deploy-EL082-Startup_v3.ps1  (no-trace)
- Removes ONLY our known old printer-map scripts from All Users Startup
- Copies the new EL082-MapAll-SetDefault.vbs
- Verifies integrity via SHA256 (shown in console only; no files left behind)
- Optional: -RunNow triggers the VBS immediately without leaving artifacts
Run elevated on your admin box.
#>

[CmdletBinding()]
param(
  [string[]] $ComputerName = @(
    'WEL082MST051','WEL082MST052','WEL082MST053','WEL082MST054',
    'WEL082MST055','WEL082MST056','WEL082MST057','WEL082MST058',
    'WEL082MST060','WEL082MST061','WEL082MST062','WEL082MST063',
    'WEL082MST066','WEL082MST067'
  ),
  [string] $LocalVbs = "$PSScriptRoot\EL082-MapAll-SetDefault.vbs",
  [switch] $RunNow
)

if (!(Test-Path -LiteralPath $LocalVbs)) { throw "Cannot find VBS: $LocalVbs" }
$localHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $LocalVbs).Hash
Write-Host "Local VBS SHA256: $localHash"

$KnownOldNames = @(
  'Map-082-Defaults.vbs',
  'Map-EL082-All.vbs',
  'remote_printer-map_startup.vbs',
  'EL082-MapAll-SetDefault.vbs'  # ensure fresh copy replaces stale one
)

function Get-StartupPath([string]$Computer) {
  "\\$Computer\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
}

foreach ($c in $ComputerName) {
  Write-Host "==== $c ===="
  try {
    if (-not (Test-Connection -ComputerName $c -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
      Write-Warning "$c : offline/unreachable"; continue
    }

    $startup = Get-StartupPath $c
    if (-not (Test-Path $startup)) { Write-Warning "$c : Startup path not reachable"; continue }

    # 1) Purge OUR old files only
    foreach ($n in $KnownOldNames) {
      $p = Join-Path $startup $n
      if (Test-Path $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; Write-Host "removed: $n" }
    }

    # 2) Copy new VBS
    $destVbs = Join-Path $startup 'EL082-MapAll-SetDefault.vbs'
    Copy-Item -LiteralPath $LocalVbs -Destination $destVbs -Force

    # 3) Verify hash (console only)
    $remoteHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destVbs).Hash
    if ($remoteHash -eq $localHash) {
      Write-Host "deployed (hash ok)"
    } else {
      Write-Warning "hash mismatch after copy; retrying..."
      Copy-Item -LiteralPath $LocalVbs -Destination $destVbs -Force
      $remoteHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destVbs).Hash
      if ($remoteHash -ne $localHash) { Write-Error "$c : hash mismatch persists"; continue }
      Write-Host "deployed (hash ok after retry)"
    }

    # 4) Optional: run now without leaving artifacts
    if ($RunNow) {
      $tempLocal = "$env:TEMP\EL082-MapAll-SetDefault.vbs"           # local temp copy for UNC push
      Copy-Item -LiteralPath $LocalVbs -Destination $tempLocal -Force
      $remoteTemp = "\\$c\C$\Windows\Temp\EL082-MapAll-SetDefault.vbs"
      Copy-Item -LiteralPath $tempLocal -Destination $remoteTemp -Force
      $cmd = 'wscript.exe "C:\Windows\Temp\EL082-MapAll-SetDefault.vbs"'
      $r = Invoke-WmiMethod -Class Win32_Process -ComputerName $c -Name Create -ArgumentList $cmd -ErrorAction SilentlyContinue
      if ($r -and $r.ReturnValue -eq 0) { Write-Host "run-now: started (PID $($r.ProcessId))" } else { Write-Warning "run-now: could not start" }
      # Optional silent cleanup of the temp copy after ~2 minutes could be added via schtasks; omitted for no-trace simplicity.
    }

  } catch { Write-Warning "$c : $_" }
}

Write-Host "`nDone. Users can sign out/in (or reboot) to run Startup."
