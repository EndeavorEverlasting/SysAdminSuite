# Cleanup script for stray/bad filenames in Git branches
# Usage: run from the repo root, already cloned locally

# 1) Make sure you’re on the branch and up to date
git fetch --prune
git checkout <branch-name>
git pull --ff-only

# 2) See suspicious files in the index
git ls-files | egrep '(^tatus$|^status$|porcelain|git checkout main|ersCheeks)'

# 3) Remove the obvious ones (won’t error if they’re missing)
git rm -f -- 'tatus' || true
git rm -f -- 'tatus --porcelain' || true
git rm -f -- 'status' || true

# 4) Find & remove any weird long filename containing "git checkout main"
WEIRD="$(git ls-files | grep -F 'git checkout main' || true)"
if [ -n "$WEIRD" ]; then
  echo "Removing: $WEIRD"
  git rm -f -- "$WEIRD"
fi

# 5) Commit and push
git commit -m "chore: remove stray debug/status files with spaces/non-ASCII (cleanup)"
git push -u origin <branch-name>

# 6) Quick sanity check
git log -1 --name-status
