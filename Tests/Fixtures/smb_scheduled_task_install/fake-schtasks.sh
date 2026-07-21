#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$SIM_TASK_LOG"
case "${1:-}" in
  /Create)
    : > "$SIM_TASK_STATE"
    ;;
  /Run)
    [[ -f "$SIM_TASK_STATE" ]]
    shopt -s nullglob
    roots=("$SIM_REMOTE_ROOT"/ProgramData/SysAdminSuite/AppInstall/app-install-*)
    [[ "${#roots[@]}" -eq 1 ]]
    run_root="${roots[0]}"
    [[ -f "$run_root/sas-install-worker.ps1" ]]
    [[ -f "$run_root/Start-Installer.ps1" ]]
    [[ -f "$run_root/staged/package-bca/EPIC_BCA_Web-Shortcut_1.0.msi" ]]
    mkdir -p "$run_root/results"
    status="${SIM_RESULT_STATUS:-Installed}"
    error=""
    [[ "$status" == "Installed" ]] || error="fixture installer failure"
    printf 'Name,Status,Error\nEpic BCA Web Shortcut 1.0,%s,%s\n' "$status" "$error" \
      > "$run_root/results/install_results_package-bca.csv"
    ;;
  /Query)
    if [[ ! -f "$SIM_TASK_STATE" ]]; then
      printf 'ERROR: The system cannot find the file specified.\n' >&2
      exit 1
    fi
    ;;
  /Delete)
    [[ -f "$SIM_TASK_STATE" ]]
    rm -f -- "$SIM_TASK_STATE"
    ;;
  *) exit 42 ;;
esac
