#!/usr/bin/env bash
set -euo pipefail

fixture=""
output=""
lifecycle_output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture) fixture="${2:-tmux-session-healthy}"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --lifecycle-output) lifecycle_output="$2"; shift 2 ;;
    --help) printf 'Usage: %s [--fixture SCENARIO] [--output PATH] [--lifecycle-output PATH]\n' "$(basename "$0")"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command_state() {
  local name="$1" version_arg="${2:---version}"
  if command -v "$name" >/dev/null 2>&1; then
    local version
    version=$("$name" "$version_arg" 2>/dev/null | head -n 1 || true)
    printf 'true\t%s\tsystem-path' "$version"
  else
    printf 'false\t\tmissing'
  fi
}

agent_state() {
  local name="$1" kind path_class backend
  kind=$(type -t "$name" 2>/dev/null || true)
  case "$kind" in
    alias) path_class=alias-only; backend=native ;;
    function) path_class=alias-only; backend=native ;;
    file) kind=executable; path_class=system-path; backend=native ;;
    *) kind=missing; path_class=missing; backend=missing ;;
  esac
  printf '%s\t%s\t%s' "$kind" "$path_class" "$backend"
}

if [[ -z "$fixture" ]]; then
  detected_context=linux-native
  if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then detected_context=windows-wsl; fi
  host_platform=linux
  IFS=$'\t' read -r wez_present wez_version wez_path <<<"$(command_state wezterm --version)"
  IFS=$'\t' read -r gui_present gui_version gui_path <<<"$(command_state wezterm-gui --version)"
  IFS=$'\t' read -r tmux_present tmux_version tmux_path <<<"$(command_state tmux -V)"
  sessions=""
  socket=missing
  if [[ "$tmux_present" == true ]]; then
    sessions=$(tmux list-sessions -F '#S' 2>/dev/null || true)
    [[ -n "$sessions" ]] && socket=present
  fi
  inside_tmux=false; [[ -n "${TMUX:-}" ]] && inside_tmux=true
  config_class=missing; workspace_configured=false; font_name=""; font_availability=not-configured
  if [[ -f "$HOME/.wezterm.lua" ]]; then
    config_class=user-home
    grep -q 'tmux: Development' "$HOME/.wezterm.lua" && workspace_configured=true || true
    font_name=$(sed -n 's/.*font.*["'"']\([^"'"']*\)["'"'].*/\1/p' "$HOME/.wezterm.lua" | head -n 1)
    [[ -n "$font_name" ]] && font_availability=unknown
  fi
  IFS=$'\t' read -r opencode_kind opencode_path opencode_backend <<<"$(agent_state opencode)"
  IFS=$'\t' read -r agy_kind agy_path agy_backend <<<"$(agent_state agy)"
  IFS=$'\t' read -r goose_kind goose_path goose_backend <<<"$(agent_state goose)"
  export SAS_FIXTURE="" SAS_HOST_PLATFORM="$host_platform" SAS_CONTEXT="$detected_context"
  export SAS_WEZ_PRESENT="$wez_present" SAS_WEZ_VERSION="$wez_version" SAS_WEZ_PATH="$wez_path"
  export SAS_GUI_PRESENT="$gui_present" SAS_GUI_VERSION="$gui_version" SAS_GUI_PATH="$gui_path"
  export SAS_TMUX_PRESENT="$tmux_present" SAS_TMUX_VERSION="$tmux_version" SAS_TMUX_SOCKET="$socket" SAS_TMUX_SESSIONS="$sessions" SAS_INSIDE_TMUX="$inside_tmux"
  export SAS_CONFIG_CLASS="$config_class" SAS_WORKSPACE_CONFIGURED="$workspace_configured" SAS_FONT_NAME="$font_name" SAS_FONT_AVAILABILITY="$font_availability"
  export SAS_OPENCODE="$opencode_kind|$opencode_path|$opencode_backend" SAS_AGY="$agy_kind|$agy_path|$agy_backend" SAS_GOOSE="$goose_kind|$goose_path|$goose_backend"
else
  export SAS_FIXTURE="$fixture"
fi

json=$(python3 - <<'PY'
import datetime, json, os

def command(present=False, version=None, path="missing"):
    return {"present": bool(present), "version": version or None, "path_class": path}

def agent(agent_id, packed="missing|missing|missing"):
    kind, path, backend = packed.split("|")
    return {"agent_id": agent_id, "resolution_kind": kind, "backend": backend,
            "command_path_class": path, "version": None, "authentication_readiness": "unknown",
            "interactive_smoke": {"attempted": False, "status": "not-attempted"}}

def tmux(present=False, version=None, socket="unknown", sessions=None, inside=False):
    return {"present": present, "version": version, "server_socket": socket,
            "sessions": sessions or [], "inside_tmux": inside}

fixture = os.environ.get("SAS_FIXTURE", "")
proof = "Read-only inventory proves detected state only; command presence is not authentication, session presence is not persistence, and no interactive smoke was attempted."
if fixture:
    missing = [agent(x) for x in ("opencode", "agy", "goose")]
    native = {"id":"windows-native","available":True,"health":"healthy","shell":"pwsh",
              "backend":{"kind":"windows-native","distribution":None,"distribution_state":"not-applicable","docker_only":False,"tmux":tmux(socket="not-applicable")},"agents":missing}
    wsl = {"id":"windows-wsl","available":True,"health":"healthy","shell":"bash",
           "backend":{"kind":"wsl","distribution":"Ubuntu","distribution_state":"running","docker_only":False,"tmux":tmux(True,"tmux 3.6","present",["dev"])},"agents":[agent(x) for x in ("opencode","agy","goose")]}
    data={"schema_version":"sas-developer-workstation-inventory/v2","generated_at":"2026-07-15T00:00:00Z","host_platform":"windows","detected_context":"windows-native",
          "terminal":{"wezterm_cli":command(True,"fixture","system-path"),"wezterm_gui":command(True,"fixture","system-path"),"config_path_class":"user-home","default_workspace":{"configured":True,"name":"tmux: Development"},"font":{"configured_name":None,"availability":"not-configured"}},
          "domains":[native,wsl],"workspace_service":{"keepalive":"healthy","pid_file":"healthy","shortcut":"present","start_script":"present","stop_script":"present"},
          "selected_backend":"windows-wsl","lifecycle":{"outcome":"success","state":"session-running","reason_codes":["none"]},"proof_ceiling":proof}
    if fixture == "no-wsl":
        wsl.update(available=False, health="unavailable"); wsl["backend"].update(distribution=None,distribution_state="unknown",tmux=tmux()); data.update(selected_backend=None,lifecycle={"outcome":"action-required","state":"absent","reason_codes":["no-wsl-distro"]})
    elif fixture == "docker-only-wsl":
        wsl.update(available=False, health="unavailable"); wsl["backend"].update(distribution="docker-desktop",docker_only=True,tmux=tmux()); data.update(selected_backend=None,lifecycle={"outcome":"action-required","state":"absent","reason_codes":["docker-only-distro"]})
    elif fixture == "wsl-stops":
        wsl["health"]="degraded"; wsl["backend"].update(distribution_state="stopped",tmux=tmux()); data["lifecycle"]={"outcome":"partial","state":"installed","reason_codes":["wsl-stopped"]}
    elif fixture == "keepalive-stale":
        data["workspace_service"].update(keepalive="stale",pid_file="stale"); data["lifecycle"]={"outcome":"partial","state":"session-running","reason_codes":["keepalive-stale"]}
    elif fixture == "windows-bridge-only":
        wsl["agents"][0]=agent("opencode","wrapper|windows-interop|bridge"); data["lifecycle"]={"outcome":"partial","state":"session-running","reason_codes":["windows-only-agent-bridge"]}
    elif fixture == "wsl-native-agent": wsl["agents"][0]=agent("opencode","executable|system-path|native")
    elif fixture == "invalid-font":
        data["terminal"]["font"]={"configured_name":"JetBrainsMono Nerd Font","availability":"unavailable"}; data["lifecycle"]={"outcome":"partial","state":"session-running","reason_codes":["unavailable-font"]}
    elif fixture == "cli-gui-mismatch":
        data["terminal"]["wezterm_gui"]=command(); data["lifecycle"]={"outcome":"failure","state":"failed","reason_codes":["wezterm-cli-gui-confusion"]}
else:
    b=lambda name: os.environ.get(name,"false").lower()=="true"
    sessions=[x for x in os.environ.get("SAS_TMUX_SESSIONS","").splitlines() if x]
    context=os.environ["SAS_CONTEXT"]
    domain_id="windows-wsl" if context=="windows-wsl" else "linux-native"
    backend_kind="wsl" if context=="windows-wsl" else "native-linux"
    agents=[agent("opencode",os.environ["SAS_OPENCODE"]),agent("agy",os.environ["SAS_AGY"]),agent("goose",os.environ["SAS_GOOSE"])]
    has_tmux=b("SAS_TMUX_PRESENT")
    reasons=[] if has_tmux else ["tmux-missing"]
    data={"schema_version":"sas-developer-workstation-inventory/v2","generated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"host_platform":"linux","detected_context":context,
          "terminal":{"wezterm_cli":command(b("SAS_WEZ_PRESENT"),os.environ.get("SAS_WEZ_VERSION"),os.environ.get("SAS_WEZ_PATH","missing")),"wezterm_gui":command(b("SAS_GUI_PRESENT"),os.environ.get("SAS_GUI_VERSION"),os.environ.get("SAS_GUI_PATH","missing")),"config_path_class":os.environ["SAS_CONFIG_CLASS"],"default_workspace":{"configured":b("SAS_WORKSPACE_CONFIGURED"),"name":"tmux: Development" if b("SAS_WORKSPACE_CONFIGURED") else None},"font":{"configured_name":os.environ.get("SAS_FONT_NAME") or None,"availability":os.environ["SAS_FONT_AVAILABILITY"]}},
          "domains":[{"id":domain_id,"available":True,"health":"healthy" if has_tmux else "degraded","shell":"bash","backend":{"kind":backend_kind,"distribution":None,"distribution_state":"not-applicable" if context=="linux-native" else "running","docker_only":False,"tmux":tmux(has_tmux,os.environ.get("SAS_TMUX_VERSION") or None,os.environ["SAS_TMUX_SOCKET"],sessions,b("SAS_INSIDE_TMUX"))},"agents":agents}],
          "workspace_service":{"keepalive":"not-applicable","pid_file":"not-applicable","shortcut":"not-applicable","start_script":"unknown","stop_script":"unknown"},"selected_backend":domain_id,
          "lifecycle":{"outcome":"success" if not reasons else "partial","state":"session-running" if "dev" in sessions else ("tmux-available" if has_tmux else "installed"),"reason_codes":reasons or ["none"]},"proof_ceiling":proof}
print(json.dumps(data, indent=2))
PY
)

if [[ -n "$output" ]]; then mkdir -p "$(dirname "$output")"; printf '%s\n' "$json" > "$output"; else printf '%s\n' "$json"; fi

if [[ -n "$lifecycle_output" ]]; then
  mkdir -p "$(dirname "$lifecycle_output")"
  INVENTORY_JSON="$json" SAS_FIXTURE="$fixture" python3 - "$lifecycle_output" <<'PY'
import json, os, pathlib, sys
inventory=json.loads(os.environ["INVENTORY_JSON"]); fixture=os.environ.get("SAS_FIXTURE","")
result={"schema_version":"sas-developer-workstation-lifecycle-result/v1","workflow_id":"developer-workstation","run_id":f"fixture-{fixture}" if fixture else "inventory-live","operation":"inventory","outcome":inventory["lifecycle"]["outcome"],"lifecycle_state":inventory["lifecycle"]["state"],"reason_codes":inventory["lifecycle"]["reason_codes"],"message":"Read-only developer workstation inventory completed.","artifacts":[{"role":"inventory","path_class":"temporary-fixture" if fixture else "repo-ignored-run","tracked":False,"contains_live_data":not bool(fixture)}],"proof":{"install_completed":False,"config_applied":False,"launcher_started":False,"tmux_attached":False,"command_acknowledged":False,"behavior_observed":False,"persistence_observed":False,"live_runtime":False,"operator_accepted":False}}
pathlib.Path(sys.argv[1]).write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
PY
fi
