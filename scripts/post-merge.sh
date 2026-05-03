#!/bin/bash
set -e

echo "Post-merge setup: SysAdminSuite"
echo "No build step required — dashboard is pure HTML/JS/CSS."
echo "server.py serves /dashboard/ as static files."

echo "Installing git hooks..."
if [ -f "git-hooks/post-commit" ]; then
  cp git-hooks/post-commit .git/hooks/post-commit
  chmod +x .git/hooks/post-commit
  echo "post-commit hook installed."
else
  echo "WARNING: git-hooks/post-commit not found — hook not installed."
fi

echo "Configuring git credentials..."
if [ -z "$GITHUB_TOKEN" ]; then
  echo "WARNING: GITHUB_TOKEN is not set. Skipping GitHub sync."
else
  git config credential.helper \
    '!f() { printf "username=x-token-auth\n"; printf "password=%s\n" "$GITHUB_TOKEN"; }; f'

  echo "Syncing to GitHub..."
  if git push origin main; then
    echo "GitHub sync complete."
  else
    echo "WARNING: GitHub push failed (remote may have diverged)."
  fi
fi

echo "Post-merge setup complete."
