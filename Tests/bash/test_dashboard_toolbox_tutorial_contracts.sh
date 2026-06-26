#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

index_html="$repo_root/dashboard/index.html"
toolbox_js="$repo_root/dashboard/js/toolbox-tutorial.js"
launch_js="$repo_root/dashboard/js/launch-toolbox-tutorial.js"
repo_setup_launch_js="$repo_root/dashboard/js/launch-repo-setup-tutorial.js"
app_js="$repo_root/dashboard/js/app.js"
parsers_js="$repo_root/dashboard/js/parsers.js"
build_bundle="$repo_root/dashboard/build-bundle.js"
host_bat="$repo_root/Launch-SysAdminSuiteDashboard.Host.bat"
start_bat="$repo_root/START-HERE-SysAdminSuite-Dashboard.bat"
gitignore="$repo_root/.gitignore"

[[ -f "$toolbox_js" ]] || fail "missing toolbox tutorial JS"
[[ -f "$launch_js" ]] || fail "missing toolbox launch JS"

for needle in 'id="toolbox-status-banner"' 'id="toolbox-hero"' 'id="toolbox-checklist"' 'id="toolbox-tutorial"' 'id="hero-start-toolbox"'; do
  grep -Fq "$needle" "$index_html" || fail "dashboard index missing $needle"
done

grep -Fq 'sas-guide-glow' "$toolbox_js" || fail "toolbox tutorial does not apply guide glow"
grep -Fq '__sasApplyToolboxStatus' "$toolbox_js" || fail "toolbox tutorial missing status apply hook"
grep -Fq 'buildStepsFromStatus' "$toolbox_js" || fail "toolbox tutorial missing dynamic step builder"
grep -Fq 'toolbox-status.json?ts=' "$launch_js" || fail "toolbox launcher does not fetch runtime status JSON"
grep -Fq '__sasToolboxActionNeeded' "$launch_js" || fail "toolbox launcher missing toolbox-first precedence flag"
grep -Fq '__sasToolboxActionNeeded' "$repo_setup_launch_js" || fail "repo setup launcher does not respect toolbox-first precedence"
grep -Fq 'initToolboxTutorial' "$app_js" || fail "app.js does not initialize toolbox tutorial"
grep -Fq 'startToolboxTutorial' "$app_js" || fail "app.js missing toolbox hero shell"
grep -Fq 'toolbox-status' "$parsers_js" || fail "parsers missing toolbox-status type"
grep -Fq 'dashboard/js/toolbox-tutorial.js' "$build_bundle" || fail "bundle build missing toolbox tutorial"
grep -Fq 'sas-write-toolbox-status.sh' "$host_bat" || fail "host launcher does not write toolbox status"
grep -Fq 'SAS_UPDATE_STATE' "$start_bat" || fail "START-HERE does not set update state"
grep -Fq 'dashboard/toolbox-status.json' "$gitignore" || fail "runtime toolbox status is not ignored"

for fixture in toolbox-status-all-ok.json toolbox-status-missing-naabu.json toolbox-status-update-available.json; do
  [[ -f "$repo_root/dashboard/samples/$fixture" ]] || fail "missing sample fixture: $fixture"
  python -m json.tool "$repo_root/dashboard/samples/$fixture" >/dev/null || fail "invalid fixture JSON: $fixture"
done

[[ -f "$repo_root/docs/DASHBOARD_TOOLBOX_TUTORIAL.md" ]] || fail "DASHBOARD_TOOLBOX_TUTORIAL.md missing"

echo "PASS: Dashboard toolbox tutorial contracts"
