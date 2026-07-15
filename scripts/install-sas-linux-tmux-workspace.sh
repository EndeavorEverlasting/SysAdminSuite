#!/usr/bin/env bash
set -euo pipefail
action=Plan
for argument in "$@"; do [[ "$argument" == --apply ]] && action=Apply; done
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/invoke-sas-linux-tmux-workspace.sh" --action "$action" "$@"
