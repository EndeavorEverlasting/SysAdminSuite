#!/usr/bin/env bash
set -euo pipefail

# Contracts for the persistent wizard Back/Exit controls and the real (relay-honored)
# live-probe Stop. A field user must always be able to leave a wizard and stop a
# running probe — and Stop must halt server-side network activity, not just the UI.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
index="$repo_root/dashboard/index.html"
app="$repo_root/dashboard/js/app.js"
bundle="$repo_root/dashboard/js/bundle.js"
panel="$repo_root/dashboard/js/panel-network.js"
relay_client="$repo_root/dashboard/js/relay-client.js"
relay_py="$repo_root/dashboard/relay.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for f in "$index" "$app" "$bundle" "$panel" "$relay_client" "$relay_py"; do
  [[ -f "$f" ]] || fail "missing required file: $f"
done

# ── Persistent Back/Exit on every wizard ─────────────────────────────────────
for id in cybernet-exit repo-setup-exit toolbox-exit sw-exit; do
  grep -q "id=\"$id\"" "$index" || fail "wizard exit control #$id is missing from index.html"
done
grep -q "Back to dashboard" "$index" || fail "no 'Back to dashboard' exit control in index.html"

# Step Back must be a distinct control from the persistent exit (not overloaded).
grep -q "Previous Step" "$index" || fail "step Back not renamed to 'Previous Step'"

# Shared, state-independent close helper exists and is bundled.
grep -q "closeWorkflowTutorial" "$app" || fail "app.js does not define closeWorkflowTutorial"
grep -q "closeWorkflowTutorial" "$bundle" || fail "bundle.js is stale — run: node dashboard/build-bundle.js"

# Each wizard shell wires its exit control to the close helper.
for id in cybernet-exit repo-setup-exit toolbox-exit sw-exit; do
  grep -q "$id" "$app" || fail "app.js does not wire the #$id exit control"
done

# ── Real Stop: relay cancellation protocol ───────────────────────────────────
grep -q "probe_cancel" "$relay_client" || fail "relay-client.js does not send probe_cancel (UI-only Stop is a defect)"
grep -q "probeId" "$relay_client" || fail "relay-client.js does not tag probes with a probeId"
grep -q "probe_cancel" "$relay_py" || fail "relay.py does not handle probe_cancel"
grep -q "cancel_event" "$relay_py" || fail "relay.py has no cancellation token"
grep -Eq "def run_probe" "$relay_py" || fail "relay.py missing run_probe orchestrator"
grep -q "cancelled" "$relay_py" || fail "relay.py does not report a cancelled probe_done"

# ── Persistent Stop on the network panel (not modal-only) ────────────────────
grep -q "net-stop-probe-btn" "$panel" || fail "no persistent Stop button on the network panel"
grep -q "net-stop-probe-btn" "$bundle" || fail "bundle.js is stale (missing panel Stop) — run: node dashboard/build-bundle.js"
grep -q "Partial results preserved" "$panel" || fail "panel-network.js does not report preserved partial results"

# ── Command-gen fallback honesty ─────────────────────────────────────────────
grep -q "Ctrl+C" "$app" || fail "command-gen modal does not tell the user to stop copied commands with Ctrl+C"

echo "PASS: dashboard wizard exit + probe stop contracts"
