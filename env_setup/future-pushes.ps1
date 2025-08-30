param(
  [string]$RepoPath = (Get-Location).Path,
  [string]$Message,
  [switch]$AllowEmpty,
  [switch]$Tag,
  [string]$TagName
)

# Ensure git exists
try { Get-Command git -ErrorAction Stop | Out-Null } catch {
  Write-Error "git not found on PATH."; exit 1
}

Push-Location $RepoPath
try {
  # Validate repo
  $inside = (& git rev-parse --is-inside-work-tree 2>$null).Trim()
  if ($inside -ne 'true') { throw "Not a git repo: $RepoPath" }

  # Branch / remote
  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if (-not $branch) { throw "Couldn't determine current branch." }
  $remote = ((& git remote) | Select-Object -First 1); if (-not $remote) { $remote = 'origin' }

  # Stage changes (adds/edits/deletes)
  & git add -A

  # Commit only if there are changes unless -AllowEmpty
  $changes = (& git status --porcelain)
  if (-not $changes -and -not $AllowEmpty) {
    Write-Host "No changes to commit in '$RepoPath'."
    return
  }

  if (-not $Message) { $Message = "Update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }
  & git commit --allow-empty -m $Message

  # First push sets upstream
  & git rev-parse --abbrev-ref --symbolic-full-name "@{u}" *> $null
  if ($LASTEXITCODE -ne 0) { & git push -u $remote $branch } else { & git push }

  if ($Tag -or $TagName) {
    if (-not $TagName) { $TagName = "v$(Get-Date -Format yyyy.MM.dd.HHmmss)" }
    & git tag $TagName
    & git push $remote $TagName
  }

  Write-Host "Pushed '$branch' to '$remote'." -ForegroundColor Green
}
finally {
  Pop-Location
}
