#!/bin/bash
set -e

echo "Post-merge setup: SysAdminSuite"
echo "No build step required — dashboard is pure HTML/JS/CSS."
echo "server.py serves /dashboard/ as static files."

echo "Syncing to GitHub..."
if [ -z "$GITHUB_TOKEN" ]; then
  echo "WARNING: GITHUB_TOKEN is not set. Skipping GitHub sync."
else
  REPO_URL="https://${GITHUB_TOKEN}@github.com/EndeavorEverlasting/SysAdminSuite.git"
  git push --force "$REPO_URL" main
  echo "GitHub sync complete."
fi

echo "Post-merge setup complete."
