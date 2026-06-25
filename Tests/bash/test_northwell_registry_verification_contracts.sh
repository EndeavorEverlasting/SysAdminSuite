#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$ROOT/docs/NORTHWELL_REGISTRY_VERIFICATION_DOCTRINE.md"
CATALOG="$ROOT/Config/software_registry_evidence.example.json"
CMD_HELPER="$ROOT/survey/sas-reg-query.cmd"
WRAPPER="$ROOT/survey/sas-verify-software-install.sh"
PARSER="$ROOT/survey/parse_registry_install_evidence.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$DOC" ]] || fail "missing doctrine doc"
[[ -f "$CATALOG" ]] || fail "missing software evidence catalog"
[[ -f "$CMD_HELPER" ]] || fail "missing CMD registry collector"
[[ -f "$WRAPPER" ]] || fail "missing Bash wrapper"
[[ -f "$PARSER" ]] || fail "missing Python parser"

[[ ! -e "$ROOT/scripts/powershell/Test-SoftwareInstallEvidence.ps1" ]] || fail "new PowerShell verifier must not be added for this Northwell lane"

grep -q "CMD/reg.exe" "$DOC" || fail "doctrine must identify CMD/reg.exe as the primary Northwell runtime"
grep -q "must not attempt to suppress" "$DOC" || fail "doctrine must reject log suppression"
grep -q "environment_blocked" "$DOC" || fail "doctrine must define environment_blocked"
grep -q "survey/output/" "$DOC" || fail "doctrine must keep live outputs under ignored survey/output"

grep -q '"software_id": "sample-viewer"' "$CATALOG" || fail "catalog must include public-safe sample-viewer"
grep -q '"uninstall_display_name_patterns"' "$CATALOG" || fail "catalog must define uninstall display name patterns"

grep -q "reg.exe QUERY" "$CMD_HELPER" || fail "CMD helper must use reg.exe QUERY"
grep -q "command_family=reg_query_read_only" "$CMD_HELPER" || fail "CMD helper must label read-only command family"

grep -q "cmd.exe" "$WRAPPER" || fail "Bash wrapper must call cmd.exe"
grep -q "--fixture-raw" "$WRAPPER" || fail "Bash wrapper must support fixture raw parsing for CI"
grep -q "parse_registry_install_evidence.py" "$WRAPPER" || fail "Bash wrapper must call Python parser"

grep -q "installed_registry_confirmed" "$PARSER" || fail "parser must emit installed_registry_confirmed"
grep -q "installed_fallback_confirmed" "$PARSER" || fail "parser must emit installed_fallback_confirmed"
grep -q "environment_blocked" "$PARSER" || fail "parser must emit environment_blocked"

runtime_files=("$CMD_HELPER" "$WRAPPER" "$PARSER")
for f in "${runtime_files[@]}"; do
  grep -Eiq 'reg\.exe[[:space:]]+(ADD|DELETE|IMPORT|RESTORE)' "$f" && fail "forbidden reg.exe mutation verb in $f"
  grep -Eiq 'Set-ItemProperty|New-ItemProperty|Remove-ItemProperty' "$f" && fail "forbidden registry mutation cmdlet in $f"
done

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
RAW="$TMPDIR/sample_registry_raw.txt"
OUT_CSV="$TMPDIR/software_install_evidence.csv"
OUT_JSON="$TMPDIR/software_install_evidence.json"

cat > "$RAW" <<'EOF'
# SysAdminSuite registry evidence raw output
# target=SAMPLEHOST001
# software_id=sample-viewer
# command_family=reg_query_read_only

### UNINSTALL_64
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SampleViewer
    DisplayName    REG_SZ    Sample Viewer
    DisplayVersion    REG_SZ    1.2.3
    Publisher    REG_SZ    Sample Vendor
EOF

python3 "$PARSER" \
  --catalog "$CATALOG" \
  --software-id sample-viewer \
  --target SAMPLEHOST001 \
  --raw "$RAW" \
  --output "$OUT_CSV" \
  --json "$OUT_JSON" >/dev/null

[[ -f "$OUT_CSV" ]] || fail "parser did not write CSV"
[[ -f "$OUT_JSON" ]] || fail "parser did not write JSON"
grep -q "installed_registry_confirmed" "$OUT_CSV" || fail "fixture should classify as installed_registry_confirmed"
grep -q "registry_uninstall_key" "$OUT_CSV" || fail "fixture should label registry_uninstall_key evidence"

if git -C "$ROOT" check-ignore -q survey/output/example_registry_output.csv; then
  :
else
  fail "survey/output must remain gitignored for live verification outputs"
fi

echo "PASS: Northwell registry verification contracts"
