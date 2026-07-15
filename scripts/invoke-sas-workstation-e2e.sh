#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
exec "${PYTHON:-python3}" "$script_dir/Invoke-SasWorkstationE2E.py" "$@"
