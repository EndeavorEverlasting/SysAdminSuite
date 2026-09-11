#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KIT_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
MANIFEST="$KIT_ROOT/MANIFEST.sha256"

[ -f "$MANIFEST" ] || { printf 'STOP: manifest missing: %s\n' "$MANIFEST" >&2; exit 1; }
cd "$KIT_ROOT"
sha256sum -c MANIFEST.sha256
printf 'FIELD_KIT_VERIFY=PASS\n'
printf 'RUNNER=%s\n' "$KIT_ROOT/recovery/systemrescue/sas-recovery.sh"
