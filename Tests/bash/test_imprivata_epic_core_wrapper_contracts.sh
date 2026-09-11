#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'test_imprivata_epic_core_wrapper_contracts: FAIL: %s\n' "$*" >&2
  exit 1
}

SCRIPT="bash/apps/sas-install-imprivata-core.sh"
[[ -f "$SCRIPT" ]] || fail "wrapper is missing"
bash -n "$SCRIPT"

HELP_OUTPUT="$(bash "$SCRIPT" --help)"
for fragment in \
  'Imprivata OneSign Epic Connector 25.6.40154' \
  'Imprivata OneSign Agent 25.1.000.15' \
  'Northwell OneSign SecureLock Shortcut 1.0' \
  '--target-file PATH' \
  '--dry-run'; do
  grep -Fq -- "$fragment" <<< "$HELP_OUTPUT" || fail "help missing: $fragment"
done

for fragment in \
  'Imprivata_OnesignEpicConnector_25.6.40154' \
  'Imprivata_OneSignAgent_25.1.000.15' \
  'Northwell_OneSign-SecureLock-Shortcut_1.0' \
  'os.walk(source, followlinks=False)' \
  '"entrypoint_file": "Install.cmd"' \
  '"installer_type": "cmd"' \
  'recursive_files_pinned_per_run_before_target_contact' \
  '--package-set imprivata-epic-core' \
  '--package-set-catalog "$MANIFEST"' \
  '--allow-legacy'; do
  grep -Fq -- "$fragment" "$SCRIPT" || fail "wrapper contract missing: $fragment"
done

if grep -Eq -- '--smb-user|--smb-pass|SAS_SMB_PASS' "$SCRIPT"; then
  fail "wrapper must not introduce SMB credential arguments"
fi

python3 - "$SCRIPT" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
ordered = [
    "Imprivata_OnesignEpicConnector_25.6.40154",
    "Imprivata_OneSignAgent_25.1.000.15",
    "Northwell_OneSign-SecureLock-Shortcut_1.0",
]
positions = [text.index(item) for item in ordered]
assert positions == sorted(positions), "approved Imprivata install order changed"
assert "len(staged_files) > 50" in text, "wrapper must preserve package-set file-count guard"
assert "Install.cmd is missing" in text, "wrapper must fail closed when the bundle entrypoint is absent"
PY

printf 'PASS: Imprivata Epic core SAS wrapper contracts\n'
