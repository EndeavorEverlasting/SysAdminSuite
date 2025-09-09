<#
 Deploy two shortcuts to Public Desktop on WLS111WCC001-164
 Source share: \\LPW003ASI037\C$\Shortcuts

 Logging (created under C:\ShortcutDeployLogs):
   - DeployShortcuts_*.txt  (human-readable log)
   - DeployShortcuts_*.csv  (structured per-host per-file)
   - Transcript_*.txt       (full console transcript)

 Design / future-proofing notes:
   - Username is fixed below; password is prompted every run (changes daily).
   - Uses net.exe for SMB auth; handles multiple-connection errors (1219/3775).
   - Detects 1326 (bad password), re-prompts ONCE globally, then retries.
   - Never overwrites existing files. If present and different, logs EXISTS_DIFFERENT.
   - If present and identical (hash match), logs UPTODATE and skips.
   - ASCII-only punctuation to avoid encoding parse issues.
   - Avoids $host automatic variable; uses $targetHost, $hostName, etc.
#>

param(
  [string]$SourceDir = "\\LPW003ASI037\C$\Shortcuts",
  [string]$Prefix    = "WLS111WCC",
  [int]   $StartNum  = 1,
  [int]   $EndNum    = 164,
  [string[]]$ComputerList,  # optional explicit list; overrides prefix/range
  [switch]$WhatIf
)

Set-StrictMode -Version Latest

# ---------- logging setup ----------
$ts      = Get-Date -Format "yyyyMMdd_HHmmss"
$logRoot = Join-Path $env:SystemDrive "ShortcutDeployLogs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$logTxt  = Join-Path $logRoot "DeployShortcuts_$ts.txt"
$logCsv  = Join-Path $logRoot "DeployShortcuts_$ts.csv"
$trans   = Join-Path $logRoot "Transcript_$ts.txt"

function LogLine([string]$msg) {
  $stamp = "[{0}]" -f (Get-Date)
  Write-Host "$stamp $msg"
  "$stamp $msg" | Out-File $logTxt -Append -Encoding UTF8
}
function CsvLog($hostName,$file,$status,$detail) {
  # escape internal quotes for CSV safety
  $safeDetail = ($detail -replace '"','""')
  $line = ('{0},{1},"{2}",{3},"{4}"' -f (Get-Date).ToString("s"), $hostName, $file, $status, $safeDetail)
  $line | Out-File $logCsv -Append -Encoding UTF8
}
"Time,Hostname,File,Status,Detail" | Out-File $logCsv -Encoding UTF8

# ---------- SMB credentials (daily password) ----------
# Username is static; password is prompted each run. We convert it to plain
# to pass to net.exe, and we clear the variable in finally.
$SmbUser = "pa_rperez26@nslijhs.net"
$plainPass = $null
$bstr = [IntPtr]::Zero
try {
  $securePass = Read-Host -AsSecureString -Prompt ("Enter password for {0}" -f $SmbUser)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
  $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  $securePass = $null
}

# Track whether we already re-prompted once for 1326
$script:DidGlobalPasswordRetry = $false

# ---------- helpers ----------
function Get-SafeHash([string]$path) {
  try { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } catch { $null }
}
function DestReachable([string]$uncPath) {
  try { Test-Path -LiteralPath $uncPath } catch { $false }
}
function Test-Port445([string]$targetName) {
  try { Test-NetConnection -ComputerName $targetName -Port 445 -InformationLevel Quiet } catch { $false }
}

# Track hosts we authenticated to so we can clean them up.
$script:ConnectedHosts = @()

function Invoke-NetUseIpc([string]$targetHost, [string]$password, [string]$user) {
  # Returns @{ ExitCode = int; Output = string }
  $args = @("use", "\\$targetHost\IPC$", $password, "/user:$user", "/persistent:no")
  $output = & net.exe $args 2>&1
  $code = $LASTEXITCODE
  return @{ ExitCode = $code; Output = ($output -join "`n") }
}

function Remove-NetUse([string]$targetHost) {
  try {
    $args = @("use", "\\$targetHost\IPC$", "/delete", "/y")
    & net.exe $args 2>&1 | Out-Null
  } catch { }
}

function Prompt-For-NewPassword() {
  # One global retry if the first password was wrong (1326).
  $global:bstr2 = [IntPtr]::Zero
  try {
    $sec = Read-Host -AsSecureString -Prompt "Password appears incorrect (1326). Enter password again"
    $global:bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $newPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($global:bstr2)
  } finally {
    if ($global:bstr2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($global:bstr2) }
  }
  return $newPlain
}

function Ensure-SmbAuth([string]$targetHost) {
  if ($script:ConnectedHosts -contains $targetHost) { return $true }

  # First attempt with current password
  $try1 = Invoke-NetUseIpc -targetHost $targetHost -password $plainPass -user $SmbUser
  if ($try1.ExitCode -eq 0) {
    $script:ConnectedHosts += $targetHost
    return $true
  }

  $out1 = $try1.Output

  # If 1326, re-prompt ONCE globally and retry
  if (-not $script:DidGlobalPasswordRetry -and ($out1 -match '1326|Logon failure|The user name or password is incorrect')) {
    $script:DidGlobalPasswordRetry = $true
    $newPass = Prompt-For-NewPassword
    if ($newPass) { $script:plainPass = $newPass }
    $try1b = Invoke-NetUseIpc -targetHost $targetHost -password $plainPass -user $SmbUser
    if ($try1b.ExitCode -eq 0) {
      $script:ConnectedHosts += $targetHost
      return $true
    } else {
      LogLine ("NET USE failed after password retry for \\{0}\IPC$ (exit {1}): {2}" -f $targetHost, $try1b.ExitCode, $try1b.Output)
      CsvLog $targetHost "" "AUTH_BADPASS" $try1b.Output
      return $false
    }
  }

  # Handle multiple-connection errors (1219 or message indicates multiple connections)
  if ($out1 -match 'Multiple connections|1219|3775') {
    Remove-NetUse -targetHost $targetHost
    Start-Sleep -Milliseconds 200
    $try2 = Invoke-NetUseIpc -targetHost $targetHost -password $plainPass -user $SmbUser
    if ($try2.ExitCode -eq 0) {
      $script:ConnectedHosts += $targetHost
      return $true
    } else {
      LogLine ("NET USE retry after 1219/3775 failed for \\{0}\IPC$ (exit {1}): {2}" -f $targetHost, $try2.ExitCode, $try2.Output)
      CsvLog $targetHost "" "AUTH_FAIL" $try2.Output
      return $false
    }
  }

  # Generic auth failure
  LogLine ("NET USE failed for \\{0}\IPC$ (exit {1}): {2}" -f $targetHost, $try1.ExitCode, $out1)
  CsvLog $targetHost "" "AUTH_FAIL" $out1
  return $false
}

# ---------- main ----------
$oldEAP = $ErrorActionPreference
$ErrorActionPreference = 'Stop'

try {
  Start-Transcript -Path $trans -Force | Out-Null
  LogLine ("Deployment started as {0} from {1} | PS {2}" -f $env:USERNAME, $env:COMPUTERNAME, $PSVersionTable.PSVersion)
  LogLine ("SourceDir: {0}" -f $SourceDir)

  # Determine actual source files by label and allowed extensions
  $want = @(
    @{ Label = 'Nuance Powershare' ; Patterns = @('Nuance Powershare*.lnk','Nuance Powershare*.url','Nuance Powershare*.website') },
    @{ Label = 'Welcome to Cerner' ; Patterns = @('Welcome to Cerner*.lnk','Welcome to Cerner*.url','Welcome to Cerner*.website') }
  )

  $filesToCopy = @()
  foreach ($w in $want) {
    $found = $null
    foreach ($p in $w.Patterns) {
      $found = Get-ChildItem -LiteralPath $SourceDir -Filter $p -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { break }
    }
    if ($found) {
      LogLine ("FOUND source for '{0}': {1} ({2} bytes)" -f $w.Label, $found.Name, $found.Length)
      $filesToCopy += $found
    } else {
      LogLine ("MISSING source for '{0}' in {1} (skipping this item for all targets)" -f $w.Label, $SourceDir)
      CsvLog "" $w.Label "MISSING_SOURCE" ("No matching files in {0}" -f $SourceDir)
    }
  }

  if ($filesToCopy.Count -eq 0) {
    LogLine "No source files discovered. Aborting."
    return
  }

  # Build target list from explicit ComputerList or prefix + numeric range
  $targets = if ($ComputerList -and $ComputerList.Count -gt 0) {
    $ComputerList
  } else {
    ($StartNum..$EndNum | ForEach-Object { "{0}{1:D3}" -f $Prefix, $_ })
  }

  # Stats to summarize at the end
  $stats = [ordered]@{
    Success         = 0
    Fail            = 0
    Offline         = 0
    SmbBlocked      = 0
    AccessDenied    = 0
    MissingSource   = 0
    UpToDate        = 0
    ExistsDifferent = 0
  }

  foreach ($target in $targets) {
    $destShare     = "\\$target\C$"
    $publicDesktop = Join-Path $destShare "Users\Public\Desktop"

    LogLine ("Checking {0}..." -f $target)

    # 1) port 445 reachable?
    if (-not (Test-Port445 $target)) {
      LogLine ("SMB port 445 not reachable on {0} (offline or firewall)." -f $target)
      CsvLog $target "" "SMB_UNREACHABLE" "Port 445 closed or host offline"
      $stats.SmbBlocked++
      continue
    }

    # 2) authenticate to IPC$
    if (-not (Ensure-SmbAuth $target)) {
      LogLine ("Auth failed for {0}; skipping." -f $target)
      $stats.Fail++
      continue
    }

    # 3) verify admin share access
    $adminShareOk = DestReachable $publicDesktop
    if (-not $adminShareOk) {
      try { Get-ChildItem -LiteralPath $publicDesktop | Out-Null } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Access is denied|denied by the server') {
          LogLine ("ACCESS DENIED to {0}" -f $publicDesktop)
          CsvLog $target "" "ACCESS_DENIED" $msg
          $stats.AccessDenied++
          continue
        } else {
          LogLine ("DEST PATH NOT FOUND or other error at {0} : {1}" -f $publicDesktop, $msg)
          CsvLog $target "" "DEST_NOT_FOUND" $msg
          $stats.Fail++
          continue
        }
      }
    }

    # 4) per-file copy logic (never overwrite)
    foreach ($srcInfo in $filesToCopy) {
      $fileName = $srcInfo.Name
      $srcPath  = $srcInfo.FullName
      $dstPath  = Join-Path $publicDesktop $fileName

      # destination exists? compare hashes, then skip
      $dstExists = Test-Path -LiteralPath $dstPath
      if ($dstExists) {
        $srcHash = Get-SafeHash $srcPath
        $dstHash = Get-SafeHash $dstPath
        if ($srcHash -and $dstHash -and ($srcHash -eq $dstHash)) {
          LogLine ("UPTODATE on {0} : {1}" -f $target, $fileName)
          CsvLog $target $fileName "UPTODATE" $dstPath
          $stats.UpToDate++
          continue
        } else {
          LogLine ("EXISTS but different on {0} : {1} - left untouched" -f $target, $fileName)
          CsvLog $target $fileName "EXISTS_DIFFERENT" "Present and differs; not overwritten"
          $stats.ExistsDifferent++
          continue
        }
      }

      # copy only if not present
      try {
        if ($WhatIf) {
          Copy-Item -LiteralPath $srcPath -Destination $publicDesktop -Force -WhatIf -ErrorAction Stop
          LogLine ("WHATIF: Would copy {0} to {1}" -f $fileName, $target)
          CsvLog $target $fileName "WHATIF" $dstPath
        } else {
          Copy-Item -LiteralPath $srcPath -Destination $publicDesktop -Force -ErrorAction Stop

          if (Test-Path -LiteralPath $dstPath) {
            # optional hash verification
            $srcHash = Get-SafeHash $srcPath
            $vHash   = Get-SafeHash $dstPath
            if ($srcHash -and $vHash -and ($srcHash -ne $vHash)) {
              LogLine ("VERIFY MISMATCH on {0} : {1} (hash differs after copy)" -f $target, $fileName)
              CsvLog $target $fileName "VERIFY_FAIL" "Hash mismatch after copy"
              $stats.Fail++
            } else {
              LogLine ("SUCCESS: Copied {0} to {1}" -f $fileName, $target)
              CsvLog $target $fileName "SUCCESS" $dstPath
              $stats.Success++
            }
          } else {
            LogLine ("ERROR: Copy reported success but file missing on {0} : {1}" -f $target, $fileName)
            CsvLog $target $fileName "ERROR" "Missing after copy"
            $stats.Fail++
          }
        }
      } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'cannot find path' -and -not (Test-Path -LiteralPath $srcPath)) {
          LogLine ("SOURCE MISSING: {0}" -f $srcPath)
          CsvLog $target $fileName "MISSING_SOURCE" $srcPath
          $stats.MissingSource++
        } else {
          LogLine ("ERROR: Failed to copy {0} to {1} : {2}" -f $fileName, $target, $msg)
          CsvLog $target $fileName "ERROR" $msg
          $stats.Fail++
        }
      }
    } # end per-file
  }   # end per-target

  # ---------- summary ----------
  $summary = ("Summary => Success: {0} | Fail: {1} | UpToDate: {2} | ExistsDifferent: {3} | SMB Blocked: {4} | AccessDenied: {5} | MissingSource: {6}" -f `
    $stats.Success, $stats.Fail, $stats.UpToDate, $stats.ExistsDifferent, $stats.SmbBlocked, $stats.AccessDenied, $stats.MissingSource)
  LogLine $summary
  LogLine ("Deployment completed {0}" -f (Get-Date))

} finally {
  try { Stop-Transcript | Out-Null } catch { }
  $ErrorActionPreference = $oldEAP

  foreach ($h in ($script:ConnectedHosts | Select-Object -Unique)) {
    Remove-NetUse -targetHost $h
  }

  if ($plainPass) { $plainPass = $null }
}

Write-Host ""
Write-Host "Logs:"
Write-Host ("  Text:       " + $logTxt)
Write-Host ("  CSV:        " + $logCsv)
Write-Host ("  Transcript: " + $trans)
