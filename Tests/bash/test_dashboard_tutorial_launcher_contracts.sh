#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cmd="$repo_root/Start-CybernetSurveyTutorial.cmd"
index="$repo_root/dashboard/index.html"
helper="$repo_root/dashboard/js/launch-cybernet-tutorial.js"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$cmd" ]] || fail "Start-CybernetSurveyTutorial.cmd is missing"
[[ -f "$index" ]] || fail "dashboard/index.html is missing"
[[ -f "$helper" ]] || fail "dashboard/js/launch-cybernet-tutorial.js is missing"

grep -q "dashboard\\index.html" "$cmd" || fail "launcher does not point at dashboard\\index.html"
grep -q "tutorial=cybernet" "$cmd" || fail "launcher does not request the Cybernet tutorial"
grep -q "launch-cybernet-tutorial.js" "$index" || fail "dashboard index does not include tutorial launcher helper"
grep -q "hero-start-survey" "$helper" || fail "helper does not target the existing Start Cybernet Survey button"
grep -q "URLSearchParams" "$helper" || fail "helper does not inspect query parameters"

if grep -qiE "naabu|nmap|credential|password|psexec|invoke-command" "$cmd"; then
  fail "double-click launcher must not run survey, credential, or remote command tooling"
fi

echo "PASS: dashboard tutorial launcher contracts"
