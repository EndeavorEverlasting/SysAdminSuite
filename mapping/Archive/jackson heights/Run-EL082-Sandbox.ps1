# Creates .\sandbox\<HOST>\C$\... locally and simulates the full deploy+map
$hosts = @(
  'WEL082MST051','WEL082MST055','WEL082MST057','WEL082MST058',
  'WEL082MST061','WEL082MST063','WEL082MST066','WEL082MST067'
)

$root = "$PSScriptRoot\sandbox"
New-Item -ItemType Directory -Path $root -Force | Out-Null

# BUG-FIX: Use $PSScriptRoot-rooted path so the script always resolves correctly
& "$PSScriptRoot\Publish-EL082-Pack-Sandbox.ps1" `
  -ComputerName $hosts `
  -PrintersCsv "$PSScriptRoot\EL082_el082_printers.csv" `
  -DefaultsCsv "$PSScriptRoot\EL082_el082_defaults.csv" `
  -MapScript   "$PSScriptRoot\Map-EL082-MachineWide.ps1" `
  -UserVbs     "$PSScriptRoot\Set-EL082-Default-FromCSV.vbs" `
  -MapNow -InstallDefaultAtLogon `
  -SandboxRoot $root `
  -PauseAtEnd
