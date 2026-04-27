#!/usr/bin/env bash

# SysAdminSuite Maintenance Status Harness
# Placeholder modules now. Real checks later.
#
# Field posture:
#   - Intended to be launched by Run-MaintenanceStatus.cmd from a UNC/file-share path.
#   - Does not require the operator to cd into this directory.
#   - Placeholder modules are explicit so they can be replaced with real checks cleanly.
#   - Any keyboard input flips to an interruption warning screen.

set -u

HOSTNAME_VALUE="$(hostname 2>/dev/null || echo 'UNKNOWN-HOST')"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
BAR_WIDTH=38
TICK_DELAY_SECONDS="${TICK_DELAY_SECONDS:-3}"
INTERRUPTED=0

MODULES=(
  "Pre-requisite verification"
  "Cybernet workstation readiness"
  "SIS application validation"
  "SmartLynx configuration review"
  "Epic / TDR access posture"
  "Network connectivity validation"
  "Security policy alignment"
  "Autologon access posture review"
  "Peripheral communication checks"
  "COM port / serial pathway review"
  "Final QA pending technician confirmation"
)

PROGRESS_STEPS=(4 9 15 22 29 36 43 51 59 67 74 82 91 98)

clear_screen() {
  printf '\033c'
}

set_warning_color() {
  printf '\033[41;97m'
}

reset_color() {
  printf '\033[0m'
}

draw_bar() {
  local progress="$1"
  local filled=$((progress * BAR_WIDTH / 100))
  local empty=$((BAR_WIDTH - filled))

  printf '['

  if [ "$filled" -gt 0 ]; then
    printf '%*s' "$filled" '' | tr ' ' '#'
  fi

  if [ "$empty" -gt 0 ]; then
    printf '%*s' "$empty" '' | tr ' ' '-'
  fi

  printf '] %3d%%' "$progress"
}

show_interruption_warning() {
  clear_screen
  set_warning_color
  echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  echo "XX                                                        XX"
  echo "XX              MAINTENANCE DISPLAY INTERRUPTED           XX"
  echo "XX                                                        XX"
  echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  reset_color
  echo
  echo "Workstation : ${HOSTNAME_VALUE}"
  echo "Started     : ${START_TIME}"
  echo "Interrupted : $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "Status:"
  echo "  Keyboard input was detected while this workstation was marked"
  echo "  as under IT maintenance / review."
  echo
  echo "Required Action:"
  echo "  Contact the assigned IT technician or project lead."
  echo "  Maintenance validation may need to be restarted or rechecked."
  echo
  echo "Do not power off, unplug, restart, or use this workstation unless"
  echo "directed by IT."
  echo
  echo "============================================================"
  echo "This warning remains visible so the interruption is not missed."
  echo "============================================================"

  while true; do
    sleep 60
  done
}

check_for_keypress() {
  # read -t works in Git Bash / most Bash shells. Any key, including Enter
  # or the first byte of an arrow-key escape sequence, triggers the warning.
  local key=""
  if read -rsn1 -t 0.05 key; then
    INTERRUPTED=1
    show_interruption_warning
  fi
}

print_screen() {
  local module_name="$1"
  local progress="$2"

  clear_screen

  echo "============================================================"
  echo "              IT MAINTENANCE STATUS HARNESS"
  echo "============================================================"
  echo
  echo "Workstation : ${HOSTNAME_VALUE}"
  echo "Started     : ${START_TIME}"
  echo "Current Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "Status      : Device is under IT maintenance / review."
  echo "Instruction : Do not power off, unplug, restart, use, or type."
  echo
  echo "Current Module:"
  echo "  - ${module_name}"
  echo
  printf "Progress    : "
  draw_bar "$progress"
  echo
  echo
  echo "Technician Note:"
  echo "  Placeholder modules are active until real validation checks"
  echo "  are wired into this harness."
  echo
  echo "Interruption Guard:"
  echo "  Keyboard input will mark this maintenance display as interrupted."
  echo
  echo "Future Wiring:"
  echo "  Replace each module with real checks, logs, and exit codes."
  echo
  echo "============================================================"
  echo "If urgent, contact the assigned IT technician or project lead."
  echo "============================================================"
}

sleep_with_keywatch() {
  local elapsed=0
  local total="$1"

  while [ "$elapsed" -lt "$total" ]; do
    check_for_keypress
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

while true; do
  for module_name in "${MODULES[@]}"; do
    for progress in "${PROGRESS_STEPS[@]}"; do
      print_screen "$module_name" "$progress"
      sleep_with_keywatch "$TICK_DELAY_SECONDS"
    done
  done
done
