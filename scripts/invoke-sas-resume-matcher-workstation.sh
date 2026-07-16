#!/usr/bin/env bash
set -euo pipefail

action=Plan
apply=false
config_path=
app_root_override=
state_root=
output_path=
fixture_root=

usage() {
  cat <<'EOF'
Usage: invoke-sas-resume-matcher-workstation.sh [options]

Options:
  --action Plan|Apply|Start|Status|Stop|Validate
  --apply                         Required for Apply, Start, and Stop
  --config PATH                   Deployment profile JSON
  --app-root PATH                 Override the configured install path
  --state-root PATH               Runtime state root (default: XDG state)
  --output PATH                   Result JSON path
  --fixture-root PATH             Isolated no-network fixture adapter
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) action=${2:-}; shift 2 ;;
    --apply) apply=true; shift ;;
    --config) config_path=${2:-}; shift 2 ;;
    --app-root) app_root_override=${2:-}; shift 2 ;;
    --state-root) state_root=${2:-}; shift 2 ;;
    --output) output_path=${2:-}; shift 2 ;;
    --fixture-root) fixture_root=${2:-}; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$action" in
  Plan|Apply|Start|Status|Stop|Validate) ;;
  *) printf 'Unsupported action: %s\n' "$action" >&2; exit 2 ;;
esac

if [[ "$action" =~ ^(Apply|Start|Stop)$ ]] && ! $apply; then
  printf '%s requires --apply. Plan, Status, and Validate remain non-mutating defaults.\n' "$action" >&2
  exit 3
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
config_path=${config_path:-$repo_root/Config/resume-matcher-workstation.sample.json}
[[ -f "$config_path" ]] || { printf 'Deployment profile not found: %s\n' "$config_path" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'python3 is required to read the deployment profile.\n' >&2; exit 2; }

mapfile -d '' config_values < <(python3 - "$config_path" <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if data.get("schema_version") != "sas-resume-matcher-workstation/v1":
    raise SystemExit("unsupported deployment profile schema")
app = data["application"]
runtime = data["runtime"]
services = data["services"]
browser = data["browser"]
posture = data["posture"]
relative = app["install_path_relative_to_home"]
if pathlib.PurePosixPath(relative).is_absolute() or ".." in pathlib.PurePosixPath(relative).parts:
    raise SystemExit("unsafe install_path_relative_to_home")
if app["repository_url"] != "https://github.com/srbhr/Resume-Matcher.git":
    raise SystemExit("unapproved Resume Matcher repository URL")
if runtime["python_version"] != "3.13" or str(runtime["node_major"]) != "22":
    raise SystemExit("unsupported pinned runtime contract")
if posture["automatic_authentication"] or posture["write_api_key_to_env"]:
    raise SystemExit("deployment profile may not automate API authentication")
values = [
    app["repository_url"], app["repository_ref"], relative,
    app["backend_relative_path"], app["frontend_relative_path"],
    runtime["python_version"], str(runtime["node_major"]), runtime["nvm_version"],
    runtime["uv_installer_url"], runtime["nvm_repository_url"],
    services["tmux_session"], services["backend_window"], services["frontend_window"],
    str(services["backend_port"]), str(services["frontend_port"]),
    services["backend_health_path"], str(services["startup_timeout_seconds"]),
    browser["playwright_ubuntu_2604_strategy"], browser["system_browser_command"],
    browser["system_browser_package_url"],
]
for value in values:
    sys.stdout.write(str(value))
    sys.stdout.write("\0")
PY
)

(( ${#config_values[@]} == 20 )) || { printf 'Deployment profile did not yield the expected contract fields.\n' >&2; exit 2; }
repo_url=${config_values[0]}
repo_ref=${config_values[1]}
install_relative=${config_values[2]}
backend_relative=${config_values[3]}
frontend_relative=${config_values[4]}
python_version=${config_values[5]}
node_major=${config_values[6]}
nvm_version=${config_values[7]}
uv_installer_url=${config_values[8]}
nvm_repository_url=${config_values[9]}
tmux_session=${config_values[10]}
backend_window=${config_values[11]}
frontend_window=${config_values[12]}
backend_port=${config_values[13]}
frontend_port=${config_values[14]}
backend_health_path=${config_values[15]}
startup_timeout_seconds=${config_values[16]}
ubuntu_2604_strategy=${config_values[17]}
system_browser_command=${config_values[18]}
system_browser_package_url=${config_values[19]}

if [[ -n "$fixture_root" ]]; then
  fixture_root=$(mkdir -p "$fixture_root" && cd "$fixture_root" && pwd -P)
  home_root=$fixture_root/home
  mkdir -p "$home_root"
else
  home_root=$HOME
fi

if [[ -n "$app_root_override" ]]; then
  app_root=$app_root_override
else
  app_root=$home_root/$install_relative
fi
app_root=$(python3 - "$app_root" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)
backend_dir=$app_root/$backend_relative
frontend_dir=$app_root/$frontend_relative
state_root=${state_root:-${XDG_STATE_HOME:-$home_root/.local/state}/sysadminsuite/resume-matcher}
mkdir -p "$state_root"
output_path=${output_path:-$state_root/last-result.json}
state_file=$state_root/state.env

json_escape() {
  local value=${1:-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

bool_json() {
  [[ ${1:-false} == true ]] && printf true || printf false
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

backend_healthy=false
frontend_healthy=false
repo_present=false
repo_dirty=false
uv_available=false
node_available=false
python_ready=false
browser_ready=false
tmux_available=false
configuration_applied=false
install_completed=false
launcher_started=false
live_runtime=false

refresh_inventory() {
  [[ -d "$app_root/.git" ]] && repo_present=true || repo_present=false
  if $repo_present && [[ -n "$(git -C "$app_root" status --porcelain 2>/dev/null || true)" ]]; then
    repo_dirty=true
  else
    repo_dirty=false
  fi
  if [[ -r "$home_root/.local/bin/env" ]]; then
    # shellcheck disable=SC1090
    source "$home_root/.local/bin/env"
  fi
  command_exists uv && uv_available=true || uv_available=false
  command_exists tmux && tmux_available=true || tmux_available=false
  export NVM_DIR=$home_root/.nvm
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
  fi
  command_exists node && node_available=true || node_available=false
  [[ -x "$backend_dir/.venv/bin/python" ]] && python_ready=true || python_ready=false
  if command_exists "$system_browser_command" || [[ -d "$home_root/.cache/ms-playwright" ]]; then
    browser_ready=true
  else
    browser_ready=false
  fi
  if curl -fsS --max-time 3 "http://127.0.0.1:$backend_port$backend_health_path" >/dev/null 2>&1; then
    backend_healthy=true
  else
    backend_healthy=false
  fi
  if curl -fsS --max-time 3 "http://127.0.0.1:$frontend_port" >/dev/null 2>&1; then
    frontend_healthy=true
  else
    frontend_healthy=false
  fi
}

write_state() {
  umask 077
  cat > "$state_file" <<EOF
schema_version=sas-resume-matcher-workstation-state/v1
app_root=$app_root
repo_ref=$repo_ref
python_version=$python_version
node_major=$node_major
tmux_session=$tmux_session
configuration_applied=$configuration_applied
install_completed=$install_completed
fixture_mode=$([[ -n "$fixture_root" ]] && printf true || printf false)
EOF
}

emit_result() {
  local operation=$1 outcome=$2 lifecycle=$3 reason=$4 message=$5
  local fixture=false
  [[ -n "$fixture_root" ]] && fixture=true
  local payload
  payload=$(cat <<EOF
{"schema_version":"sas-resume-matcher-workstation-result/v1","workflow_id":"resume-matcher-workstation","operation":"$(json_escape "$operation")","outcome":"$(json_escape "$outcome")","lifecycle_state":"$(json_escape "$lifecycle")","reason_codes":["$(json_escape "$reason")"],"message":"$(json_escape "$message")","configuration":{"profile":"$(json_escape "$config_path")","application_root":"$(json_escape "$app_root")","api_key_automated":false,"fixture_mode":$(bool_json "$fixture")},"inventory":{"repo_present":$(bool_json "$repo_present"),"repo_dirty":$(bool_json "$repo_dirty"),"uv_available":$(bool_json "$uv_available"),"node_available":$(bool_json "$node_available"),"python_ready":$(bool_json "$python_ready"),"browser_ready":$(bool_json "$browser_ready"),"tmux_available":$(bool_json "$tmux_available"),"backend_healthy":$(bool_json "$backend_healthy"),"frontend_healthy":$(bool_json "$frontend_healthy")},"proof":{"install_completed":$(bool_json "$install_completed"),"configuration_applied":$(bool_json "$configuration_applied"),"launcher_started":$(bool_json "$launcher_started"),"backend_health_observed":$(bool_json "$backend_healthy"),"frontend_health_observed":$(bool_json "$frontend_healthy"),"live_runtime":$(bool_json "$live_runtime")}}
EOF
)
  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "$payload" > "$output_path"
  printf '%s\n' "$payload"
}

read_os_release() {
  os_id=unknown
  os_version=unknown
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id=${ID:-unknown}
    os_version=${VERSION_ID:-unknown}
  fi
}

ensure_fixture_tree() {
  mkdir -p "$backend_dir" "$frontend_dir" "$app_root/.git" "$home_root/.local/bin" "$home_root/.nvm"
  if [[ ! -f "$backend_dir/.env.example" ]]; then
    cat > "$backend_dir/.env.example" <<'EOF'
LLM_PROVIDER=openai
LLM_MODEL=gpt-5-nano-2025-08-07
LLM_API_KEY=sk-your-api-key-here
HOST=0.0.0.0
PORT=8000
FRONTEND_BASE_URL=http://localhost:3000
CORS_ORIGINS=["http://localhost:3000","http://127.0.0.1:3000"]
EOF
  fi
  mkdir -p "$backend_dir/.venv/bin" "$frontend_dir/node_modules" "$home_root/.cache/ms-playwright"
  : > "$backend_dir/.venv/bin/python"
  chmod +x "$backend_dir/.venv/bin/python"
}

ensure_base_packages() {
  read_os_release
  case "$os_id" in
    ubuntu|debian) ;;
    *) printf 'Unsupported distribution for automated Apply: %s %s\n' "$os_id" "$os_version" >&2; return 1 ;;
  esac
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl git build-essential tmux python3
}

ensure_uv() {
  if [[ -r "$home_root/.local/bin/env" ]]; then
    # shellcheck disable=SC1090
    source "$home_root/.local/bin/env"
  fi
  if command_exists uv; then return 0; fi
  local tmp installer
  tmp=$(mktemp -d)
  installer=$tmp/uv-install.sh
  curl -fsSL "$uv_installer_url" -o "$installer"
  HOME=$home_root sh "$installer"
  rm -rf "$tmp"
  [[ -r "$home_root/.local/bin/env" ]] && source "$home_root/.local/bin/env"
  command_exists uv
}

ensure_nvm_and_node() {
  export NVM_DIR=$home_root/.nvm
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    [[ ! -e "$NVM_DIR" || -d "$NVM_DIR" ]] || { printf 'NVM path exists and is not a directory: %s\n' "$NVM_DIR" >&2; return 1; }
    if [[ -d "$NVM_DIR/.git" ]]; then
      git -C "$NVM_DIR" fetch --tags --force origin "$nvm_version"
      git -C "$NVM_DIR" checkout --detach "$nvm_version"
    else
      rm -rf "$NVM_DIR"
      git clone --depth 1 --branch "$nvm_version" "$nvm_repository_url" "$NVM_DIR"
    fi
  fi
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  nvm install "$node_major"
  nvm alias default "$node_major"
  nvm use "$node_major"
  node --version
  npm --version
}

ensure_application_repo() {
  if [[ ! -e "$app_root" ]]; then
    mkdir -p "$(dirname "$app_root")"
    git clone --branch "$repo_ref" "$repo_url" "$app_root"
    return 0
  fi
  [[ -d "$app_root/.git" ]] || { printf 'Application path exists but is not a Git repository: %s\n' "$app_root" >&2; return 1; }
  local origin
  origin=$(git -C "$app_root" remote get-url origin)
  [[ "$origin" == "$repo_url" ]] || { printf 'Application origin mismatch: %s\n' "$origin" >&2; return 1; }
  if [[ -n "$(git -C "$app_root" status --porcelain)" ]]; then
    printf 'Application repository is dirty; preserving local work and refusing update: %s\n' "$app_root" >&2
    return 4
  fi
  git -C "$app_root" fetch origin "$repo_ref"
  git -C "$app_root" checkout "$repo_ref"
  git -C "$app_root" pull --ff-only origin "$repo_ref"
}

configure_backend_env() {
  [[ -f "$backend_dir/.env.example" ]] || { printf 'Missing backend .env.example: %s\n' "$backend_dir/.env.example" >&2; return 1; }
  if [[ ! -e "$backend_dir/.env" ]]; then
    cp "$backend_dir/.env.example" "$backend_dir/.env"
  fi
  python3 - "$backend_dir/.env" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("LLM_API_KEY=sk-your-api-key-here", "LLM_API_KEY=")
path.write_text(text, encoding="utf-8")
PY
  configuration_applied=true
}

ensure_python_dependencies() {
  source "$home_root/.local/bin/env"
  uv python install "$python_version"
  (
    cd "$backend_dir"
    uv sync --python "$python_version"
    uv run python --version
    uv run python -c "import fastapi, playwright; print('PASS: backend imports')"
  )
}

ensure_browser() {
  read_os_release
  if [[ "$os_id" == ubuntu && "$os_version" == 26.04 && "$ubuntu_2604_strategy" == system_chrome ]]; then
    if ! command_exists "$system_browser_command"; then
      local tmp package
      tmp=$(mktemp -d)
      package=$tmp/google-chrome-stable_current_amd64.deb
      curl -fsSL "$system_browser_package_url" -o "$package"
      sudo apt-get install -y "$package"
      rm -rf "$tmp"
    fi
    command_exists "$system_browser_command"
  else
    (
      cd "$backend_dir"
      uv run playwright install chromium
    )
  fi
}

ensure_frontend_dependencies() {
  export NVM_DIR=$home_root/.nvm
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  nvm use "$node_major"
  [[ -f "$frontend_dir/package-lock.json" ]] || { printf 'Missing frontend package-lock.json.\n' >&2; return 1; }
  (cd "$frontend_dir" && npm ci)
}

wait_for_runtime() {
  local deadline=$((SECONDS + startup_timeout_seconds))
  while (( SECONDS < deadline )); do
    refresh_inventory
    if $backend_healthy && $frontend_healthy; then return 0; fi
    sleep 2
  done
  return 1
}

start_runtime() {
  if [[ -n "$fixture_root" ]]; then
    launcher_started=false
    live_runtime=false
    return 0
  fi
  command_exists tmux || { printf 'tmux is required to start Resume Matcher.\n' >&2; return 1; }
  if tmux has-session -t "$tmux_session" 2>/dev/null; then
    wait_for_runtime
    launcher_started=true
    live_runtime=true
    return 0
  fi
  local uv_env nvm_script backend_command frontend_command
  uv_env=$(printf '%q' "$home_root/.local/bin/env")
  nvm_script=$(printf '%q' "$home_root/.nvm/nvm.sh")
  backend_command="cd $(printf '%q' "$backend_dir") && source $uv_env && RELOAD=true uv run app"
  frontend_command="export NVM_DIR=$(printf '%q' "$home_root/.nvm") && source $nvm_script && nvm use $(printf '%q' "$node_major") >/dev/null && cd $(printf '%q' "$frontend_dir") && npm run dev"
  tmux new-session -d -s "$tmux_session" -n "$backend_window" "$backend_command"
  tmux new-window -d -t "$tmux_session" -n "$frontend_window" "$frontend_command"
  launcher_started=true
  if wait_for_runtime; then
    live_runtime=true
    return 0
  fi
  return 1
}

stop_runtime() {
  if [[ -n "$fixture_root" ]]; then return 0; fi
  if tmux has-session -t "$tmux_session" 2>/dev/null; then
    tmux kill-session -t "$tmux_session"
  fi
}

validate_installation() {
  [[ -d "$backend_dir" && -d "$frontend_dir" ]] || return 1
  if [[ -n "$fixture_root" ]]; then
    [[ -f "$backend_dir/.env" ]] || return 1
    ! grep -Fq 'sk-your-api-key-here' "$backend_dir/.env" || return 1
    return 0
  fi
  source "$home_root/.local/bin/env"
  export NVM_DIR=$home_root/.nvm
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  nvm use "$node_major" >/dev/null
  [[ "$(cd "$backend_dir" && uv run python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" == "$python_version" ]] || return 1
  [[ "$(node --version)" == v${node_major}.* ]] || return 1
  (
    cd "$backend_dir"
    uv run python - <<'PY'
import asyncio
from playwright.async_api import async_playwright
from app.pdf import _launch_browser

async def main() -> None:
    async with async_playwright() as playwright:
        browser = await _launch_browser(playwright)
        print(f"PASS: Resume Matcher launched browser {browser.version}")
        await browser.close()

asyncio.run(main())
PY
  )
}

refresh_inventory

case "$action" in
  Plan)
    missing=()
    $repo_present || missing+=(application-repo)
    $uv_available || missing+=(uv)
    $node_available || missing+=(node-22)
    $python_ready || missing+=(python-3.13-environment)
    $browser_ready || missing+=(chromium-or-system-chrome)
    $tmux_available || missing+=(tmux)
    if ((${#missing[@]})); then
      emit_result plan action-required planned prerequisites-missing "Apply would install or configure: ${missing[*]}. API-key entry remains a manual Settings UI step."
    else
      emit_result plan success ready none 'Resume Matcher prerequisites appear present. Run Validate, then Start with the explicit mutation gate.'
    fi
    ;;
  Apply)
    if [[ -n "$fixture_root" ]]; then
      ensure_fixture_tree
      configure_backend_env
      install_completed=false
      write_state
      refresh_inventory
      configuration_applied=true
      emit_result apply success configured fixture-no-network 'Fixture Apply proved idempotent configuration without package installation, process launch, or network access.'
      exit 0
    fi
    ensure_base_packages
    ensure_uv
    ensure_nvm_and_node
    ensure_application_repo
    configure_backend_env
    ensure_python_dependencies
    ensure_browser
    ensure_frontend_dependencies
    install_completed=true
    write_state
    refresh_inventory
    install_completed=true
    configuration_applied=true
    emit_result apply success installed none 'Resume Matcher installed and configured. API credentials were not written; configure DeepSeek or another provider in the Settings UI.'
    ;;
  Start)
    validate_installation
    if start_runtime; then
      refresh_inventory
      if [[ -n "$fixture_root" ]]; then
        emit_result start success configured fixture-no-process-launch 'Fixture Start intentionally did not launch processes.'
      else
        launcher_started=true
        live_runtime=true
        emit_result start success running none "Resume Matcher is running at http://localhost:$frontend_port with backend health observed."
      fi
    else
      refresh_inventory
      emit_result start failure degraded startup-timeout 'Resume Matcher did not reach both bounded health checks. Inspect the tmux backend and frontend windows.'
      exit 1
    fi
    ;;
  Status)
    refresh_inventory
    if $backend_healthy && $frontend_healthy; then
      live_runtime=true
      emit_result status success running none "Resume Matcher is healthy at http://localhost:$frontend_port."
    elif $repo_present; then
      emit_result status action-required stopped runtime-not-running 'Resume Matcher is installed but one or both services are not healthy.'
    else
      emit_result status action-required absent application-not-installed 'Resume Matcher is not installed at the configured application root.'
    fi
    ;;
  Stop)
    stop_runtime
    refresh_inventory
    emit_result stop success stopped none 'The repo-owned Resume Matcher tmux session is stopped.'
    ;;
  Validate)
    if validate_installation; then
      refresh_inventory
      configuration_applied=true
      emit_result validate success ready none 'Pinned runtimes, backend imports, configuration safety, and browser launch fallback validated.'
    else
      refresh_inventory
      emit_result validate failure degraded validation-failed 'Resume Matcher validation failed. Run Plan and inspect the application and runtime state.'
      exit 1
    fi
    ;;
esac
