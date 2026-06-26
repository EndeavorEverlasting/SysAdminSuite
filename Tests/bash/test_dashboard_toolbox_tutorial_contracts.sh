#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
index="$repo_root/dashboard/index.html"
tutorial="$repo_root/dashboard/js/toolbox-tutorial.js"
launcher="$repo_root/dashboard/js/launch-toolbox-tutorial.js"
app="$repo_root/dashboard/js/app.js"
bundle="$repo_root/dashboard/js/bundle.js"
host_bat="$repo_root/Launch-SysAdminSuiteDashboard.Host.bat"
writer="$repo_root/scripts/sas-write-toolbox-status.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$index" ]] || fail "dashboard/index.html missing"
[[ -f "$tutorial" ]] || fail "toolbox-tutorial.js missing"
[[ -f "$launcher" ]] || fail "launch-toolbox-tutorial.js missing"
[[ -f "$app" ]] || fail "app.js missing"
[[ -f "$bundle" ]] || fail "bundle.js missing"

for id in toolbox-hero toolbox-tutorial toolbox-checklist toolbox-status-banner; do
  grep -q "id=\"${id}\"" "$index" || fail "index.html missing #${id}"
done

grep -q 'sas-guide-glow' "$tutorial" || fail "toolbox-tutorial.js must use sas-guide-glow"
grep -q '__sasApplyToolboxStatus' "$tutorial" || fail "toolbox-tutorial.js must define __sasApplyToolboxStatus"
grep -q 'buildStepsFromStatus' "$tutorial" || fail "toolbox-tutorial.js must build dynamic steps"

grep -q 'toolbox-status.json' "$launcher" || fail "launch-toolbox-tutorial.js must fetch toolbox-status.json"
grep -q 'actionNeeded' "$launcher" || fail "launch-toolbox-tutorial.js must respect actionNeeded"
grep -q 'startRepoSetupWhenReady' "$launcher" || fail "launcher must fall back to repo setup when toolbox is clear"

grep -q 'initToolboxShell' "$app" || fail "app.js must define initToolboxShell"
grep -q 'window.startToolboxTutorial' "$app" || fail "app.js must expose startToolboxTutorial"
grep -q 'initToolboxTutorial' "$bundle" || fail "bundle must include initToolboxTutorial"

grep -q 'launch-toolbox-tutorial.js' "$index" || fail "index must load launch-toolbox-tutorial.js"
grep -q 'sas-write-toolbox-status.sh' "$host_bat" || fail "host launcher must invoke toolbox status writer"

grep -q 'dashboard/toolbox-status.json' "$repo_root/.gitignore" || fail ".gitignore must cover live toolbox status"

[[ -f "$repo_root/dashboard/samples/toolbox-status-missing-naabu.json" ]] || fail "missing naabu sample fixture"
[[ -f "$repo_root/docs/DASHBOARD_TOOLBOX_TUTORIAL.md" ]] || fail "DASHBOARD_TOOLBOX_TUTORIAL.md missing"

echo "OK: dashboard toolbox tutorial contracts"
