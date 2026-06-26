#!/usr/bin/env bash
set -euo pipefail

# Contracts for the end-to-end loopback relay cancellation test. These are static
# guards (no network) that the E2E test exists, stays loopback-only, exercises the
# real relay, and asserts the server-side stop semantics. The live behavior is
# proven by running dashboard/test_relay_cancel_e2e.py itself.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
e2e="$repo_root/dashboard/test_relay_cancel_e2e.py"
relay="$repo_root/dashboard/relay.py"
workflow="$repo_root/.github/workflows/dashboard-smoke.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$e2e" ]] || fail "dashboard/test_relay_cancel_e2e.py is missing"
[[ -f "$relay" ]] || fail "dashboard/relay.py is missing"
[[ -f "$workflow" ]] || fail ".github/workflows/dashboard-smoke.yml is missing"

# Loopback-only discipline: every target literal must be in 127.0.0.0/8, and the
# test must not reference non-loopback hosts.
grep -q "127.0.0.1" "$e2e" || fail "E2E test does not use a loopback target"
grep -q "LOOPBACK_TARGETS" "$e2e" || fail "E2E test does not declare a LOOPBACK_TARGETS guard"
if grep -Eq 'targets.*(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' "$e2e"; then
  fail "E2E test references a non-loopback RFC1918 target — must stay loopback-only"
fi

# Real relay subprocess + token auth (no hardcoded credential).
grep -q "relay.py" "$e2e" || fail "E2E test does not launch the real relay.py"
grep -q "Token only:" "$e2e" || fail "E2E test does not authenticate via the relay's printed token"

# Cancellation protocol + the required assertions.
grep -q "probe_cancel" "$e2e" || fail "E2E test does not send probe_cancel"
grep -q "cancelled" "$e2e" || fail "E2E test does not assert a cancelled probe_done"
grep -q "completed" "$e2e" || fail "E2E test does not assert the completed count"
grep -q "no_results_for_targets_two_and_three" "$e2e" \
  || fail "E2E test does not assert targets 2-3 are not probed after cancel"
grep -q "stopped_with_partial" "$e2e" \
  || fail "E2E test does not assert the client stopped-with-partial classification"

# CI must actually run the relay tests so the loop stays closed.
grep -q "test_relay_cancel_e2e.py" "$workflow" || fail "dashboard-smoke.yml does not run the relay E2E test"
grep -q "pip install websockets" "$workflow" || fail "dashboard-smoke.yml does not install the websockets dependency"

echo "PASS: dashboard relay cancel E2E contracts"
