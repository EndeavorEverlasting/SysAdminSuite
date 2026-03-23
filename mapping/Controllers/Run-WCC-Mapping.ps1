∩╗┐<# Run-WCC-Mapping.ps1
PS7 ΓåÆ PS5 endpoints. Case-by-case mapping for WCC today.
Assumes the compat mapper is in the same folder:
  .\Map-Remote-MachineWide-Printers.v5Compat.ps1
#>

$ErrorActionPreference = 'Stop'
Set-Location "C:\Users\pa_rperez26\OneDrive - Northwell Health\Desktop\dev\SysAdminSuite\mapping"

# --- Queues (exact, as provided) ---
$Q61 = '\\SWBPNSXPS01V\LS111-WCC61'   # Xerox server
$Q62 = '\\SWBPNSXPS01V\LS111-WCC62'
$Q63 = '\\swbpnsxps01v\LS111-WCC63'
$Q64 = '\\swbpnsxps01v\LS111-WCC64'
$Q65 = '\\SWBPNHPHPS01V\LS111-WCC65'  # HP server
$Q66 = '\\SWBPNHPHPS01V\LS111-WCC66'
$Q67 = '\\SWBPNHPHPS01V\LS111-WCC67'
$Q68 = '\\SWBPNHPHPS01V\LS111-WCC68'

# --- Files ---
$HostsAll = '.\csv\hosts.txt'
$OutDir   = '.\csv\runs'
$Mapper   = '.\Map-Remote-MachineWide-Printers.v5Compat.ps1'  # PS7ΓåÆPS5 compat

# --- Prep ---
if (-not (Test-Path $Mapper)) { throw "Mapper not found: $Mapper" }
$null = New-Item -ItemType Directory -Force -Path $OutDir

# Load and parse host numbers (expects trailing 2ΓÇô3 digit sequence, e.g., WLS111WCC091)
$all = Get-Content $HostsAll | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
$parsed = foreach($h in $all){
  if ($h -match '(\d{2,3})$') { [pscustomobject]@{ Host=$h; Num=[int]$Matches[1] } }
}

# --- Groups for TODAY ---
# OBGYN ΓÇô Check out: 91ΓÇô94 ΓåÆ 67, 62
$obgyn_checkout = $parsed | Where-Object { $_.Num -ge 91 -and $_.Num -le 94 } | Select-Object -ExpandProperty Host
# OBGYN ΓÇô Check in: 79ΓÇô83 ΓåÆ 65, 62
$obgyn_checkin  = $parsed | Where-Object { $_.Num -ge 79 -and $_.Num -le 83 } | Select-Object -ExpandProperty Host
# Breast Surgery ΓÇô Checkout: 24ΓÇô26 ΓåÆ 68, 61
$breast_checkout = $parsed | Where-Object { $_.Num -ge 24 -and $_.Num -le 26 } | Select-Object -ExpandProperty Host
# Breast Surgery ΓÇô Check in: 31ΓÇô34 ΓåÆ 66, 61
$breast_checkin  = $parsed | Where-Object { $_.Num -ge 31 -and $_.Num -le 34 } | Select-Object -ExpandProperty Host

# Persist the exact host lists (audit trail)
$obgyn_checkout  | Set-Content "$OutDir\obgyn_checkout.txt"
$obgyn_checkin   | Set-Content "$OutDir\obgyn_checkin.txt"
$breast_checkout | Set-Content "$OutDir\breast_checkout.txt"
$breast_checkin  | Set-Content "$OutDir\breast_checkin.txt"

# --- Map + Verify (machine-wide /ga) ---
# Tune -MaxParallel to your network; 24ΓÇô48 is usually safe inside LAN.
& $Mapper -HostsPath "$OutDir\obgyn_checkout.txt"  -Queues $Q67,$Q62 -Verify -MaxParallel 32 -Verbose
& $Mapper -HostsPath "$OutDir\obgyn_checkin.txt"   -Queues $Q65,$Q62 -Verify -MaxParallel 32 -Verbose
& $Mapper -HostsPath "$OutDir\breast_checkout.txt" -Queues $Q68,$Q61 -Verify -MaxParallel 32 -Verbose
& $Mapper -HostsPath "$OutDir\breast_checkin.txt"  -Queues $Q66,$Q61 -Verify -MaxParallel 32 -Verbose

Write-Host "`nAll groups processed. Review VERFIY outputs above for each host." -ForegroundColor Green

<# --- Rollback helpers (uncomment and run if needed)
# & $Mapper -HostsPath "$OutDir\obgyn_checkout.txt"  -RemoveQueues $Q67 -Verify -MaxParallel 32 -Verbose
# & $Mapper -HostsPath "$OutDir\obgyn_checkout.txt"  -RemoveQueues $Q62 -Verify -MaxParallel 32 -Verbose
# etcΓÇª
#>