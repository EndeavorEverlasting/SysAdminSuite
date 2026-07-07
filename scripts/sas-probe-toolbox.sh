#!/usr/bin/env bash
# Read-only toolbox probe: checks suite dependencies and emits JSON status.
set -euo pipefail

SAS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh" ]]; then
  SAS_REPO_ROOT="$(cd "$SAS_SCRIPT_DIR/../.." && pwd)"
fi
# shellcheck source=survey/lib/sas-network-guard.sh
source "$SAS_REPO_ROOT/survey/lib/sas-network-guard.sh"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${REPO_ROOT}/Config/toolbox-dependencies.json"

usage() {
  cat <<'USAGE'
Usage: bash scripts/sas-probe-toolbox.sh [--dry-run]

Probes each tool listed in Config/toolbox-dependencies.json and prints JSON
status to stdout. The probe is informational and never mutates the machine.

Options:
  --dry-run   Alias for normal run; probe is always read-only
  -h, --help  Show help
USAGE
}

log() { printf '[sas-probe-toolbox] %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log "Unknown argument: $1"; usage; exit 0 ;;
  esac
done

if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_NMAP:-0}" != "1" ]]; then
  sas_require_northwell_wifi
fi

if [[ ! -f "$MANIFEST" ]]; then
  log "Missing manifest: $MANIFEST"
  printf '{"schema":1,"error":"missing_manifest","repo":{"updateState":"unknown","updateMode":"unknown"},"tools":[]}\n'
  exit 0
fi

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  return 1
}

export REPO_ROOT
export SAS_UPDATE_STATE="${SAS_UPDATE_STATE:-unknown}"
export SAS_UPDATE_MODE="${SAS_UPDATE_MODE:-unknown}"

PY="$(find_python)" || {
  log "Python required for JSON output"
  printf '{"schema":1,"error":"python_required","repo":{"updateState":"unknown","updateMode":"unknown"},"tools":[]}\n'
  exit 0
}

"$PY" - "$MANIFEST" <<'PY'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

manifest_path = sys.argv[1]
repo_root = os.environ.get("REPO_ROOT", ".")
dotnet_cfg_path = os.path.join(repo_root, "Config", "dotnet-bootstrap.json")
naabu_runtime_cfg_path = os.path.join(repo_root, "Config", "cybernet-naabu-profiles.json")
naabu_doctrine_cfg_path = os.path.join(repo_root, "survey", "naabu_profiles.json")


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return {} if default is None else default


def run(argv, timeout=15):
    try:
        out = subprocess.check_output(argv, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        return out.strip(), 0
    except subprocess.CalledProcessError as exc:
        return (exc.output or "").strip(), exc.returncode
    except Exception as exc:
        return str(exc), 1


def bash_capture(command):
    return run(["bash", "-lc", command])


def semver_tuple(value):
    if not value:
        return ()
    parts = []
    for piece in re.split(r"[.\-+_\s]", str(value)):
        if not piece:
            continue
        match = re.match(r"(\d+)", piece)
        if match:
            parts.append(int(match.group(1)))
    return tuple(parts)


def compare_version(found, pinned):
    if not pinned:
        return "ok"
    if not found:
        return "missing"
    found_tuple = semver_tuple(found)
    pinned_tuple = semver_tuple(pinned)
    if not found_tuple or not pinned_tuple:
        return "unknown"
    return "ok" if found_tuple >= pinned_tuple else "outdated"


def version_from_text(text):
    match = re.search(r"(\d+\.\d+\.\d+(?:\.\d+)?)", text or "")
    return match.group(1) if match else ""


def windows_program_files():
    raw = os.environ.get("ProgramFiles") or r"C:\Program Files"
    return raw.replace("\\", "/")


def command_path(*names):
    command = " || ".join(f"command -v {name}" for name in names)
    out, rc = bash_capture(command)
    if rc == 0 and out:
        return out.splitlines()[0]
    return ""


def dotnet_path():
    path = command_path("dotnet.exe", "dotnet")
    if path:
        return path
    for candidate in ("/c/Program Files/dotnet/dotnet.exe", "/c/Program Files (x86)/dotnet/dotnet.exe"):
        if os.path.isfile(candidate):
            return candidate
    return ""


def git_bash_path():
    pf = windows_program_files()
    for candidate in (f"{pf}/Git/bin/bash.exe", "/c/Program Files/Git/bin/bash.exe"):
        if os.path.isfile(candidate):
            return candidate
    return command_path("bash.exe", "bash")


def host_path():
    candidates = [
        "app/bin/SysAdminSuite.DashboardHost.exe",
        "dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe",
        "tools/publish/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.exe",
        "src/SysAdminSuite.DashboardHost/bin/Release/net8.0-windows/SysAdminSuite.DashboardHost.exe",
        "src/SysAdminSuite.DashboardHost/bin/Debug/net8.0-windows/SysAdminSuite.DashboardHost.exe",
    ]
    for rel in candidates:
        candidate = os.path.join(repo_root, rel)
        if os.path.isfile(candidate):
            return candidate
    return ""


def field_release_present():
    return os.path.isfile(os.path.join(repo_root, "app", "bin", "SysAdminSuite.DashboardHost.exe"))


def naabu_path():
    path = command_path("naabu.exe", "naabu")
    if path:
        return path
    candidate = os.path.join(repo_root, "bin", "naabu.exe")
    return candidate if os.path.isfile(candidate) else ""


def ensure_text(ensure, default=""):
    if not ensure:
        return default
    if ensure.get("script"):
        return f"bash {ensure['script']}"
    return ensure.get("action") or ensure.get("note") or default


def hint_for(tool, status):
    hints = tool.get("statusHints") or {}
    return hints.get(status) or hints.get("default") or ""


manifest = load_json(manifest_path)
dotnet_cfg = load_json(dotnet_cfg_path)
naabu_runtime_cfg = load_json(naabu_runtime_cfg_path)
naabu_doctrine_cfg = load_json(naabu_doctrine_cfg_path)

naabu_version = (
    naabu_runtime_cfg.get("naabuVersion")
    or naabu_doctrine_cfg.get("naabuVersion")
    or manifest.get("naabuVersion")
    or "2.6.1"
)

pinned_from_config = {
    "dotnet_aspnet": dotnet_cfg.get("release", "8.0.28"),
    "dotnet_desktop": dotnet_cfg.get("release", "8.0.28"),
    "dotnet_sdk": dotnet_cfg.get("sdkVersion", "8.0.422"),
    "naabu": naabu_version,
}

update_state = os.environ.get("SAS_UPDATE_STATE") or "unknown"
update_mode = os.environ.get("SAS_UPDATE_MODE") or "unknown"
tools = []

for tool in manifest.get("tools", []):
    if tool.get("registryOnly"):
        continue
    tool_id = tool.get("id", "")
    pinned = tool.get("pinnedVersion")
    if not pinned:
        pinned = pinned_from_config.get(tool_id)
    ensure = tool.get("ensure") or {}
    entry = {
        "id": tool_id,
        "displayName": tool.get("displayName") or tool_id,
        "tier": tool.get("tier", "recommended"),
        "workflows": tool.get("workflows", []),
        "pinnedVersion": pinned or "",
        "found": False,
        "version": "",
        "path": "",
        "status": "unknown",
        "nextAction": "",
        "fixCommand": "",
        "installDoc": tool.get("installDoc") or "",
        "hint": "",
    }

    if tool_id == "repo":
        entry["found"] = True
        if update_state in {"available", "manual_review"}:
            entry["status"] = update_state
            entry["nextAction"] = ensure_text(ensure, "Re-run START-HERE-SysAdminSuite-Dashboard.bat.")
        else:
            entry["status"] = "ok"

    elif tool_id == "git_bash":
        path = git_bash_path()
        entry["found"] = bool(path)
        entry["path"] = path
        entry["status"] = "ok" if path else "missing"
        if not path:
            entry["nextAction"] = ensure_text(ensure, "Install Git for Windows or use the field release package.")

    elif tool_id == "cmd":
        path = command_path("cmd.exe")
        if not path and os.path.isfile("/c/Windows/System32/cmd.exe"):
            path = "/c/Windows/System32/cmd.exe"
        entry["found"] = bool(path)
        entry["path"] = path
        entry["status"] = "ok" if path else "missing"

    elif tool_id == "powershell":
        path = command_path("powershell.exe")
        entry["found"] = bool(path)
        entry["path"] = path
        entry["status"] = "ok" if path else "missing"

    elif tool_id == "pwsh":
        path = command_path("pwsh.exe", "pwsh")
        if not path and os.path.isfile("/c/Program Files/PowerShell/7/pwsh.exe"):
            path = "/c/Program Files/PowerShell/7/pwsh.exe"
        version = ""
        if path:
            out, _ = run([path, "-Version"])
            version = version_from_text(out)
        entry["found"] = bool(path)
        entry["path"] = path
        entry["version"] = version
        entry["status"] = compare_version(version, pinned) if path else "missing"
        if entry["status"] != "ok":
            entry["nextAction"] = ensure_text(ensure, "bash bash/apps/sas-install-apps.sh")

    elif tool_id == "python":
        path = command_path("python3.exe", "python3", "python.exe", "python")
        version = ""
        if path:
            out, _ = run([path, "--version"])
            version = version_from_text(out)
        entry["found"] = bool(path)
        entry["path"] = path
        entry["version"] = version
        entry["status"] = compare_version(version, pinned) if path else "missing"
        if entry["status"] != "ok":
            entry["nextAction"] = ensure_text(ensure, "bash bash/apps/sas-install-apps.sh")

    elif tool_id in {"dotnet_aspnet", "dotnet_desktop"}:
        dotnet = dotnet_path()
        framework = "Microsoft.AspNetCore.App" if tool_id == "dotnet_aspnet" else "Microsoft.WindowsDesktop.App"
        version = ""
        if dotnet:
            out, _ = run([dotnet, "--list-runtimes"])
            for line in (out or "").splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[0] == framework:
                    version = parts[1]
                    break
        entry["found"] = bool(version)
        entry["path"] = dotnet
        entry["version"] = version
        entry["status"] = compare_version(version, pinned) if version else "missing"
        if entry["status"] != "ok":
            entry["nextAction"] = ensure_text(ensure, "bash scripts/ensure-dotnet-runtime.sh")

    elif tool_id == "dotnet_sdk":
        if field_release_present() and tool.get("fieldReleaseNotApplicable"):
            entry["found"] = True
            entry["status"] = "not_applicable"
            entry["nextAction"] = "Field release includes a pre-built host; SDK not required."
        else:
            dotnet = dotnet_path()
            version = ""
            if dotnet:
                out, _ = run([dotnet, "--list-sdks"])
                for line in (out or "").splitlines():
                    candidate = line.split()[0] if line.split() else ""
                    if candidate.startswith("8."):
                        version = candidate
                        break
            entry["found"] = bool(version)
            entry["path"] = dotnet
            entry["version"] = version
            entry["status"] = compare_version(version, pinned) if version else "missing"
            if entry["status"] != "ok":
                entry["nextAction"] = ensure_text(ensure, "bash scripts/ensure-dotnet-sdk.sh")

    elif tool_id == "dashboard_host":
        path = host_path()
        entry["found"] = bool(path)
        entry["path"] = path
        entry["status"] = "ok" if path else "missing"
        if not path:
            entry["nextAction"] = ensure_text(ensure, "Re-run START-HERE-SysAdminSuite-Dashboard.bat.")

    elif tool_id == "naabu":
        path = naabu_path()
        version = ""
        if path:
            out, _ = run([path, "-version"])
            version = version_from_text(out)
        entry["found"] = bool(path)
        entry["path"] = path
        entry["version"] = version
        entry["status"] = compare_version(version, pinned) if path else "missing"
        if entry["status"] != "ok":
            entry["nextAction"] = ensure_text(ensure, "bash survey/sas-ensure-naabu.sh")

    elif tool_id == "nmap":
        path = command_path("nmap.exe", "nmap")
        version = ""
        if path:
            out, _ = run([path, "--version"])
            version = version_from_text(out)
        entry["found"] = bool(path)
        entry["path"] = path
        entry["version"] = version
        entry["status"] = "ok" if path else "missing"
        if not path:
            entry["nextAction"] = ensure_text(ensure, "Install nmap manually and confirm it is on PATH.")

    elif tool_id in {"curl", "unzip"}:
        path = command_path(tool_id)
        entry["found"] = bool(path)
        entry["path"] = path
        entry["status"] = "ok" if path else "missing"
        if not path:
            entry["nextAction"] = ensure_text(ensure, "Install or repair Git for Windows.")

    if entry["status"] != "ok":
        entry["hint"] = hint_for(tool, entry["status"])
        if not entry["fixCommand"]:
            action = ensure_text(ensure)
            if action.startswith("bash "):
                entry["fixCommand"] = action
    tools.append(entry)

payload = {
    "schema": 1,
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "repo": {
        "updateState": update_state,
        "updateMode": update_mode,
    },
    "tools": tools,
}

print(json.dumps(payload, indent=2))
PY

exit 0
