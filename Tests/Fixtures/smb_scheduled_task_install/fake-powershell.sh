#!/usr/bin/env bash
set -euo pipefail

map_target_unc() {
  local value="${1//\\//}"
  value="${value#//}"
  value="${value#*/}"
  local share="${value%%/*}"
  value="${value#*/}"
  [[ "$share" == 'C$' ]]
  printf '%s/%s' "$SIM_REMOTE_ROOT" "$value"
}

if [[ -n "${SAS_ADMIN_SHARE:-}" ]]; then
  exit 0
fi

if [[ -n "${SAS_REMOTE_PATH:-}" ]]; then
  remote_file="$(map_target_unc "$SAS_REMOTE_PATH")"
  [[ -f "$remote_file" ]]
  exit
fi

if [[ -n "${SAS_REMOTE_RUN_ROOT:-}" ]]; then
  run_root="$(map_target_unc "$SAS_REMOTE_RUN_ROOT")"
  case "$run_root" in
    "$SIM_REMOTE_ROOT"/ProgramData/SysAdminSuite/AppInstall/app-install-*) ;;
    *) exit 44 ;;
  esac
  rm -rf -- "$run_root"
  exit 0
fi

if [[ -n "${SAS_COPY_SOURCE:-}" && -n "${SAS_COPY_DESTINATION:-}" ]]; then
  if [[ "$SAS_COPY_DESTINATION" == \\\\* ]]; then
    destination="$(map_target_unc "$SAS_COPY_DESTINATION")"
    mkdir -p "$(dirname "$destination")"
    if [[ -f "$SAS_COPY_SOURCE" ]]; then
      cp "$SAS_COPY_SOURCE" "$destination"
    else
      printf 'fixture-package\n' > "$destination"
    fi
  else
    source_path="$(map_target_unc "$SAS_COPY_SOURCE")"
    mkdir -p "$(dirname "$SAS_COPY_DESTINATION")"
    cp "$source_path" "$SAS_COPY_DESTINATION"
  fi
  exit 0
fi

exit 41
