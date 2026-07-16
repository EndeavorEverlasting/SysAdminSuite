#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
exec "$script_dir/invoke-sas-resume-matcher-workstation.sh" "$@" --action Accept --apply
