#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

cat <<'TXT'
[SAS] Harness output locations

Validator output:
  survey/output/harness-validator/

English reports:
  survey/output/english-log/

Run contexts:
  survey/output/runs/

Latest reviewed evidence pointer:
  docs/evidence/latest/README.md

Keep generated run output local unless it is reviewed and intentionally sanitized.
TXT
