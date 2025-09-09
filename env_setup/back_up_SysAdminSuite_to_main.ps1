# 1) Log in to GitHub (if not already)
gh auth login

# 2) Set your identity (once)
git config --global user.name  "EndeavorEverlasting"
git config --global user.email "sage.holly7825@eagereverest.com"

# 3) Go to your project
cd "C:\Users\pa_rperez26\OneDrive - Northwell Health\Desktop\dev\SysAdminSuite"

# 4) Initialize & point at your repo (use your actual URL)
git init
git branch -M main
git remote add origin https://github.com/EndeavorEverlasting/SysAdminSuite.git

# 5) First commit + push
git add .
git commit -m "Initial backup of SysAdminSuite tools"
git push -u origin main
