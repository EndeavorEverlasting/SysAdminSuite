#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

manifest="$repo_root/Config/toolbox-dependencies.json"
probe="$repo_root/scripts/sas-probe-toolbox.sh"
writer="$repo_root/scripts/sas-write-toolbox-status.sh"
dotnet_cfg="$repo_root/Config/dotnet-bootstrap.json"
naabu_profiles="$repo_root/survey/naabu_profiles.json"
gitignore="$repo_root/.gitignore"

[[ -f "$manifest" ]] || fail "missing toolbox dependency manifest"
[[ -f "$probe" ]] || fail "missing toolbox probe"
[[ -f "$writer" ]] || fail "missing toolbox writer"
[[ -f "$gitignore" ]] || fail "missing .gitignore"

for id in repo git_bash cmd powershell pwsh python dotnet_aspnet dotnet_desktop dotnet_sdk dashboard_host naabu nmap curl unzip; do
  grep -Fq "\"id\": \"$id\"" "$manifest" || fail "manifest missing tool id: $id"
done

grep -Fq '"release": "8.0.28"' "$dotnet_cfg" || fail "dotnet bootstrap release pin changed without contract update"
grep -Fq '"sdkVersion": "8.0.422"' "$dotnet_cfg" || fail "dotnet bootstrap SDK pin changed without contract update"
grep -Fq '"pinnedVersion": "8.0.28"' "$manifest" || fail "manifest missing .NET runtime pin"
grep -Fq '"pinnedVersion": "8.0.422"' "$manifest" || fail "manifest missing .NET SDK pin"
grep -Fq '"pinnedVersion": "2.6.1"' "$manifest" || fail "manifest missing naabu pin"
grep -Fiq 'low-noise survey discipline' "$naabu_profiles" || fail "naabu doctrine source missing low-noise language"

if grep -Eiq 'winget|choco|chocolatey' "$manifest" "$probe" "$writer"; then
  fail "toolbox probe path must not use winget/choco"
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

bash "$probe" --dry-run > "$tmp"
python -m json.tool "$tmp" >/dev/null || fail "probe did not emit valid JSON"
python - "$tmp" <<'PY' || exit 1
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
assert data["schema"] == 1
assert isinstance(data.get("tools"), list) and data["tools"]
assert all("status" in item for item in data["tools"])
assert data.get("repo", {}).get("updateState") is not None
PY

bash "$writer" --dry-run > "$tmp"
python - "$tmp" <<'PY' || exit 1
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
assert isinstance(data.get("actionNeeded"), bool)
summary = data.get("summary", {})
for key in ("total", "ok", "needsAction", "missing", "outdated", "blocked", "unknown"):
    assert key in summary, key
PY

bash "$writer" --dry-run --update-state available --update-mode skipped > "$tmp"
python - "$tmp" <<'PY' || exit 1
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
assert data.get("actionNeeded") is True
assert data.get("repo", {}).get("updateState") == "available"
PY

grep -Fq 'dashboard/toolbox-status.json' "$gitignore" || fail ".gitignore must ignore dashboard/toolbox-status.json"

echo "PASS: Toolbox probe contracts"
