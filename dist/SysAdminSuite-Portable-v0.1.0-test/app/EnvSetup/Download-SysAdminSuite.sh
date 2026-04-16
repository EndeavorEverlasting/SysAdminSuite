#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Download SysAdminSuite from GitHub (main branch) without using git or the
# GitHub website. Requires bash, tar, and curl or wget.
#
# Usage:
#   ./Download-SysAdminSuite.sh              # extract into current directory
#   ./Download-SysAdminSuite.sh /path/parent # extract into /path/parent
# ------------------------------------------------------------------------------
set -euo pipefail
unset CDPATH

# ------------------------------------------------------------------------------
# Config (defaults)
# ------------------------------------------------------------------------------
GITHUB_OWNER="EndeavorEverlasting"
GITHUB_REPO="SysAdminSuite"
GIT_BRANCH="main"

GITHUB_TARBALL_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/heads/${GIT_BRANCH}.tar.gz"
ARCHIVE_TOP_DIR="${GITHUB_REPO}-${GIT_BRANCH}"

INSTALL_PARENT="${1:-.}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' is required but not found in PATH." >&2
    exit 1
  fi
}

download_extract() {
  local url=$1
  local dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fSL --retry 3 --retry-delay 2 "$url" | (cd "$dest" && tar -xz)
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" | (cd "$dest" && tar -xz)
  else
    echo "ERROR: Need curl or wget to download the repository archive." >&2
    exit 1
  fi
}

require_cmd tar

if [[ ! -d "$INSTALL_PARENT" ]]; then
  echo "ERROR: Directory does not exist: $INSTALL_PARENT" >&2
  exit 1
fi

PARENT_ABS="$(cd "$INSTALL_PARENT" && pwd)"
DEST_ARCHIVE="${PARENT_ABS}/${ARCHIVE_TOP_DIR}"
DEST_FINAL="${PARENT_ABS}/${GITHUB_REPO}"

if [[ -e "$DEST_FINAL" ]]; then
  echo "ERROR: Target already exists: $DEST_FINAL" >&2
  echo "Remove or rename it, then run this script again." >&2
  exit 1
fi

if [[ -e "$DEST_ARCHIVE" ]]; then
  echo "ERROR: Incomplete or stale folder exists: $DEST_ARCHIVE" >&2
  echo "Remove it, then run this script again." >&2
  exit 1
fi

echo "Downloading ${GITHUB_OWNER}/${GITHUB_REPO} (branch ${GIT_BRANCH}) into ${PARENT_ABS} ..."

download_extract "$GITHUB_TARBALL_URL" "$PARENT_ABS"

if [[ ! -d "$DEST_ARCHIVE" ]]; then
  echo "ERROR: Extracted folder not found: $DEST_ARCHIVE" >&2
  exit 1
fi

mv "$DEST_ARCHIVE" "$DEST_FINAL"

echo "Done. SysAdminSuite is at:"
echo "$DEST_FINAL"
