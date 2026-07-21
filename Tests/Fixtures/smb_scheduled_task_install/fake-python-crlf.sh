#!/usr/bin/env bash
set -euo pipefail

"${REAL_PYTHON3:?REAL_PYTHON3 is required}" "$@" | sed 's/$/\r/'
