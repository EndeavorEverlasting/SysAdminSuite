# --- derive variables from repo (no manual version edits) ---
Set-Location 'C:\Users\Cheex\Desktop\dev\config\github\SysAdminSuite'

# Get repo URL (fallback to your known URL if no remote yet)
$REPO_URL = (git config --get remote.origin.url 2>$null)
if (-not $REPO_URL) { $REPO_URL = 'https://github.com/your-username/SysAdminSuite.git' }

# Read version from version_manager.py: supports VERSION="1.2.3" OR __version__="1.2.3"
$main = Get-Content .\version_manager.py -Raw
$verMatch = [regex]::Match($main, '(?m)^(?:__version__|VERSION)\s*=\s*["''](?<v>\d+\.\d+\.\d+)["'']')
if (-not $verMatch.Success) { throw "Could not find VERSION or __version__ = 'X.Y.Z' in version_manager.py" }
$SemVer  = $verMatch.Groups['v'].Value
$VERSION = "v$SemVer"                  # tag name (with "v" prefix)
$BRANCH_PREFIX = 'release'             # change to dev/prod as needed
$BRANCH        = "$BRANCH_PREFIX/$VERSION"

# Build a sensible commit/tag message
$MSG = "Release $VERSION (auto from version_manager.py): SysAdminSuite IT tools collection"
# ------------------------------------------------------------

# go to your project
Set-Location 'C:\Users\Cheex\Desktop\dev\config\github\SysAdminSuite'

# pre-flight: ensure git author is configured
$gitUserName  = (git config user.name 2>$null)
$gitUserEmail = (git config user.email 2>$null)
if ([string]::IsNullOrWhiteSpace($gitUserName) -or $gitUserName -match 'unknown' -or [string]::IsNullOrWhiteSpace($gitUserEmail) -or $gitUserEmail -match 'unknown') {
  Write-Warning "Git user.name and/or user.email is not set (or is 'unknown')."
  Write-Host "Set them globally to avoid anonymous commits:" -ForegroundColor Yellow
  Write-Host "  git config --global user.name `"Your Name`"" -ForegroundColor DarkYellow
  Write-Host "  git config --global user.email `"you@example.com`"" -ForegroundColor DarkYellow
  $proceed = Read-Host "Continue anyway? [y/N]"
  if ($proceed -notin @('y','Y','yes','YES')) {
    Write-Host "Aborting. Configure your Git identity and re-run the script." -ForegroundColor Red
    exit 1
  }
}

# create a privacy-friendly .gitignore if one doesn't exist
if (-not (Test-Path .gitignore)) {
@"
# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
.env
.env.*
*.env

# IDE/OS
.vscode/
.idea/
.DS_Store
Thumbs.db

# Local data that may contain sensitive info
logs/
reports/
*.log

# Windows specific
*.exe
*.msi
*.tmp
*.bak

# IT tools specific
configs/backups/
installs/temp/
tests/results/
"@ | Out-File -Encoding utf8 .gitignore
}

# quick preflight scan for secrets (optional)
Write-Host "Scanning for potential secrets..." -ForegroundColor Yellow
Select-String -Path (Get-ChildItem -Recurse -File | Where-Object { $_.FullName -notmatch '\\.git\\' }).FullName `
  -Pattern 'password|secret|api[_-]?key|token|bearer\s+[a-z0-9._-]+|BEGIN (RSA|OPENSSH) PRIVATE KEY' `
  -AllMatches -CaseSensitive:$false | Select-Object Path, LineNumber, Line | Format-List

# init git (safe to re-run)
git init

# connect the remote named 'origin' to the GitHub repo
git remote remove origin 2>$null
git remote add origin $REPO_URL

# discover the default branch on the remote (fallback to 'main')
$defaultBranch = 'main'
try {
  $remoteInfo = git remote show origin 2>&1
  $headMatch = ($remoteInfo | Select-String -Pattern 'HEAD branch:\s*(\S+)')
  if ($headMatch) {
    $defaultBranch = $headMatch.Matches[0].Groups[1].Value
  }
} catch {
  Write-Host "Could not determine default branch, using 'main'" -ForegroundColor Yellow
}

Write-Host "Using default branch: $defaultBranch" -ForegroundColor Green

# add all files (except .gitignore patterns)
git add .

# check if there are changes to commit
$status = git status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
  Write-Host "No changes to commit. Repository is up to date." -ForegroundColor Green
  exit 0
}

# commit with the auto-generated message
Write-Host "Committing changes with message: $MSG" -ForegroundColor Yellow
git commit -m $MSG

# push to the default branch
Write-Host "Pushing to $defaultBranch..." -ForegroundColor Yellow
git push -u origin $defaultBranch

# create and push the version tag
Write-Host "Creating and pushing tag: $VERSION" -ForegroundColor Yellow
git tag -a $VERSION -m "Release $VERSION: SysAdminSuite IT tools collection"
git push origin $VERSION

Write-Host "`nSuccessfully uploaded SysAdminSuite v$SemVer to GitHub!" -ForegroundColor Green
Write-Host "Repository: $REPO_URL" -ForegroundColor Cyan
Write-Host "Tag: $VERSION" -ForegroundColor Cyan
Write-Host "Branch: $defaultBranch" -ForegroundColor Cyan
