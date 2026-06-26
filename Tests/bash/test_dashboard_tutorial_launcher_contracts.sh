#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cmd="$repo_root/Start-CybernetSurveyTutorial.cmd"
index="$repo_root/dashboard/index.html"
helper="$repo_root/dashboard/js/launch-cybernet-tutorial.js"
setup_helper="$repo_root/dashboard/js/launch-repo-setup-tutorial.js"
app="$repo_root/dashboard/js/app.js"
bundle="$repo_root/dashboard/js/bundle.js"
preflight="$repo_root/dashboard/js/cybernet-os-preflight.js"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$cmd" ]] || fail "Start-CybernetSurveyTutorial.cmd is missing"
[[ -f "$index" ]] || fail "dashboard/index.html is missing"
[[ -f "$helper" ]] || fail "dashboard/js/launch-cybernet-tutorial.js is missing"
[[ -f "$setup_helper" ]] || fail "dashboard/js/launch-repo-setup-tutorial.js is missing"
[[ -f "$app" ]] || fail "dashboard/js/app.js is missing"
[[ -f "$bundle" ]] || fail "dashboard/js/bundle.js is missing"
[[ -f "$preflight" ]] || fail "dashboard/js/cybernet-os-preflight.js is missing"

grep -Fq 'dashboard\index.html' "$cmd" || fail "launcher does not point at dashboard\index.html"
grep -q "tutorial=cybernet" "$cmd" || fail "launcher does not request the Cybernet tutorial"
grep -q "launch-cybernet-tutorial.js" "$index" || fail "dashboard index does not include tutorial launcher helper"
grep -q "launch-repo-setup-tutorial.js" "$index" || fail "dashboard index does not include repo setup tutorial launcher helper"
grep -q "hero-start-survey" "$helper" || fail "helper does not target the existing Start Cybernet Survey button"
grep -q "URLSearchParams" "$helper" || fail "helper does not inspect query parameters"
grep -q "hero-start-setup" "$setup_helper" || fail "setup helper does not target the Start Repo Setup button"
grep -q "tutorial === 'setup'" "$setup_helper" || fail "setup helper does not inspect setup tutorial query parameter"

# Ignore REM lines; the launcher documents that it does not run survey tooling.
if grep -viE '^[[:space:]]*rem[[:space:]]' "$cmd" | grep -qiE 'naabu|nmap|credential|password|psexec|invoke-command'; then
  fail "double-click launcher must not run survey, credential, or remote command tooling"
fi

# ── Start-button visible-failure contracts ──────────────────────────────────
# A press of Start must never strand the user: the wizard must open and be
# verified visible, or a visible recovery state must be shown. The Start button
# must not simply be hidden with no visible continuation.

# 1. The hero must carry a visible status line for Opening / open / error states.
grep -q 'id="cybernet-hero-status"' "$index" \
  || fail "dashboard index is missing the hero status line (cybernet-hero-status)"

# 2. app.js must use an explicit, verified state transition (not a bare unhide).
grep -q 'startCybernetTutorial' "$app" \
  || fail "app.js does not define an explicit startCybernetTutorial transition"
grep -q 'window.startCybernetTutorial' "$app" \
  || fail "app.js does not expose startCybernetTutorial for the auto-launch path"
grep -q 'window.startRepoSetupTutorial' "$app" \
  || fail "app.js does not expose startRepoSetupTutorial for the setup auto-launch path"
grep -q 'getComputedStyle' "$app" \
  || fail "app.js does not verify the tutorial is actually visible before transforming the hero"
grep -q 'cybernet-hero-status' "$app" \
  || fail "app.js does not drive a visible hero status"

# 3. Recovery: the Start action must transform into a recovery control rather
#    than vanish. Guard against the old strand pattern that only hid the hero.
grep -q 'Restart Cybernet Survey' "$app" \
  || fail "app.js does not provide a recovery control (Restart Cybernet Survey)"
if grep -Eq "cybernet-hero-actions'\)\?\.classList\.add\('hidden'\)" "$app"; then
  fail "app.js still hides cybernet-hero-actions on Start (strands the user)"
fi

# 4. The OS-preflight helper must not force the wizard hidden on load.
if grep -q 'syncTutorialVisibility' "$preflight"; then
  fail "cybernet-os-preflight.js still gates wizard visibility (forces display:none)"
fi
if grep -Eq "root\.style\.display *= *liveActive" "$preflight"; then
  fail "cybernet-os-preflight.js still forces the tutorial root display off"
fi

# 5. The auto-launch helper must route through the verified transition.
grep -q 'window.startCybernetTutorial' "$helper" \
  || fail "launch-cybernet-tutorial.js does not use the verified startCybernetTutorial transition"
grep -q 'window.startRepoSetupTutorial' "$setup_helper" \
  || fail "launch-repo-setup-tutorial.js does not use the verified startRepoSetupTutorial transition"

# 6. The served bundle must be rebuilt from source (not stale).
grep -q 'startCybernetTutorial' "$bundle" \
  || fail "dashboard/js/bundle.js is stale — rebuild with: node dashboard/build-bundle.js"
grep -q 'initRepoSetupTutorial' "$bundle" \
  || fail "dashboard/js/bundle.js is stale — missing Repo Setup tutorial; rebuild with: node dashboard/build-bundle.js"

echo "PASS: dashboard tutorial launcher contracts"
