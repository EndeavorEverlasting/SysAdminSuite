#!/usr/bin/env bash
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/invoke-sas-linux-tmux-workspace.sh" --action Stop "$@"
