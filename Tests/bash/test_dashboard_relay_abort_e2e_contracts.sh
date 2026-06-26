#!/usr/bin/env bash
set -euo pipefail

# Contracts for the end-to-end loopback relay abort test. These are static
# guards (no network) that the E2E test exists, stays loopback-only, exercises
# the real relay, kills the relay process, and asserts client-side
# abort/disconnect classification. The live behavior is proven by running
# dashboard/test_relay_abort_e2e.js itself.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
e2e="$repo_root/dashboard/test_relay_abort_e2e.js"
relay="$repo_root/dashboard/relay.py"
workflow="$repo_root/.github/workflows/dashboard-smoke.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$e2e" ]] || fail "dashboard/test_relay_abort_e2e.js is missing"
[[ -f "$relay" ]] || fail "dashboard/relay.py is missing"
[[ -f "$workflow" ]] || fail ".github/workflows/dashboard-smoke.yml is missing"

# Loopback-only discipline: every target literal must be in 127.0.0.0/8, and the
# test must not reference non-loopback hosts.
grep -q "127.0.0.1" "$e2e" || fail "E2E test does not use a loopback target"
grep -q "LOOPBACK_TARGETS" "$e2e" || fail "E2E test does not declare a LOOPBACK_TARGETS guard"
if grep -Eq 'targets.*(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' "$e2e"; then
  fail "E2E test references a non-loopback RFC1918 target - must stay loopback-only"
fi

# Real relay subprocess + token auth (no hardcoded credential).
grep -q "relay.py" "$e2e" || fail "E2E test does not launch the real relay.py"
grep -q "Token only:" "$e2e" || fail "E2E test does not authenticate via the relay's printed token"

# Abort/disconnect protocol + required client-side assertions.
grep -q "sendRelayProbe" "$e2e" || fail "E2E test does not drive the real relay-client sendRelayProbe path"
grep -q "SIGTERM" "$e2e" || fail "E2E test does not terminate the relay process mid-probe"
grep -q "aborted" "$e2e" || fail "E2E test does not assert aborted classification"
grep -q "cancelled" "$e2e" || fail "E2E test does not assert relay death is not cancelled"
grep -q "not-success" "$e2e" || fail "E2E test does not assert relay death is not success"
grep -q "partial-results-preserved" "$e2e" || fail "E2E test does not assert partial results are preserved"
grep -q "no-server-probe-done" "$e2e" || fail "E2E test does not assert abort is client-synthesized"
if grep -q "probe_cancel" "$e2e"; then
  fail "E2E test must prove relay death, not user Stop via probe_cancel"
fi

# CI must actually run the relay abort test so the loop stays closed.
grep -q "test_relay_abort_e2e.js" "$workflow" || fail "dashboard-smoke.yml does not run the relay abort E2E test"
grep -q "node --check dashboard/test_relay_abort_e2e.js" "$workflow" \
  || fail "dashboard-smoke.yml does not syntax-check the relay abort E2E test"
grep -q "npm install --no-save --no-package-lock ws@8" "$workflow" \
  || fail "dashboard-smoke.yml does not install ws for the relay abort E2E test"

echo "PASS: dashboard relay abort E2E contracts"
