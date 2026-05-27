#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-autologon-assessment"
CSV_OUT="$OUT_DIR/autologon_assessment.csv"
HTML_OUT="$OUT_DIR/autologon_dashboard.html"
ASSESS="$ROOT/survey/sas-assess-autologon.sh"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

bash "$ASSESS" \
  --manifest "$ROOT/survey/fixtures/autologon_manifest.sample.csv" \
  --fixture-dry-run \
  --output "$CSV_OUT" \
  --dashboard "$HTML_OUT"

[[ -f "$CSV_OUT" ]] || { echo "FAIL: missing CSV output" >&2; exit 1; }
[[ -f "$HTML_OUT" ]] || { echo "FAIL: missing HTML dashboard" >&2; exit 1; }

for col in Timestamp HostName Reachability AdminShareOk PostInstall_SetAutoLogon Winlogon_AutoAdminLogon \
  Hostname_User_Match AD_User_Found OverallStatus AssessmentStage ProbeMethod EvidenceDetail RevisitRecommendation; do
  grep -q "$col" "$CSV_OUT" || { echo "FAIL: missing $col column" >&2; exit 1; }
done

for val in shared_device autologon_ready intent_only account_missing setup_incomplete ou_mismatch unreachable probe_failed; do
  grep -q "$val" "$CSV_OUT" || { echo "FAIL: expected OverallStatus $val" >&2; exit 1; }
done

grep -q 'SysAdminSuite Auto-logon Assessment Dashboard' "$HTML_OUT" || { echo "FAIL: dashboard title missing" >&2; exit 1; }
grep -q 'Glowing Workstation Cards' "$HTML_OUT" || { echo "FAIL: glowing workstation cards missing" >&2; exit 1; }
grep -q 'Auto-logon Ready' "$HTML_OUT" || { echo "FAIL: metric label missing" >&2; exit 1; }
grep -q 'Shared Devices' "$HTML_OUT" || { echo "FAIL: shared devices metric missing" >&2; exit 1; }
grep -q 'OverallStatus' "$HTML_OUT" || { echo "FAIL: OverallStatus column missing from dashboard" >&2; exit 1; }
grep -q 'RevisitRecommendation' "$HTML_OUT" || { echo "FAIL: RevisitRecommendation column missing" >&2; exit 1; }

if grep -Eiq '(Set-Item|New-ItemProperty|reg\.exe\s+ADD|Remove-Item|Set-AD|Add-AD|Move-ADObject|Invoke-Command.*-ScriptBlock)' "$ASSESS"; then
  echo "FAIL: assess script contains forbidden mutation patterns" >&2
  exit 1
fi

echo "PASS: autologon assessment contracts"
