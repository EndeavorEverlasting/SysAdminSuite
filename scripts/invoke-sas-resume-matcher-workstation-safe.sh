#!/usr/bin/env bash
set -euo pipefail

action=Plan
allow_application_update=false
confirm_provider_charge=false
require_provider_health=false
config_path=
app_root_override=
state_root=
output_path=
fixture_root=
engine_args=()

usage() {
  cat <<'USAGE'
Usage: invoke-sas-resume-matcher-workstation-safe.sh [options]

Operator-safe front door for Resume Matcher workstation lifecycle actions.

Options:
  --action Plan|Apply|Start|Status|Stop|Validate|Accept
  --apply                         Required by mutating engine actions
  --allow-application-update      Apply only: authorize a clean-clone fast-forward
  --require-provider-health       Accept only: request one stored-provider health test
  --confirm-provider-charge       Required with --require-provider-health
  --config PATH                   Deployment profile JSON
  --app-root PATH                 Override the configured install path
  --state-root PATH               Runtime state root
  --output PATH                   Result JSON path
  --fixture-root PATH             Isolated fixture adapter
  --help

This wrapper never kills processes outside the repo-owned tmux session. After Stop,
it reports action-required when configured health endpoints still answer.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      action=${2:-}
      shift 2
      ;;
    --apply)
      engine_args+=(--apply)
      shift
      ;;
    --allow-application-update)
      allow_application_update=true
      shift
      ;;
    --require-provider-health)
      require_provider_health=true
      engine_args+=(--require-provider-health)
      shift
      ;;
    --confirm-provider-charge)
      confirm_provider_charge=true
      shift
      ;;
    --config)
      config_path=${2:-}
      engine_args+=(--config "$config_path")
      shift 2
      ;;
    --app-root)
      app_root_override=${2:-}
      engine_args+=(--app-root "$app_root_override")
      shift 2
      ;;
    --state-root)
      state_root=${2:-}
      engine_args+=(--state-root "$state_root")
      shift 2
      ;;
    --output)
      output_path=${2:-}
      shift 2
      ;;
    --fixture-root)
      fixture_root=${2:-}
      engine_args+=(--fixture-root "$fixture_root")
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$action" in
  Plan|Apply|Start|Status|Stop|Validate|Accept) ;;
  *) printf 'Unsupported action: %s\n' "$action" >&2; exit 2 ;;
esac

if $allow_application_update && [[ "$action" != Apply ]]; then
  printf '%s\n' '--allow-application-update is valid only with --action Apply.' >&2
  exit 2
fi
if $confirm_provider_charge && [[ "$action" != Accept ]]; then
  printf '%s\n' '--confirm-provider-charge is valid only with --action Accept.' >&2
  exit 2
fi
if $confirm_provider_charge && ! $require_provider_health; then
  printf '%s\n' '--confirm-provider-charge requires --require-provider-health.' >&2
  exit 2
fi
if $require_provider_health && ! $confirm_provider_charge; then
  printf '%s\n' '--require-provider-health requires --confirm-provider-charge because it performs one provider request that may consume credits.' >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
engine="$script_dir/invoke-sas-resume-matcher-workstation.sh"
[[ -x "$engine" || -f "$engine" ]] || { printf 'Resume Matcher lifecycle engine not found: %s\n' "$engine" >&2; exit 2; }
config_path=${config_path:-$repo_root/Config/resume-matcher-workstation.sample.json}
[[ -f "$config_path" ]] || { printf 'Deployment profile not found: %s\n' "$config_path" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'python3 is required to read the deployment profile.\n' >&2; exit 2; }

mapfile -d '' contract_values < <(python3 - "$config_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
app = data["application"]
services = data["services"]
if data.get("schema_version") != "sas-resume-matcher-workstation/v1":
    raise SystemExit("unsupported deployment profile schema")
relative = app["install_path_relative_to_home"]
if pathlib.PurePosixPath(relative).is_absolute() or ".." in pathlib.PurePosixPath(relative).parts:
    raise SystemExit("unsafe install path")
values = (
    app["repository_url"],
    app["repository_ref"],
    relative,
    str(services["backend_port"]),
    str(services["frontend_port"]),
    services["backend_health_path"],
)
for value in values:
    sys.stdout.write(str(value))
    sys.stdout.write("\0")
PY
)
(( ${#contract_values[@]} == 6 )) || { printf 'Deployment profile did not yield the expected safety fields.\n' >&2; exit 2; }
repo_url=${contract_values[0]}
repo_ref=${contract_values[1]}
install_relative=${contract_values[2]}
backend_port=${contract_values[3]}
frontend_port=${contract_values[4]}
backend_health_path=${contract_values[5]}
[[ "$repo_url" == "https://github.com/srbhr/Resume-Matcher.git" ]] || { printf 'Unapproved Resume Matcher repository URL.\n' >&2; exit 2; }

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
import os
import sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)

if [[ -n "$output_path" ]]; then
  final_output=$output_path
elif [[ -n "$state_root" ]]; then
  final_output=$state_root/last-result.json
else
  final_output=${XDG_STATE_HOME:-$home_root/.local/state}/sysadminsuite/resume-matcher/last-result.json
fi
mkdir -p "$(dirname "$final_output")"

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT
core_output=$tmp_root/core-result.json
core_stdout=$tmp_root/core-stdout.txt

publish_core_result() {
  [[ -f "$core_output" ]] || return 1
  cp "$core_output" "$final_output"
  cat "$final_output"
}

rewrite_result() {
  local operation=$1 outcome=$2 lifecycle=$3 reason=$4 message=$5 backend=$6 frontend=$7 live=$8
  python3 - "$core_output" "$final_output" "$operation" "$outcome" "$lifecycle" "$reason" "$message" "$backend" "$frontend" "$live" <<'PY'
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:3])
operation, outcome, lifecycle, reason, message = sys.argv[3:8]
backend = sys.argv[8] == "true"
frontend = sys.argv[9] == "true"
live = sys.argv[10] == "true"
data = json.loads(source.read_text(encoding="utf-8"))
data["operation"] = operation
data["outcome"] = outcome
data["lifecycle_state"] = lifecycle
data["reason_codes"] = [reason]
data["message"] = message
data["inventory"]["backend_healthy"] = backend
data["inventory"]["frontend_healthy"] = frontend
data["proof"]["backend_health_observed"] = backend
data["proof"]["frontend_health_observed"] = frontend
data["proof"]["live_runtime"] = live
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
print(destination.read_text(encoding="utf-8"), end="")
PY
}

run_engine_to_temp() {
  "$engine" --action "$action" "${engine_args[@]}" --output "$core_output" >"$core_stdout"
}

emit_blocked_apply() {
  local reason=$1 message=$2
  local plan_args=(--action Plan)
  [[ -n "$config_path" ]] && plan_args+=(--config "$config_path")
  [[ -n "$app_root_override" ]] && plan_args+=(--app-root "$app_root_override")
  [[ -n "$state_root" ]] && plan_args+=(--state-root "$state_root")
  [[ -n "$fixture_root" ]] && plan_args+=(--fixture-root "$fixture_root")
  "$engine" "${plan_args[@]}" --output "$core_output" >"$core_stdout" || true
  [[ -f "$core_output" ]] || { printf '%s\n' "$message" >&2; exit 4; }
  rewrite_result apply action-required planned "$reason" "$message" false false false
  exit 4
}

check_application_update_gate() {
  [[ -z "$fixture_root" ]] || return 0
  [[ -d "$app_root/.git" ]] || return 0
  git -C "$app_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local origin
  origin=$(git -C "$app_root" remote get-url origin 2>/dev/null || true)
  [[ "$origin" == "$repo_url" ]] || return 0
  [[ -z "$(git -C "$app_root" status --porcelain 2>/dev/null || true)" ]] || return 0
  $allow_application_update && return 0

  local local_head remote_head
  local_head=$(git -C "$app_root" rev-parse HEAD 2>/dev/null || true)
  remote_head=$(git ls-remote --heads "$repo_url" "$repo_ref" 2>/dev/null | awk 'NR==1 {print $1}')
  if [[ -z "$remote_head" ]]; then
    remote_head=$(git ls-remote "$repo_url" "$repo_ref" 2>/dev/null | awk 'NR==1 {print $1}')
  fi
  if [[ -z "$local_head" || -z "$remote_head" ]]; then
    emit_blocked_apply application-update-check-failed \
      'Apply was blocked because the clean-clone update check could not be proven. No application checkout was changed.'
  fi
  if [[ "$local_head" != "$remote_head" ]]; then
    emit_blocked_apply application-update-authorization-required \
      'A clean Resume Matcher clone has an available upstream revision. Rerun Apply with --allow-application-update to authorize the fast-forward.'
  fi
}

probe_backend=false
probe_frontend=false
probe_runtime() {
  probe_backend=false
  probe_frontend=false
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --max-time 3 "http://127.0.0.1:$backend_port$backend_health_path" >/dev/null 2>&1 && probe_backend=true || true
  curl -fsS --max-time 3 "http://127.0.0.1:$frontend_port" >/dev/null 2>&1 && probe_frontend=true || true
}

case "$action" in
  Apply)
    check_application_update_gate
    ;;
  Stop)
    if [[ -n "$fixture_root" ]]; then
      run_engine_to_temp
      publish_core_result
      exit 0
    fi
    if run_engine_to_temp; then
      for _ in 1 2 3; do
        probe_runtime
        ! $probe_backend && ! $probe_frontend && break
        sleep 0.2
      done
      if $probe_backend || $probe_frontend; then
        rewrite_result stop action-required running unmanaged-runtime-still-running \
          'The repo-owned tmux session was stopped, but one or both configured health endpoints still answer. SysAdminSuite did not kill arbitrary processes started outside its managed session.' \
          "$probe_backend" "$probe_frontend" true
        exit 4
      fi
      publish_core_result
      exit 0
    fi
    publish_core_result || true
    exit 1
    ;;
esac

normal_args=(--action "$action" "${engine_args[@]}")
[[ -n "$output_path" ]] && normal_args+=(--output "$output_path")
exec "$engine" "${normal_args[@]}"
