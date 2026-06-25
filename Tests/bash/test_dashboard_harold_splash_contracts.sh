#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
index="$repo_root/dashboard/index.html"
app="$repo_root/dashboard/js/app.js"
bundle="$repo_root/dashboard/js/bundle.js"
asset="$repo_root/dashboard/assets/harold.jpg"
host_mime="$repo_root/src/SysAdminSuite.DashboardHost/DashboardStaticServer.cs"
server_py="$repo_root/server.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$asset" ]] || fail "dashboard/assets/harold.jpg is missing"
[[ -f "$index" ]] || fail "dashboard/index.html is missing"

grep -Fq 'id="harold-loading"' "$index" || fail "index.html missing Harold loading splash element"
grep -Fq 'assets/harold.jpg' "$index" || fail "index.html does not reference the Harold image"
grep -Fq 'window.SASHarold' "$index" || fail "index.html does not define the reusable SASHarold hook"

# In-app loading wait (xlsx) should summon Harold in both source and built bundle.
grep -Fq 'SASHarold' "$app" || fail "app.js does not call the SASHarold hook"
grep -Fq 'SASHarold' "$bundle" || fail "bundle.js is stale — run: node dashboard/build-bundle.js"

# JPEG MIME parity between the .NET host and the Python launcher.
grep -Fq '".jpg"' "$host_mime" || fail "DashboardStaticServer.cs missing .jpg MIME type"
grep -Fq '".jpg"' "$server_py" || fail "server.py missing .jpg MIME type"

echo "PASS: dashboard Harold splash contracts"
