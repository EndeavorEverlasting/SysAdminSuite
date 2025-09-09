<#
.SYNOPSIS
  Safe "push current repo" helper with:
    - Auto-branch (from main → perf/debug-<timestamp>) when there are changes
    - Large-file warning (or blocking) before commit
    - Standard add/commit/push flow + optional tag push

.PARAMETER RepoPath
  Path to a Git working tree. Defaults to current location.

.PARAMETER Message
  Commit message. Defaults to "Update: <timestamp>".

.PARAMETER AllowEmpty
  Commit even if there are no changes.

.PARAMETER Tag
  If present, create a tag (auto-named) and push it.

.PARAMETER TagName
  Explicit tag name to create and push.

.PARAMETER AllowOnMain
  Allow committing directly to main/master even when there are changes.
  If not specified and you're on main/master with changes, a perf/debug branch is auto-created.

.PARAMETER AutoBranchPrefix
  Prefix for auto-created branches when protecting main/master. Default: "perf/debug".

.PARAMETER ThresholdMB
  Warn when staged files exceed this size (per-file). Default: 10 MB.

.PARAMETER BlockOnLarge
  If supplied, abort the run when any staged file exceeds ThresholdMB.

.EXAMPLE
  .\env_setup\_future-pushes.ps1 -Message "Sync before moving to fast box"

.EXAMPLE
  .\env_setup\_future-pushes.ps1 -AllowOnMain -Message "Hotfix on main"

.EXAMPLE
  .\env_setup\_future-pushes.ps1 -Tag -Message "Cut build" -ThresholdMB 25
#>

param(
  [string]$RepoPath = (Get-Location).Path,
  [string]$Message,
  [switch]$AllowEmpty,
  [switch]$Tag,
  [string]$TagName,
  [switch]$AllowOnMain,
  [string]$AutoBranchPrefix = "perf/debug",
  [int]$ThresholdMB = 10,
  [switch]$BlockOnLarge
)

# --- Guardrails: git present ---
try { Get-Command git -ErrorAction Stop | Out-Null } catch {
  Write-Error "git not found on PATH."; exit 1
}

# Utility: tiny helper to run git and capture trimmed output
function Invoke-Git([string[]]$Args) {
  $out = & git @Args
  if ($LASTEXITCODE -ne 0) { throw "git $Args failed (exit $LASTEXITCODE)" }
  return ($out | Out-String).Trim()
}

# Utility: pretty status message
function Info($msg)  { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Warn($msg)  { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Good($msg)  { Write-Host "[✓] $msg" -ForegroundColor Green }
function Bad($msg)   { Write-Host "[x] $msg" -ForegroundColor Red }

Push-Location $RepoPath
try {
  # --- Validate repo & location ---
  $inside = (& git rev-parse --is-inside-work-tree 2>$null).Trim()
  if ($inside -ne 'true') { throw "Not a git repo: $RepoPath" }

  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if (-not $branch) { throw "Couldn't determine current branch." }

  # Pick a remote, default to 'origin' if none configured
  $remote = ((& git remote) | Select-Object -First 1)
  if (-not $remote) { $remote = 'origin' }

  Info "Repo: $RepoPath"
  Info "Branch: $branch  Remote: $remote"

  # --- Stage changes (adds/edits/deletes) ---
  & git add -A
  $changes = (& git status --porcelain)

  # If protecting main/master: auto-create a debug branch on change
  $isProtected = @('main', 'master') -contains $branch
  if ($isProtected -and (-not $AllowOnMain) -and $changes) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $newBranch = "$AutoBranchPrefix-$stamp"
    Warn "Protected branch '$branch' with changes detected → creating '$newBranch'."
    & git checkout -b $newBranch | Out-Null
    $branch = $newBranch
    Good "Switched to '$branch'."
  }

  # --- Large-file gate (staged files only) ---
  # After 'git add -A', check names staged for commit
  $staged = (& git diff --cached --name-only -z) -split ([char]0) | Where-Object { $_ -ne "" }

  $thresholdBytes = [int64]$ThresholdMB * 1MB
  $bigOnes = @()

  foreach ($p in $staged) {
    # Deleted files won't exist on disk; skip those gracefully
    if (Test-Path -LiteralPath $p) {
      try {
        $size = (Get-Item -LiteralPath $p).Length
        if ($size -ge $thresholdBytes) {
          $bigOnes += [PSCustomObject]@{ Path = $p; SizeMB = [Math]::Round($size / 1MB, 2) }
        }
      } catch { }
    }
  }

  if ($bigOnes.Count -gt 0) {
    Warn "Large staged file(s) detected (≥ $ThresholdMB MB):"
    $bigOnes | ForEach-Object { Write-Host ("   - {0}  ({1} MB)" -f $_.Path, $_.SizeMB) -ForegroundColor Yellow }
    Warn "Consider Git LFS for binaries:  winget install Git.GitLFS; git lfs install; git lfs track \"*.msi\" \"*.exe\" \"*.zip\""

    if ($BlockOnLarge) {
      Bad "Blocking push due to large files. Re-run with -BlockOnLarge:$false or track with LFS."
      exit 2
    }
  }

  # --- Commit phase ---
  if (-not $changes -and -not $AllowEmpty) {
    Info "No changes to commit in '$RepoPath'."
    return
  }

  if (-not $Message) { $Message = "Update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }
  & git commit --allow-empty -m $Message | Out-Null
  Good "Committed: $Message"

  # --- Push phase (set upstream if needed) ---
  & git rev-parse --abbrev-ref --symbolic-full-name "@{u}" *> $null
  if ($LASTEXITCODE -ne 0) {
    Info "Setting upstream: $remote $branch"
    & git push -u $remote $branch
  } else {
    & git push
  }
  Good "Pushed '$branch' → '$remote'."

  # --- Optional tag push ---
  if ($Tag -or $TagName) {
    if (-not $TagName) { $TagName = "v$(Get-Date -Format yyyy.MM.dd.HHmmss)" }
    & git tag $TagName
    & git push $remote $TagName
    Good "Pushed tag '$TagName'."
  }
}
finally {
  Pop-Location
}
