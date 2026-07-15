#!/usr/bin/env bash
set -euo pipefail

action=Plan
user_root=${HOME}
state_root=${XDG_STATE_HOME:-$HOME/.local/state}/sysadminsuite/workstation
fixture=
output=
apply=false
install_missing=false
launch_gui=false
session=dev

usage() {
  printf 'Usage: %s [--action Plan|Apply|Start|Status|Stop|Repair|Rollback] [--apply] [--install-missing] [--fixture PATH] [--user-root PATH] [--state-root PATH] [--output PATH] [--launch-gui]\n' "$(basename "$0")"
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) action=$2; shift 2 ;;
    --apply) apply=true; shift ;;
    --install-missing) install_missing=true; shift ;;
    --fixture) fixture=$2; shift 2 ;;
    --user-root) user_root=$2; shift 2 ;;
    --state-root) state_root=$2; shift 2 ;;
    --output) output=$2; shift 2 ;;
    --launch-gui) launch_gui=true; shift ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$action" in Plan|Apply|Start|Status|Stop|Repair|Rollback) ;; *) printf 'Unsupported action: %s\n' "$action" >&2; exit 2 ;; esac

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
state_file=$state_root/linux-tmux-workspace-state.env
manifest_json=$state_root/linux-tmux-workspace-backup.json
manifest_tsv=$state_root/linux-tmux-workspace-backup.tsv
template=$repo_root/Config/wezterm-linux-tmux.lua.template
tmux_fragment=$repo_root/Config/tmux-sysadminsuite.conf
bash_fragment=$repo_root/Config/bashrc-sysadminsuite.sh
managed_start='-- BEGIN SYSADMINSUITE LINUX TMUX WORKSPACE'
managed_end='-- END SYSADMINSUITE LINUX TMUX WORKSPACE'

supported=false
os_id=unknown
package_manager=unknown
tmux_available=false
tmux_version=
wezterm_available=false
wezterm_path=
git_available=false
bash_available=false
session_exists=false
custom_dotfiles=false
malformed_config=false
apply_failure=false
nested_tmux=false
config_applied=false
gui_launched=false

load_values() {
  local path=$1 key value
  [[ -f "$path" ]] || return 0
  while IFS='=' read -r key value; do
    case "$key" in
      supported|os_id|package_manager|tmux_available|tmux_version|wezterm_available|wezterm_path|git_available|bash_available|session_exists|custom_dotfiles|malformed_config|apply_failure|nested_tmux|config_applied|gui_launched)
        printf -v "$key" '%s' "$value"
        ;;
    esac
  done < "$path"
}

if [[ -n "$fixture" ]]; then
  [[ -f "$fixture" ]] || { printf 'Fixture not found: %s\n' "$fixture" >&2; exit 2; }
  load_values "$fixture"
  load_values "$state_file"
else
  if [[ -r /etc/os-release ]]; then
    os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2); print $2}' /etc/os-release)
  fi
  case "$os_id" in
    ubuntu|debian) supported=true; package_manager=apt-get ;;
    fedora|rhel|centos) supported=true; package_manager=dnf ;;
    arch|manjaro) supported=true; package_manager=pacman ;;
    opensuse*|sles) supported=true; package_manager=zypper ;;
  esac
  command -v tmux >/dev/null 2>&1 && { tmux_available=true; tmux_version=$(tmux -V); }
  command -v wezterm >/dev/null 2>&1 && { wezterm_available=true; wezterm_path=$(command -v wezterm); }
  command -v git >/dev/null 2>&1 && git_available=true
  command -v bash >/dev/null 2>&1 && bash_available=true
  if $tmux_available && tmux has-session -t "$session" 2>/dev/null; then session_exists=true; fi
  [[ -n ${TMUX:-} ]] && nested_tmux=true
fi

json_escape() {
  local value=$1
  value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}
  printf '%s' "$value"
}
reason_json() {
  local csv=$1 first=true item
  if [[ -z "$csv" ]]; then printf '["none"]'; return; fi
  printf '['
  IFS=',' read -r -a items <<< "$csv"
  for item in "${items[@]}"; do $first || printf ','; first=false; printf '"%s"' "$(json_escape "$item")"; done
  printf ']'
}
emit_result() {
  local operation=$1 outcome=$2 lifecycle=$3 reasons=$4 message=$5 config_proof=${6:-false} launcher_proof=${7:-false}
  local role=backend-status
  case "$operation" in plan) role=plan ;; configure) role=config-backup-manifest ;; start) role=launcher-result ;; status|stop) role=tmux-status ;; rollback) role=rollback-result ;; esac
  local path_class=repo-ignored-run live_data=true
  [[ -n "$fixture" ]] && { path_class=temporary-fixture; live_data=false; }
  local run_id="developer-workstation-$(date -u +%Y%m%d-%H%M%S)-$(printf '%08x' "$((RANDOM * RANDOM))")"
  local payload
  payload=$(printf '{"schema_version":"sas-developer-workstation-lifecycle-result/v1","workflow_id":"developer-workstation","run_id":"%s","operation":"%s","outcome":"%s","lifecycle_state":"%s","reason_codes":%s,"message":"%s","artifacts":[{"role":"%s","path_class":"%s","tracked":false,"contains_live_data":%s}],"proof":{"install_completed":false,"config_applied":%s,"launcher_started":%s,"tmux_attached":false,"command_acknowledged":false,"behavior_observed":false,"persistence_observed":false,"live_runtime":false,"operator_accepted":false}}' \
    "$run_id" "$operation" "$outcome" "$lifecycle" "$(reason_json "$reasons")" "$(json_escape "$message")" "$role" "$path_class" "$live_data" "$config_proof" "$launcher_proof")
  if [[ -n "$output" ]]; then mkdir -p "$(dirname "$output")"; printf '%s\n' "$payload" > "$output"; fi
  printf '%s\n' "$payload"
}

blocking_reasons() {
  local reasons=()
  $supported || reasons+=(unsupported-platform)
  $tmux_available || reasons+=(tmux-missing)
  $wezterm_available || reasons+=(wezterm-cli-gui-confusion)
  $git_available || reasons+=(rollback-required)
  $bash_available || reasons+=(rollback-required)
  $nested_tmux && reasons+=(nested-tmux-attempt)
  local IFS=,
  printf '%s' "${reasons[*]}"
}

write_state() {
  mkdir -p "$state_root"
  {
    printf 'supported=%s\n' "$supported"
    printf 'os_id=%s\n' "$os_id"
    printf 'package_manager=%s\n' "$package_manager"
    printf 'tmux_available=%s\n' "$tmux_available"
    printf 'tmux_version=%s\n' "$tmux_version"
    printf 'wezterm_available=%s\n' "$wezterm_available"
    printf 'wezterm_path=%s\n' "$wezterm_path"
    printf 'git_available=%s\n' "$git_available"
    printf 'bash_available=%s\n' "$bash_available"
    printf 'session_exists=%s\n' "$session_exists"
    printf 'config_applied=%s\n' "$config_applied"
    printf 'gui_launched=%s\n' "$gui_launched"
  } > "$state_file"
}

install_prerequisites() {
  $install_missing || return 0
  [[ -n "$fixture" ]] && { tmux_available=true; wezterm_available=true; git_available=true; bash_available=true; return 0; }
  local missing=()
  $tmux_available || missing+=(tmux)
  $git_available || missing+=(git)
  $bash_available || missing+=(bash)
  if ((${#missing[@]})); then
    case "$package_manager" in
      apt-get) sudo apt-get update; sudo apt-get install -y "${missing[@]}" ;;
      dnf) sudo dnf install -y "${missing[@]}" ;;
      pacman) sudo pacman -S --needed --noconfirm "${missing[@]}" ;;
      zypper) sudo zypper --non-interactive install "${missing[@]}" ;;
      *) return 1 ;;
    esac
  fi
  if ! $wezterm_available; then
    printf 'WezTerm is not installed. Use the distro vendor package source; curl-pipe-shell installation is prohibited.\n' >&2
    return 1
  fi
}

backup_files() {
  mkdir -p "$state_root"
  local backup_root=$state_root/backup-$(date -u +%Y%m%d-%H%M%S)-$$
  mkdir -p "$backup_root"
  : > "$manifest_tsv"
  local file name existed backup first=true json_entries=
  for file in "$user_root/.wezterm.lua" "$user_root/.wezterm-sysadminsuite.lua" "$user_root/.tmux.conf" "$user_root/.tmux-sysadminsuite.conf" "$user_root/.bashrc" "$user_root/.bashrc-sysadminsuite.sh"; do
    name=$(basename "$file"); backup=$backup_root/$name; existed=false
    if [[ -f "$file" ]]; then existed=true; cp -p "$file" "$backup"; fi
    printf '%s\t%s\t%s\n' "$file" "$existed" "$backup" >> "$manifest_tsv"
    $first || json_entries+=','; first=false
    json_entries+=$(printf '{"path":"%s","existed":%s,"backup":"%s"}' "$(json_escape "$file")" "$existed" "$(json_escape "$backup")")
  done
  printf '{"schema_version":"sas-linux-tmux-workspace-backup/v1","entries":[%s]}\n' "$json_entries" > "$manifest_json"
}

replace_or_append_block() {
  local target=$1 marker_start=$2 marker_end=$3 fragment=$4 temp
  temp=$(mktemp)
  if [[ -f "$target" ]] && grep -Fq "$marker_start" "$target"; then
    awk -v start="$marker_start" -v end="$marker_end" -v fragment="$fragment" '
      $0 == start { print start; while ((getline line < fragment) > 0) print line; close(fragment); skip=1; next }
      $0 == end { print end; skip=0; next }
      !skip { print }
    ' "$target" > "$temp"
  else
    [[ -f "$target" ]] && cat "$target" > "$temp"
    printf '\n%s\n' "$marker_start" >> "$temp"
    cat "$fragment" >> "$temp"
    printf '%s\n' "$marker_end" >> "$temp"
  fi
  mv "$temp" "$target"
}

update_wezterm_root() {
  local target=$user_root/.wezterm.lua block temp
  block=$(mktemp)
  {
    printf '%s\n' "$managed_start"
    printf "local sas_workspace = dofile((os.getenv('HOME')) .. '/.wezterm-sysadminsuite.lua')\n"
    printf 'sas_workspace(config)\n'
    printf '%s\n' "$managed_end"
  } > "$block"
  if [[ ! -s "$target" ]]; then
    {
      printf "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\n\n"
      cat "$block"
      printf '\nreturn config\n'
    } > "$target"
    rm -f "$block"
    return
  fi
  if $malformed_config || { ! grep -Eq '^\s*return\s+config\s*$' "$target" && ! grep -Fq "$managed_start" "$target"; }; then
    rm -f "$block"
    return 1
  fi
  temp=$(mktemp)
  if grep -Fq "$managed_start" "$target"; then
    awk -v start="$managed_start" -v end="$managed_end" -v fragment="$block" '
      $0 == start { while ((getline line < fragment) > 0) print line; close(fragment); skip=1; next }
      $0 == end { skip=0; next }
      !skip { print }
    ' "$target" > "$temp"
  else
    awk -v fragment="$block" '/^[[:space:]]*return[[:space:]]+config[[:space:]]*$/ { while ((getline line < fragment) > 0) print line; close(fragment); print "" } { print }' "$target" > "$temp"
  fi
  mv "$temp" "$target"
  rm -f "$block"
}

apply_configuration() {
  mkdir -p "$user_root"
  backup_files
  $apply_failure && return 1
  cp "$template" "$user_root/.wezterm-sysadminsuite.lua"
  cp "$tmux_fragment" "$user_root/.tmux-sysadminsuite.conf"
  cp "$bash_fragment" "$user_root/.bashrc-sysadminsuite.sh"
  update_wezterm_root || return 2
  local tmux_block bash_block
  tmux_block=$(mktemp); printf 'source-file ~/.tmux-sysadminsuite.conf\n' > "$tmux_block"
  bash_block=$(mktemp); printf '[[ -r "$HOME/.bashrc-sysadminsuite.sh" ]] && source "$HOME/.bashrc-sysadminsuite.sh"\n' > "$bash_block"
  replace_or_append_block "$user_root/.tmux.conf" '# BEGIN SYSADMINSUITE LINUX TMUX WORKSPACE' '# END SYSADMINSUITE LINUX TMUX WORKSPACE' "$tmux_block"
  replace_or_append_block "$user_root/.bashrc" '# BEGIN SYSADMINSUITE LINUX TMUX WORKSPACE' '# END SYSADMINSUITE LINUX TMUX WORKSPACE' "$bash_block"
  rm -f "$tmux_block" "$bash_block"
  config_applied=true
  write_state
}

start_workspace() {
  if [[ -n "$fixture" ]]; then session_exists=true; $launch_gui && gui_launched=true; write_state; return; fi
  [[ -z ${TMUX:-} ]] || return 3
  tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session"
  session_exists=true
  if $launch_gui; then
    AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=0 nohup wezterm start --always-new-process >/dev/null 2>&1 &
    gui_launched=true
  fi
  write_state
}

stop_workspace() {
  if [[ -z "$fixture" ]] && tmux has-session -t "$session" 2>/dev/null; then tmux kill-session -t "$session"; fi
  session_exists=false; gui_launched=false; write_state
}

rollback_configuration() {
  [[ -f "$manifest_tsv" ]] || return 1
  local path existed backup
  while IFS=$'\t' read -r path existed backup; do
    if [[ "$existed" == true ]]; then cp -p "$backup" "$path"; else rm -f "$path"; fi
  done < "$manifest_tsv"
  config_applied=false
  write_state
}

reasons=$(blocking_reasons)
case "$action" in
  Plan)
    if [[ -n "$reasons" ]]; then emit_result plan action-required action-required "$reasons" "Plan requires supported Linux, tmux, WezTerm, Git, Bash, and a non-nested shell."; else emit_result plan success planned '' "Plan is ready for native $os_id using $package_manager; tmux=$tmux_version; session=$session_exists."; fi
    ;;
  Status)
    if [[ -n "$reasons" ]]; then emit_result status action-required action-required "$reasons" "Native Linux workspace prerequisites are incomplete."
    elif $session_exists; then emit_result status success session-running '' "Native tmux session dev is running."
    else emit_result status action-required action-required tmux-socket-missing "Native tmux session dev is not running."
    fi
    ;;
  Apply)
    $apply || { emit_result configure action-required action-required rollback-required 'Apply requires --apply.'; exit 0; }
    if [[ -n "$reasons" ]] && ! $install_missing; then emit_result configure action-required action-required "$reasons" 'Missing prerequisites require --install-missing with explicit --apply.'; exit 0; fi
    install_prerequisites || { emit_result configure failure failed rollback-required 'Approved prerequisite installation was incomplete.'; exit 0; }
    if apply_configuration; then emit_result configure success configured '' 'Bounded WezTerm, tmux, and Bash fragments were configured with backup evidence.' true
    else code=$?; [[ $code -eq 2 ]] && reason=invalid-lua || reason=rollback-required; emit_result configure failure failed "$reason" 'Configuration failed after backup; rollback evidence is available.'
    fi
    ;;
  Start)
    if [[ -n "$reasons" ]]; then emit_result start action-required action-required "$reasons" 'Workspace start is blocked.'
    elif start_workspace; then emit_result start success "$($launch_gui && printf gui-launched || printf session-running)" '' 'Native tmux dev session is running.' false "$launch_gui"
    else emit_result start failure failed nested-tmux-attempt 'Refusing to start a nested tmux session.'
    fi
    ;;
  Stop)
    if stop_workspace; then emit_result stop success stopped '' 'The exact native tmux dev session was stopped.'; else emit_result stop failure failed tmux-socket-missing 'The native tmux session could not be stopped.'; fi
    ;;
  Repair)
    $apply || { emit_result configure action-required action-required rollback-required 'Repair requires --apply.'; exit 0; }
    if [[ -n "$reasons" ]] && ! $install_missing; then emit_result configure action-required action-required "$reasons" 'Repair requires available prerequisites or --install-missing.'; exit 0; fi
    if install_prerequisites && apply_configuration && start_workspace; then emit_result configure success session-running '' 'Native configuration and tmux session were repaired.' true; else emit_result configure failure failed rollback-required 'Repair failed; rollback evidence is available.'; fi
    ;;
  Rollback)
    $apply || { emit_result rollback action-required action-required rollback-required 'Rollback requires --apply.'; exit 0; }
    if rollback_configuration; then emit_result rollback success stopped '' 'Managed dotfiles were restored from the backup manifest.'; else emit_result rollback failure failed rollback-required 'Backup manifest is unavailable.'; fi
    ;;
esac
