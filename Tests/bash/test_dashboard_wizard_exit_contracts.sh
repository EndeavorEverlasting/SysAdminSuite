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
run_control="$repo_root/dashboard/js/run-control.js"
relay_client="$repo_root/dashboard/js/relay-client.js"
relay_py="$repo_root/dashboard/relay.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for f in "$index" "$app" "$bundle" "$panel" "$run_control" "$relay_client" "$relay_py"; do
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
grep -q "run-control-banner" "$index" || fail "global Run Control banner is missing from index.html"
grep -q "run-control-stop" "$index" || fail "global Run Control Stop is missing from index.html"
grep -q "RunRequested" "$run_control" || fail "run-control.js does not reduce RunRequested events"
grep -q "CommandGenerated" "$run_control" || fail "run-control.js does not reduce CommandGenerated events"
grep -q "AwaitingExternalResults" "$run_control" || fail "run-control.js does not track AwaitingExternalResults"
grep -q "isRunStoppable" "$run_control" || fail "run-control.js does not guard external-only Stop behavior"
grep -q "_startCommandGenerationRun" "$app" || fail "app.js does not wire command-generation into Run Control"
grep -q "CommandCopied" "$app" || fail "app.js does not emit CommandCopied lifecycle events"
grep -q "subscribeRunEvents" "$panel" || fail "panel-network.js does not subscribe to Run Control lifecycle events"
grep -q "StopAcknowledged" "$run_control" || fail "run-control.js does not distinguish Stop acknowledgement"
grep -q "requestStop" "$panel" || fail "panel-network.js does not dispatch Stop through Run Control"
grep -q "probe_cancel" "$relay_client" || fail "relay-client.js does not send probe_cancel (UI-only Stop is a defect)"
grep -q "StopSent" "$relay_client" || fail "relay-client.js does not emit StopSent lifecycle events"
grep -q "StopAcknowledged" "$relay_client" || fail "relay-client.js does not emit StopAcknowledged lifecycle events"
grep -q "probeId" "$relay_client" || fail "relay-client.js does not tag probes with a probeId"
grep -q "probe_cancel" "$relay_py" || fail "relay.py does not handle probe_cancel"
grep -q "cancel_event" "$relay_py" || fail "relay.py has no cancellation token"
grep -Eq "def run_probe" "$relay_py" || fail "relay.py missing run_probe orchestrator"
grep -q "cancelled" "$relay_py" || fail "relay.py does not report a cancelled probe_done"

# ── Terminal relay failure path ──────────────────────────────────────────────
grep -q "Probe failed before completion" "$relay_py" || fail "relay.py does not send a terminal failure message when background probing crashes"
grep -q '"type": "error"' "$relay_py" || fail "relay.py does not emit an error event for background probe failure"
grep -q '"probeId": pid' "$relay_py" || fail "relay.py background error event is not tied to the active probeId"
grep -q "state\[\"task\"\] = None" "$relay_py" || fail "relay.py does not clear the background task after failure"
grep -q "state\[\"cancel_event\"\] = None" "$relay_py" || fail "relay.py does not clear cancel state after failure"
grep -q "msg.type === 'probe_done' || msg.type === 'error'" "$relay_client" || fail "relay-client.js does not treat relay error as a terminal event"
grep -q "RunFailed" "$relay_client" || fail "relay-client.js does not reduce relay error to RunFailed"

# ── Persistent Stop on the network panel (not modal-only) ────────────────────
grep -q "net-stop-probe-btn" "$panel" || fail "no persistent Stop button on the network panel"
grep -q "net-stop-probe-btn" "$bundle" || fail "bundle.js is stale (missing panel Stop) — run: node dashboard/build-bundle.js"
grep -q "Partial results preserved" "$panel" || fail "panel-network.js does not report preserved partial results"

# ── Command-gen fallback honesty ─────────────────────────────────────────────
grep -q "Ctrl+C" "$app" || fail "command-gen modal does not tell the user to stop copied commands with Ctrl+C"

echo "PASS: dashboard wizard exit + probe stop contracts"
