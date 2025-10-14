<#  push.ps1
    Purpose: unblock -> branch -> commit -> push (portable, no-main)
#>

[CmdletBinding()]
param(
  # Optional: pass a custom name; otherwise we generate a mapping/fetchmap slug
  [string]$BranchName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 0) Find repo root (works from any subfolder) ---
function Get-RepoRoot {
  try {
    $root = (git rev-parse --show-toplevel) 2>$null
    if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
    if (-not (Test-Path $root)) { throw "Repo root not found." }
    return $root
  } catch {
    throw "Not a git repo. ($_)"
  }
}
$Root = Get-RepoRoot
Set-Location $Root

# --- 1) Unblock downloaded files (ADS: Zone.Identifier) ---
function Unblock-All {
  param([string]$Path)
  Write-Host "Unblocking files under: $Path"
  Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -Path $_.FullName -ErrorAction Stop } catch {}
  }
  # Belt-and-suspenders: remove any leftover Zone.Identifier streams
  $streams = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
             ForEach-Object { Get-Item $_.FullName -Stream * -ErrorAction SilentlyContinue } |
             Where-Object Stream -eq 'Zone.Identifier'
  foreach ($s in $streams) {
    try { Remove-Item -Path $s.FileName -Stream Zone.Identifier -Force -ErrorAction Stop } catch {}
  }
}
Unblock-All -Path $Root

# --- 2) Decide branch name (never main) ---
if (-not $BranchName -or [string]::IsNullOrWhiteSpace($BranchName)) {
  $BranchName = "feat/mapping-fetchmap-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmm')
}
Write-Host "Target branch: $BranchName"

# --- 1b) Ensure .gitattributes and .gitignore are in place ---
$gitAttrPath  = Join-Path $Root ".gitattributes"
$gitIgnorePath = Join-Path $Root ".gitignore"

# Create or repair .gitattributes
$gitattributes = @"
* text=auto
*.ps1  text eol=crlf
*.psm1 text eol=crlf
*.cmd  text eol=crlf
*.md   text eol=lf
*.csv  text eol=lf
"@
if (-not (Test-Path $gitAttrPath) -or -not (Select-String -Quiet "ps1" $gitAttrPath)) {
    $gitattributes | Set-Content $gitAttrPath -Encoding UTF8 -NoNewline
    Write-Host "Created or refreshed .gitattributes"
    git add .gitattributes
}

# Create or patch .gitignore
$ignoreRules = @"
# runtime artifacts
mapping/logs/
config/exports/
*.log
.vscode/
"@
if (-not (Test-Path $gitIgnorePath) -or -not (Select-String -Quiet "mapping/logs" $gitIgnorePath)) {
    $ignoreRules | Add-Content $gitIgnorePath -Encoding UTF8
    Write-Host "Created or refreshed .gitignore"
    git add .gitignore
}

# Optionally untrack already-committed logs/exports (safe to re-run)
try {
    git rm -r --cached mapping/logs config/exports 2>$null
} catch {}


# --- 3) Stage + commit if there are changes ---
git status --porcelain | Out-Null
$hasChanges = $LASTEXITCODE -eq 0 -and (git status --porcelain)  # non-empty if changes

if ($hasChanges) {
  git add -A
  # Only commit if diff isn't empty (avoid noisy empty commits)
  if (-not (git diff --cached --quiet)) {
    git commit -m "feat(mapping,config): WIP snapshot (printer mapping + fetchmap install scaffolding)"
  }
} else {
  Write-Host "No changes detected. Will just branch & push (if needed)." -ForegroundColor Yellow
}

# --- 4) Create/switch branch safely ---
# If local branch exists, switch; else create from current HEAD.
$localExists = (git branch --list $BranchName) -ne $null -and (git branch --list $BranchName).Trim()
if ($localExists) {
  git switch $BranchName
} else {
  git switch -c $BranchName
}

# --- 5) Push and set upstream (idempotent) ---
# If remote exists, regular push; else push -u
$remoteExists = (git ls-remote --heads origin $BranchName) -ne $null -and `
                ((git ls-remote --heads origin $BranchName) -match $BranchName)
if ($remoteExists) {
  git push
} else {
  git push -u origin $BranchName
}

Write-Host "Done. Branch is ready: $BranchName" -ForegroundColor Green
Write-Host "Next: open PR against your integration branch (not main). Example:" -ForegroundColor Cyan
Write-Host "  gh pr create --base LPW003ASI037-Repo --head $BranchName --title `"Mapping + FetchMap WIP`""
