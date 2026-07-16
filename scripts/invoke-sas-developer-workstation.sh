#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
python=${PYTHON:-python3}
exec "$python" "$script_dir/Invoke-SasDeveloperWorkstation.py" "$@"
