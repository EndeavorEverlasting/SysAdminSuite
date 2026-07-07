#!/usr/bin/env bash
# Compatibility wrapper for the canonical lowercase test path.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/tests/bash/smoke-naabu-profiles.sh" "$@"
