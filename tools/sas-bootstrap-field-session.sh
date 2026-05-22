#!/usr/bin/env bash
set -euo pipefail

# SysAdminSuite field bootstrap helper.
# Purpose: move operator to repo root, optionally pull latest main, and print copy/paste-ready commands.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DO_PULL=1
SHOW_ONLY=0

usage(){ cat <<'USAGE'
SysAdminSuite Field Bootstrap

Usage:
  bash tools/sas-bootstrap-field-session.sh [options]

Options:
  --no-pull     Do not run git pull, even if this is a git clone
  --show-only   Print commands only; do not pull
  -h, --help    Show help

What this does:
  1. Finds the SysAdminSuite repo root from the script location.
  2. Runs git pull --ff-only when the folder is a git clone and --no-pull is not used.
  3. Prints the exact working directory and commands for live serial probe testing.

Notes:
  - If the repo was downloaded as a ZIP, there is no .git folder, so pull is skipped.
  - If git is unavailable, pull is skipped.
  - This helper does not mutate endpoints. It only refreshes the local repo copy.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pull) DO_PULL=0; shift ;;
    --show-only) SHOW_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[bootstrap] ERROR: Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

echo "======================================"
echo " SysAdminSuite Field Bootstrap"
echo "======================================"
echo "Repo root: $REPO_ROOT"
echo

if [[ "$SHOW_ONLY" -eq 0 && "$DO_PULL" -eq 1 ]]; then
  if [[ -d .git ]] && command -v git >/dev/null 2>&1; then
    echo "[bootstrap] Updating repo with: git pull --ff-only"
    if ! git pull --ff-only; then
      echo "[bootstrap] WARN: git pull failed. Check local changes or network access. Continuing with current files." >&2
    fi
  elif [[ ! -d .git ]]; then
    echo "[bootstrap] No .git folder found. This looks like a ZIP/download copy, so auto-pull is skipped."
  else
    echo "[bootstrap] git not found. Auto-pull skipped."
  fi
else
  echo "[bootstrap] Pull skipped by option."
fi

cat <<'COMMANDS'

Working directory is now the SysAdminSuite repo root.

Run safe offline/test mode:

  bash survey/sas-live-serial-probe.sh \
    --manifest survey/fixtures/live_serial_manifest.sample.csv \
    --identity-csv survey/fixtures/live_serial_identity.sample.csv \
    --output survey/output/live_serial_probe_results.csv \
    --dashboard survey/output/live_serial_probe_dashboard.html

Run contract test:

  bash deployment-audit/tests/test_live_serial_probe_contracts.sh

Run live probe against your manifest:

  bash survey/sas-live-serial-probe.sh \
    --manifest survey/output/remote_survey_manifest.csv \
    --output survey/output/live_serial_probe_results.csv \
    --dashboard survey/output/live_serial_probe_dashboard.html

Open dashboard after generation:

  explorer.exe survey\\output\\live_serial_probe_dashboard.html
COMMANDS
