#!/usr/bin/env bash
# Shared, line-oriented progress bars for SysAdminSuite Bash workflows.
# Progress is always written to stderr so CSV/JSON stdout remains machine-readable.

SAS_PROGRESS="${SAS_PROGRESS:-1}"
SAS_PROGRESS_WIDTH="${SAS_PROGRESS_WIDTH:-24}"
[[ "$SAS_PROGRESS_WIDTH" =~ ^[1-9][0-9]*$ ]] || SAS_PROGRESS_WIDTH=24
SAS_PROGRESS_ACTIVE=0
SAS_PROGRESS_CURRENT=0
SAS_PROGRESS_TOTAL=0
SAS_PROGRESS_LABEL="SysAdminSuite operation"

sas_progress_enabled() {
  case "${SAS_PROGRESS:-1}" in
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) return 0 ;;
  esac
}

sas_progress_disable() {
  SAS_PROGRESS=0
  SAS_PROGRESS_ACTIVE=0
}

sas_progress_render() {
  local current="$1" total="$2" state="$3" percent filled empty bar padding
  sas_progress_enabled || return 0
  [[ "$current" =~ ^[0-9]+$ && "$total" =~ ^[1-9][0-9]*$ ]] || return 0
  (( current > total )) && current="$total"
  percent=$(( current * 100 / total ))
  filled=$(( current * SAS_PROGRESS_WIDTH / total ))
  empty=$(( SAS_PROGRESS_WIDTH - filled ))
  printf -v bar '%*s' "$filled" ''
  bar="${bar// /#}"
  printf -v padding '%*s' "$empty" ''
  padding="${padding// /-}"
  printf '[%s%s] %3d%% (%d/%d) %-8s %s%s\n' \
    "$bar" "$padding" "$percent" "$current" "$total" "$state" "$SAS_PROGRESS_LABEL" \
    "${4:+ — $4}" >&2
}

sas_progress_start() {
  local total="$1" label="${2:-SysAdminSuite operation}"
  [[ "$total" =~ ^[1-9][0-9]*$ ]] || return 0
  SAS_PROGRESS_ACTIVE=1
  SAS_PROGRESS_CURRENT=0
  SAS_PROGRESS_TOTAL="$total"
  SAS_PROGRESS_LABEL="$label"
  sas_progress_render 0 "$total" running "started"
}

sas_progress_update() {
  local current="$1" detail="${2:-working}"
  [[ "$SAS_PROGRESS_ACTIVE" -eq 1 ]] || return 0
  SAS_PROGRESS_CURRENT="$current"
  sas_progress_render "$current" "$SAS_PROGRESS_TOTAL" running "$detail"
}

sas_progress_wait() {
  local detail="${1:-waiting for operator input}"
  [[ "$SAS_PROGRESS_ACTIVE" -eq 1 ]] || return 0
  sas_progress_render "$SAS_PROGRESS_CURRENT" "$SAS_PROGRESS_TOTAL" waiting "$detail"
}

sas_progress_complete() {
  local detail="${1:-finished successfully}"
  [[ "$SAS_PROGRESS_ACTIVE" -eq 1 ]] || return 0
  SAS_PROGRESS_CURRENT="$SAS_PROGRESS_TOTAL"
  sas_progress_render "$SAS_PROGRESS_TOTAL" "$SAS_PROGRESS_TOTAL" complete "$detail"
  SAS_PROGRESS_ACTIVE=0
}

sas_progress_fail() {
  local detail="${1:-stopped before completion}"
  [[ "$SAS_PROGRESS_ACTIVE" -eq 1 ]] || return 0
  sas_progress_render "$SAS_PROGRESS_CURRENT" "$SAS_PROGRESS_TOTAL" failed "$detail"
  SAS_PROGRESS_ACTIVE=0
}

sas_progress_skip() {
  local detail="${1:-not required}"
  [[ "$SAS_PROGRESS_ACTIVE" -eq 1 ]] || return 0
  sas_progress_render "$SAS_PROGRESS_CURRENT" "$SAS_PROGRESS_TOTAL" skipped "$detail"
  SAS_PROGRESS_ACTIVE=0
}
