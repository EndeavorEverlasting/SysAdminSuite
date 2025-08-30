# 0) sanity: make sure we're in the right repo
git remote -v

# 1) fetch all remote branches
git fetch origin

# 2) create/switch to the branch you want to use (based on your current work)
git switch -c LPW003ASI037-Repo

# 3) merge the remote branch history into your local branch (handles README/LICENSE)
git pull --no-edit --allow-unrelated-histories origin LPW003ASI037-Repo

# (if you see any conflicts, fix them, then:)
# git add <files>
# git commit

# 4) push this branch to GitHub and set upstream for future pushes
git push -u origin LPW003ASI037-Repo --force-with-lease
