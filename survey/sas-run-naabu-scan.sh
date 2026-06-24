#!/usr/bin/env bash
# Alias — canonical entry: sas-run-naabu-pipeline.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=() pipe=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site|--profile|--list|--host) args+=("$1" "${2:?}"); shift 2 ;;
    --json-out) args+=(--out "${2:?}"); shift 2 ;;
    --txt-out) args+=(--out "${2:?}"); shift 2 ;;
    --pipe) pipe=1; shift ;;
    --pipe-followup) args+=(--pipe-followup); shift ;;
    --dry-run|--allow-public|--allow-full-ports) args+=("$1"); shift ;;
    --full-ports) args+=(--allow-full-ports); shift ;;
    --skip-install|--verbose|--no-exclude-cdn) shift ;;
    --logs-root) shift 2 ;;
    -h|--help) exec bash "$SCRIPT_DIR/sas-run-naabu-pipeline.sh" --help ;;
    *) args+=("$1"); shift ;;
  esac
done
[[ "$pipe" -eq 1 ]] && args+=(--pipe-followup --profile keyports_cybernet_pipe)
exec bash "$SCRIPT_DIR/sas-run-naabu-pipeline.sh" "${args[@]}"
