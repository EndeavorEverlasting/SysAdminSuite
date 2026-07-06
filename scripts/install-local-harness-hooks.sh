#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push 2>/dev/null || true

echo "SysAdminSuite local harness hooks installed: core.hooksPath=.githooks"
echo "pre-commit: static contracts + generated evidence guard"
echo "pre-push: offline survey contracts"
