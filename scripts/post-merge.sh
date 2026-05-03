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
# Always write the credential helper into .git/config so it survives container
# restarts. The helper reads $GITHUB_TOKEN from the environment at runtime,
# so it does not need to be set at this point.
git config credential.helper \
  '!f() { printf "username=x-token-auth\n"; printf "password=%s\n" "$GITHUB_TOKEN"; }; f'
echo "Credential helper configured."

if [ -z "$GITHUB_TOKEN" ]; then
  echo "WARNING: GITHUB_TOKEN is not set. Skipping initial GitHub sync (push will work once the token is available)."
else
  echo "Syncing to GitHub..."
  if git push origin main; then
    echo "GitHub sync complete."
  else
    echo "WARNING: GitHub push failed (remote may have diverged)."
  fi
fi

echo "Post-merge setup complete."
