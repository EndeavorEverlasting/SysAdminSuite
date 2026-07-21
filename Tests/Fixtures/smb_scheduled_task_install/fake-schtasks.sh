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
    mkdir -p "$run_root/results"
    status="${SIM_RESULT_STATUS:-Installed}"
    error=""
    [[ "$status" == "Installed" ]] || error="fixture installer failure"
    if [[ -f "$run_root/staged/package-bca/EPIC_BCA_Web-Shortcut_1.0.msi" ]]; then
      printf 'Name,Status,Error\nEpic BCA Web Shortcut 1.0,%s,%s\n' "$status" "$error" \
        > "$run_root/results/install_results_package-bca.csv"
    else
      package_set_root="$run_root/staged/package-set-cybernet-clinical-workstation"
      required_files=(
        'allscripts-eehr-shortcut-uai-2-2/Allscripts_EEHR-Shortcut-UAI_2.2.msi'
        'epic-downtime-guide-shortcut-1-0/Epic_Epic_Downtime_Guide-Shortcut_1.0.msi'
        'epic-downtime-guide-shortcut-1-0/Install.cmd'
        'nuance-dragon-medical-one-2025/cab1.cab'
        'nuance-dragon-medical-one-2025/DMO.Mst'
        'nuance-dragon-medical-one-2025/Dragon Medical One.lnk'
        'nuance-dragon-medical-one-2025/Install.cmd'
        'nuance-dragon-medical-one-2025/Nuance_Dragon_Edge_Extension.msi'
        'nuance-dragon-medical-one-2025/Standalone.msi'
        'hyland-fos-epic-integration-23-1-33-1000/EPICFOSCONFIG.XML'
        'hyland-fos-epic-integration-23-1-33-1000/FrontOfficeScanning.exe'
        'hyland-fos-epic-integration-23-1-33-1000/Hyland Integration for Epic.msi'
        'hyland-fos-epic-integration-23-1-33-1000/Hyland_Integration_EPIC.cab'
        'hyland-fos-epic-integration-23-1-33-1000/Hyland_Integration_EPIC.Mst'
        'hyland-fos-epic-integration-23-1-33-1000/Install.cmd'
        'hyland-fos-epic-integration-23-1-33-1000/VC_redist.x64.exe'
        'bca/EPIC_BCA_Web-Shortcut_1.0.msi'
        'autologon/NW_AutoLogon_Setup_x64.exe'
      )
      for required_file in "${required_files[@]}"; do
        [[ -f "$package_set_root/$required_file" ]]
      done
      {
        printf 'Name,Status,Error\n'
        printf 'Allscripts EEHR Shortcut UAI 2.2,%s,%s\n' "$status" "$error"
        printf 'Epic Downtime Guide Shortcut 1.0,%s,%s\n' "$status" "$error"
        printf 'Nuance Dragon Medical One 2025,%s,%s\n' "$status" "$error"
        printf 'Hyland FOS Epic Integration 23.1.33.1000,%s,%s\n' "$status" "$error"
        printf 'Epic BCA Web Shortcut 1.0,%s,%s\n' "$status" "$error"
        printf 'NW AutoLogon Setup x64,%s,%s\n' "$status" "$error"
      } > "$run_root/results/install_results_package-set-cybernet-clinical-workstation.csv"
    fi
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
