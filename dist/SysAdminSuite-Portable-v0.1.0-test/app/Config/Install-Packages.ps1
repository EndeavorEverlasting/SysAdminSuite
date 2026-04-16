<#
 Install-Packages.ps1  —  Offline installer runner
 - Reads \\SERVER\SoftwareRepo\packages.csv
 - Verifies SHA-256 in checksums\<InstallerFile>.sha256 (if present)
 - Installs MSI/EXE/ZIP/MSIX machine-scope where applicable
 - Re-runnable; skips already-present packages via DetectType/DetectValue
#>

[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [string]$RepoRoot = "\\LPW003ASI037\C$\SoftwareRepo",
  [switch]$ForceReinstall
)

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Error $msg; exit 2 }
function Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Ok($msg)   { Write-Host $msg -ForegroundColor Green }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

# --- Sanity checks -----------------------------------------------------------
# Clear message if UNC is missing/inaccessible
if (-not $RepoRoot -or $RepoRoot.Trim() -eq "") { Fail "RepoRoot not provided." }
if (-not (Test-Path $RepoRoot)) {
  Fail @"
Software repo UNREACHABLE: $RepoRoot

Fixes:
  • Verify the path (typos, share vs admin share).
  • Ensure the machine is online/VPN.
  • Test creds:  New-PSDrive -Name Z -PSProvider FileSystem -Root '$RepoRoot' -Persist
  • If using admin share (C$), you must be local admin on LPW003ASI037.
"@
}

$PkgCsv = Join-Path $RepoRoot 'packages.csv'
$InstDir = Join-Path $RepoRoot 'installers'
$ChkDir  = Join-Path $RepoRoot 'checksums'

if (-not (Test-Path $PkgCsv)) { Fail "Missing manifest: $PkgCsv" }
if (-not (Test-Path $InstDir)) { Fail "Missing installers folder: $InstDir" }
New-Item -ItemType Directory -Force -Path $ChkDir | Out-Null

# Logs
$LogRoot = "C:\ProgramData\SysAdminSuite\Install"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$Log = Join-Path $LogRoot ("install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
"=== Start $(Get-Date) ===`nRepo: $RepoRoot" | Tee-Object -FilePath $Log

# --- Helpers ----------------------------------------------------------------
function Test-Detect($type,$value){
  switch ($type.ToLower()){
    'productcode' {
      $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
      )
      foreach($p in $paths){
        $hit = Get-ChildItem $p -ErrorAction SilentlyContinue | Where-Object {
          (Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue).PSChildName -eq $value -or
          (Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue).ProductID -eq $value
        }
        if ($hit){ return $true }
      }
      return $false
    }
    'regkey'   { return Test-Path ("Registry::" + $value) }
    'file'     { return Test-Path $value }
    'service'  { return (Get-Service -Name $value -ErrorAction SilentlyContinue) -ne $null }
    'appx'     { return (Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {$_.PackageFamilyName -eq $value}) -ne $null }
    default    { return $false }
  }
}

function Ensure-PathMachine([string]$dir){
  if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path $dir)) { return }
  $current = [Environment]::GetEnvironmentVariable("PATH","Machine")
  if ($current -notlike "*$dir*"){
    [Environment]::SetEnvironmentVariable("PATH",$current + ";" + $dir,"Machine")
  }
}

function Verify-Checksum($file){
  $chk = Join-Path $ChkDir ((Split-Path $file -Leaf) + ".sha256")
  if (-not (Test-Path $chk)) { Warn "No checksum for $(Split-Path $file -Leaf)"; return $true }
  $expected = (Get-Content $chk -Raw).Trim().Split()[0].ToLower()
  $actual = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLower()
  if ($expected -ne $actual) {
    Write-Host "!! SHA256 mismatch for $(Split-Path $file -Leaf)" -ForegroundColor Red
    "!! HASH MISMATCH: $file" | Tee-Object -FilePath $Log -Append
    return $false
  }
  return $true
}

# --- Main -------------------------------------------------------------------
$pkgs = Import-Csv $PkgCsv
if (-not $pkgs -or $pkgs.Count -eq 0) { Fail "packages.csv is empty." }

foreach($pkg in $pkgs){
  $name = $pkg.Name
  $file = Join-Path $InstDir $pkg.InstallerFile
  $type = ($pkg.Type ?? "").ToLower()
  $args = $pkg.SilentArgs
  $detT = $pkg.DetectType
  $detV = $pkg.DetectValue
  $post = $pkg.PostInstall
  $addp = $pkg.AddToPath

  "---- $name ----" | Tee-Object -FilePath $Log -Append

  $present = $false
  if (-not $ForceReinstall) { $present = Test-Detect $detT $detV }

  if ($present) {
    "Detected present: $name ($detT)" | Tee-Object -FilePath $Log -Append
    if ($addp) { Ensure-PathMachine $addp }
    continue
  }

  if (-not (Test-Path $file)) {
    "!! Missing installer file: $file" | Tee-Object -FilePath $Log -Append
    continue
  }

  if (-not (Verify-Checksum $file)) { continue }

  try {
    switch ($type) {
      'msi' {
        $cmd = "msiexec.exe"
        $cli = "/i `"$file`" $args"
      }
      'exe' {
        $cmd = $file
        $cli = $args
      }
      'zip' {
        $dest = "C:\Program Files\" + ($name -replace '[^\w\.-]','')
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Expand-Archive -Path $file -DestinationPath $dest -Force
        $cmd = $null; $cli = $null
      }
      'msix' {
        Add-AppxProvisionedPackage -Online -PackagePath $file -SkipLicense -ErrorAction Stop | Out-Null
        $cmd = $null; $cli = $null
      }
      default { throw "Unknown Type '$type' for $name" }
    }

    if ($cmd) {
      "Installing: $cmd $cli" | Tee-Object -FilePath $Log -Append
      $p = Start-Process -FilePath $cmd -ArgumentList $cli -Wait -PassThru -WindowStyle Hidden
      if ($p.ExitCode -ne 0) { throw "$name exited with $($p.ExitCode)" }
    } else {
      "Applied package content for $name." | Tee-Object -FilePath $Log -Append
    }

    if ($post) {
      "PostInstall: $post" | Tee-Object -FilePath $Log -Append
      cmd.exe /c "$post" | Tee-Object -FilePath $Log -Append
    }

    Start-Sleep -Seconds 2
    if (-not (Test-Detect $detT $detV)) {
      "!! Verification failed for $name" | Tee-Object -FilePath $Log -Append
    } else {
      "Installed OK: $name" | Tee-Object -FilePath $Log -Append
    }

    if ($addp) { Ensure-PathMachine $addp }
  }
  catch {
    "!! Error installing $name : $_" | Tee-Object -FilePath $Log -Append
  }
}

"=== End $(Get-Date) ===" | Tee-Object -FilePath $Log -Append
Ok "Install run complete. Log: $Log"
