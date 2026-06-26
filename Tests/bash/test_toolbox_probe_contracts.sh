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

[[ -f "$manifest" ]] || fail "missing toolbox dependency manifest"
[[ -f "$probe" ]] || fail "missing toolbox probe"
[[ -f "$writer" ]] || fail "missing toolbox writer"

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

echo "PASS: Toolbox probe contracts"
#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
manifest="$repo_root/Config/toolbox-dependencies.json"
probe="$repo_root/scripts/sas-probe-toolbox.sh"
writer="$repo_root/scripts/sas-write-toolbox-status.sh"
dotnet_cfg="$repo_root/Config/dotnet-bootstrap.json"
naabu_cfg="$repo_root/Config/cybernet-naabu-profiles.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$manifest" ]] || fail "Config/toolbox-dependencies.json is missing"
[[ -x "$probe" || -f "$probe" ]] || fail "scripts/sas-probe-toolbox.sh is missing"
[[ -f "$writer" ]] || fail "scripts/sas-write-toolbox-status.sh is missing"

required_ids=(git_bash python pwsh powershell dotnet_aspnet dotnet_desktop naabu nmap)
for id in "${required_ids[@]}"; do
  grep -q "\"id\": \"${id}\"" "$manifest" || fail "manifest missing tool id: $id"
done

grep -qiE 'winget|choco' "$probe" "$writer" "$manifest" && fail "toolbox probe/writer must not reference winget or choco"

probe_json="$(bash "$probe" --dry-run)"
[[ -n "$probe_json" ]] || fail "probe produced no output"

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool <<< "$probe_json" >/dev/null
elif command -v python >/dev/null 2>&1; then
  python -m json.tool <<< "$probe_json" >/dev/null
else
  echo "$probe_json" | grep -q '"tools"' || fail "probe JSON missing tools array"
fi

grep -q '"tools"' <<< "$probe_json" || fail "probe JSON missing tools array"

dotnet_release="$(grep -o '"release"[[:space:]]*:[[:space:]]*"[^"]*"' "$dotnet_cfg" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')"
grep -q "\"pinnedVersion\": \"${dotnet_release}\"" "$manifest" || fail "manifest dotnet pin does not match dotnet-bootstrap release"

naabu_version="$(grep -o '"naabuVersion"[[:space:]]*:[[:space:]]*"[^"]*"' "$naabu_cfg" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')"
grep -q "\"pinnedVersion\": \"${naabu_version}\"" "$manifest" || fail "manifest naabu pin does not match cybernet-naabu-profiles"

tmp_out="$(mktemp)"
bash "$writer" --dry-run --update-state available --update-mode skipped > "$tmp_out"
grep -q '"actionNeeded": true' "$tmp_out" || fail "writer should set actionNeeded when update available"
grep -q '"updateState": "available"' "$tmp_out" || fail "writer should preserve updateState"
rm -f "$tmp_out"

grep -q 'dashboard/toolbox-status.json' "$repo_root/.gitignore" || fail ".gitignore must ignore dashboard/toolbox-status.json"

echo "OK: toolbox probe contracts"
