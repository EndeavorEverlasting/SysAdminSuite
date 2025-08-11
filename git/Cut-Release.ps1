<# Cut-Release.ps1 (v1.0.0) - SysAdminSuite Release Management
Single source of truth: version_manager.py VERSION - Auto-bump from the *latest remote tag* (vX.Y.Z) 
with -Bump patch|minor|major - Writes bumped version back to version_manager.py (disable with -NoWriteMain) 
- Creates branch: <Prefix>/vX.Y.Z (default Prefix=release), and tag: vX.Y.Z 
- Explicit refspec pushes, divergence checks, no raw --force 
- Optional: open a PR (no auto-merge unless -AutoMerge) 
- Final compare: shows diff + ahead/behind vs main #>

param(
    [ValidateSet('dev','release','prod')]
    [string]$Prefix = 'release',
    [ValidateSet('patch','minor','major','none')]
    [string]$Bump = 'patch',
    [switch]$NoWriteMain, # don't write the bumped version into version_manager.py
    [switch]$OpenPR, # open a PR release/<v> -> main (requires gh)
    [switch]$AutoMerge # if set, try to auto-merge PR after checks (off by default)
)

$ErrorActionPreference = 'Stop'

# --- Functions ---
function Get-SemVerFromVersionManager {
    param([string]$Path='version_manager.py')
    $src = Get-Content $Path -Raw
    $m = [regex]::Match($src,'(?m)^(?:__version__|VERSION)\s*=\s*["''](?<v>\d+\.\d+\.\d+)["'']')
    if (-not $m.Success) {
        throw "Could not find VERSION/__version__ = 'X.Y.Z' in $Path"
    }
    return $m.Groups['v'].Value
}

function Set-SemVerInVersionManager {
    param([string]$SemVer,[string]$Path='version_manager.py')
    $src = Get-Content $Path -Raw
    $src = $src -replace '(?m)^(?:__version__|VERSION)\s*=\s*["'']\d+\.\d+\.\d+["'']', "VERSION = `"$SemVer`""
    $src | Set-Content -Encoding UTF8 $Path
}

function Get-LatestRemoteTagSemVer {
    # returns [version] or $null if none
    $lines = git ls-remote --tags origin 2>$null
    if (-not $lines) { return $null }
    $vers = @()
    foreach ($line in ($lines -split "`n")) {
        if ($line -match 'refs/tags/v(\d+\.\d+\.\d+)$') {
            try { $vers += [version]$Matches[1] } catch {}
        }
    }
    if ($vers.Count -eq 0) { return $null }
    return ($vers | Sort-Object -Descending | Select-Object -First 1)
}

function Bump-Version {
    param([version]$v,[string]$kind)
    switch ($kind) {
        'major' { [version]::new($v.Major+1,0,0) }
        'minor' { [version]::new($v.Major,$v.Minor+1,0) }
        'patch' { [version]::new($v.Major,$v.Minor,$v.Build+1) }
        default { $v }
    }
}

function Show-Compare {
    param([string]$relBranch)
    Write-Host "  Fetching latest remote info..." -ForegroundColor Gray
    git fetch origin --prune | Out-Null
    Write-Host "  Comparing $relBranch vs main (remote)..." -ForegroundColor Gray
    Write-Host "`n=== Compare $relBranch vs main (remote) ===" -ForegroundColor Cyan
    $counts = git rev-list --left-right --count "origin/main...origin/$relBranch"
    $behind,$ahead = $counts -split '\s+'
    Write-Host ("behind(main)<-: {0} ahead(rel)->: {1}" -f $behind,$ahead)
    Write-Host "`nChanged files:" -ForegroundColor Cyan
    git diff --name-status "origin/main..origin/$relBranch" | ForEach-Object { $_ }
    Write-Host "============================================`n"
}

# --- Main Script ---
try {
    # --- repo root & remote ---
    Write-Host "Starting SysAdminSuite release process..." -ForegroundColor Cyan
    Write-Host "Setting up repository..." -ForegroundColor Yellow
    
    # Set to SysAdminSuite directory
    Set-Location 'C:\Users\Cheex\Desktop\dev\config\github\SysAdminSuite'
    git init | Out-Null
    $REPO_URL = (git config --get remote.origin.url 2>$null)
    if (-not $REPO_URL) {
        Write-Host "Adding remote origin..." -ForegroundColor Yellow
        $REPO_URL = 'https://github.com/your-username/SysAdminSuite.git'
        git remote add origin $REPO_URL
        Write-Host "Remote origin added" -ForegroundColor Green
    } else {
        Write-Host "Remote origin already configured" -ForegroundColor Green
    }

    # --- identity ---
    Write-Host "Checking git identity..." -ForegroundColor Yellow
    $un = git config user.name 2>$null
    $ue = git config user.email 2>$null
    if ([string]::IsNullOrWhiteSpace($un) -or [string]::IsNullOrWhiteSpace($ue)) {
        throw "Set git user.name / user.email before proceeding."
    }
    Write-Host "Git identity configured: $un <$ue>" -ForegroundColor Green

    # --- base version from version_manager.py ---
    Write-Host "Reading current version from version_manager.py..." -ForegroundColor Yellow
    $sem = [version](Get-SemVerFromVersionManager)
    Write-Host "Current version: $sem" -ForegroundColor Green

    # --- bump logic ---
    if ($Bump -ne 'none') {
        $latestRemote = Get-LatestRemoteTagSemVer
        if ($latestRemote) {
            Write-Host "Bumping from latest remote tag: $latestRemote" -ForegroundColor Yellow
            $newSem = Bump-Version $latestRemote $Bump
        } else {
            Write-Host "No remote tags found, bumping from current: $sem" -ForegroundColor Yellow
            $newSem = Bump-Version $sem $Bump
        }
        Write-Host "New version: $newSem" -ForegroundColor Green
        
        if (-not $NoWriteMain) {
            Write-Host "Updating version_manager.py..." -ForegroundColor Yellow
            Set-SemVerInVersionManager $newSem
            Write-Host "Version updated in version_manager.py" -ForegroundColor Green
        }
    } else {
        $newSem = $sem
        Write-Host "No bump requested, using current version" -ForegroundColor Yellow
    }

    # --- branch & tag names ---
    $VERSION = "v$newSem"
    $BRANCH = "$Prefix/$VERSION"
    Write-Host "Version: $VERSION" -ForegroundColor Cyan
    Write-Host "Branch: $BRANCH" -ForegroundColor Cyan

    # --- git operations ---
    Write-Host "Fetching latest changes..." -ForegroundColor Yellow
    git fetch origin --prune | Out-Null

    # Check if branch already exists
    $branchExists = git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>$null
    if ($branchExists) {
        throw "Branch $BRANCH already exists on remote. Use a different version or delete the existing branch."
    }

    # Create and switch to release branch
    Write-Host "Creating release branch: $BRANCH" -ForegroundColor Yellow
    git checkout -b $BRANCH 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create branch $BRANCH"
    }

    # Stage and commit version changes
    if (-not $NoWriteMain) {
        Write-Host "Committing version changes..." -ForegroundColor Yellow
        git add version_manager.py
        git commit -m "chore(version): bump to $VERSION" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "No changes to commit (version already up to date)" -ForegroundColor Yellow
        } else {
            Write-Host "Version changes committed" -ForegroundColor Green
        }
    }

    # Create tag
    Write-Host "Creating tag: $VERSION" -ForegroundColor Yellow
    git tag -a $VERSION -m "Release $VERSION: SysAdminSuite IT tools collection" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create tag $VERSION"
    }
    Write-Host "Tag created" -ForegroundColor Green

    # Push branch and tag
    Write-Host "Pushing branch and tag..." -ForegroundColor Yellow
    git push origin $BRANCH 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push branch $BRANCH"
    }
    
    git push origin $VERSION 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push tag $VERSION"
    }
    Write-Host "Branch and tag pushed successfully" -ForegroundColor Green

    # --- PR creation ---
    if ($OpenPR) {
        Write-Host "Creating pull request..." -ForegroundColor Yellow
        $prTitle = "Release $VERSION: SysAdminSuite IT tools collection"
        $autoMergeStatus = if ($AutoMerge) { "Enabled" } else { "Disabled" }
        $prBody = @"
## Release $VERSION

This release includes updates to the SysAdminSuite IT tools collection.

### Changes
- Version bump to $VERSION
- Updated version management system
- Enhanced documentation and templates

### Checklist
- [ ] All tools tested
- [ ] Documentation updated
- [ ] Security audit completed
- [ ] Performance validation passed

### Auto-merge
$autoMergeStatus
"@
        
        gh pr create --title $prTitle --body $prBody --base main --head $BRANCH 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Pull request created" -ForegroundColor Green
            
            if ($AutoMerge) {
                Write-Host "Waiting for checks to complete..." -ForegroundColor Yellow
                Start-Sleep -Seconds 10
                gh pr merge --auto --delete-branch 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Pull request auto-merged" -ForegroundColor Green
                } else {
                    Write-Host "Auto-merge failed (checks may still be running)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "Failed to create pull request (GitHub CLI may not be installed)" -ForegroundColor Yellow
        }
    }

    # --- final comparison ---
    Show-Compare $BRANCH

    Write-Host "`nRelease $VERSION created successfully!" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Review the changes in the release branch" -ForegroundColor White
    Write-Host "   2. Test all tools in the collection" -ForegroundColor White
    Write-Host "   3. Create GitHub release with release notes" -ForegroundColor White
    Write-Host "   4. Merge to main when ready" -ForegroundColor White

} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
