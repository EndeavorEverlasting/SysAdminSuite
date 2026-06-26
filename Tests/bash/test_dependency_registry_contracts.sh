#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

manifest="$repo_root/Config/toolbox-dependencies.json"
probe="$repo_root/scripts/sas-probe-toolbox.sh"
dotnet_cfg="$repo_root/Config/dotnet-bootstrap.json"
naabu_cfg="$repo_root/Config/cybernet-naabu-profiles.json"
sources_cfg="$repo_root/Config/sources.yaml"
go_mod="$repo_root/probe/packet-expenditure/go.mod"
dashboard_csproj="$repo_root/src/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.csproj"

[[ -f "$manifest" ]] || fail "missing toolbox dependency manifest"
[[ -f "$dotnet_cfg" ]] || fail "missing dotnet bootstrap config"
[[ -f "$naabu_cfg" ]] || fail "missing cybernet naabu profiles"
[[ -f "$sources_cfg" ]] || fail "missing sources manifest"
[[ -f "$go_mod" ]] || fail "missing packet-expenditure go.mod"
[[ -f "$probe" ]] || fail "missing toolbox probe"

if grep -Eiq 'winget|choco|chocolatey' "$manifest" "$probe"; then
  fail "dependency registry path must not use winget/choco"
fi

python - "$manifest" "$dotnet_cfg" "$naabu_cfg" "$sources_cfg" "$go_mod" "$dashboard_csproj" <<'PY' || exit 1
import json
import re
import sys

manifest_path, dotnet_path, naabu_path, sources_path, go_mod_path, csproj_path = sys.argv[1:]

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)

tools = manifest.get("tools", [])
if not tools:
    raise SystemExit("manifest has no tools")

allowed_categories = {"runtime", "build", "library", "field-tool", "app", "meta"}
allowed_required_for = {"source-build", "field-release", "ci", "runtime"}

pins = {}
registry_only_ids = set()

for tool in tools:
    tool_id = tool.get("id")
    for field in ("id", "displayName", "tier", "category", "workflows"):
        if not tool.get(field):
            raise SystemExit(f"tool missing required field {field}: {tool_id!r}")
    if tool["category"] not in allowed_categories:
        raise SystemExit(f"invalid category for {tool_id}: {tool['category']!r}")
    required_for = tool.get("requiredFor") or []
    if not isinstance(required_for, list) or not required_for:
        raise SystemExit(f"tool {tool_id} must declare requiredFor")
    bad = set(required_for) - allowed_required_for
    if bad:
        raise SystemExit(f"tool {tool_id} has invalid requiredFor values: {sorted(bad)}")
    if tool.get("registryOnly"):
        registry_only_ids.add(tool_id)
    pins[tool_id] = tool.get("pinnedVersion")

with open(dotnet_path, encoding="utf-8") as handle:
    dotnet = json.load(handle)

release = dotnet.get("release")
sdk_version = dotnet.get("sdkVersion")
if pins.get("dotnet_aspnet") != release:
    raise SystemExit(f"dotnet_aspnet pin {pins.get('dotnet_aspnet')!r} != bootstrap release {release!r}")
if pins.get("dotnet_desktop") != release:
    raise SystemExit(f"dotnet_desktop pin {pins.get('dotnet_desktop')!r} != bootstrap release {release!r}")
if pins.get("dotnet_sdk") != sdk_version:
    raise SystemExit(f"dotnet_sdk pin {pins.get('dotnet_sdk')!r} != bootstrap sdkVersion {sdk_version!r}")

with open(naabu_path, encoding="utf-8") as handle:
    naabu = json.load(handle)
naabu_version = naabu.get("naabuVersion")
if pins.get("naabu") != naabu_version:
    raise SystemExit(f"naabu pin {pins.get('naabu')!r} != cybernet profile naabuVersion {naabu_version!r}")

go_text = open(go_mod_path, encoding="utf-8").read()
go_match = re.search(r"^go\s+(\S+)", go_text, re.MULTILINE)
if not go_match:
    raise SystemExit("go.mod missing go directive")
if pins.get("go") != go_match.group(1):
    raise SystemExit(f"go pin {pins.get('go')!r} != go.mod directive {go_match.group(1)!r}")

lib_match = re.search(
    r"require\s+github\.com/projectdiscovery/naabu/v2\s+v(\S+)",
    go_text,
)
if not lib_match:
    raise SystemExit("go.mod missing naabu/v2 require line")
if pins.get("naabu_v2_library") != lib_match.group(1):
    raise SystemExit(
        f"naabu_v2_library pin {pins.get('naabu_v2_library')!r} "
        f"!= go.mod require {lib_match.group(1)!r}"
    )

sources_text = open(sources_path, encoding="utf-8").read()

def version_from_block(marker):
    block_match = re.search(
        rf'^\s+- name: {re.escape(marker)}\s*$.*?(?=^\s+- name:|\Z)',
        sources_text,
        re.MULTILINE | re.DOTALL,
    )
    if not block_match:
        raise SystemExit(f"sources.yaml missing block matching {marker!r}")
    version_match = re.search(r'^\s+version:\s*"([^"]+)"', block_match.group(0), re.MULTILINE)
    if not version_match:
        raise SystemExit(f"sources.yaml block for {marker!r} missing pinned version")
    return version_match.group(1)

for tool_id, marker, pin in (
    ("pwsh", "PowerShell 7-x64", pins.get("pwsh")),
    ("python", "Python 3.13 x64", pins.get("python")),
):
    found = version_from_block(marker)
    if found != pin:
        raise SystemExit(f"{tool_id} pin {pin!r} != sources.yaml version {found!r}")

csproj_text = open(csproj_path, encoding="utf-8").read()
tfm_match = re.search(r"<TargetFramework>([^<]+)</TargetFramework>", csproj_text)
if not tfm_match:
    raise SystemExit("dashboard host csproj missing TargetFramework")
if pins.get("dotnet_tfm") != tfm_match.group(1):
    raise SystemExit(
        f"dotnet_tfm pin {pins.get('dotnet_tfm')!r} != csproj TFM {tfm_match.group(1)!r}"
    )
PY

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

bash "$probe" --dry-run > "$tmp"
python -m json.tool "$tmp" >/dev/null || fail "probe did not emit valid JSON"

python - "$tmp" "$manifest" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    probe_data = json.load(handle)

with open(sys.argv[2], encoding="utf-8") as handle:
    manifest = json.load(handle)

registry_only = {t["id"] for t in manifest.get("tools", []) if t.get("registryOnly")}
probed_ids = {t["id"] for t in probe_data.get("tools", [])}

if registry_only & probed_ids:
    raise SystemExit(f"registryOnly tools must not appear in probe output: {sorted(registry_only & probed_ids)}")

expected_live = {
    "repo", "git_bash", "cmd", "powershell", "pwsh", "python",
    "dotnet_aspnet", "dotnet_desktop", "dotnet_sdk", "dashboard_host",
    "naabu", "nmap", "curl", "unzip",
}
if probed_ids != expected_live:
    missing = expected_live - probed_ids
    extra = probed_ids - expected_live
    raise SystemExit(f"probe id drift: missing={sorted(missing)} extra={sorted(extra)}")
PY

echo "PASS: Dependency registry contracts"
