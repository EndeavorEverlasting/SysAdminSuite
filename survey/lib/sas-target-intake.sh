#!/usr/bin/env bash
# Shared SysAdminSuite target-intake helper.
# Purpose: keep Bash survey paths aligned with targets/local, logs/targets,
# survey/input staging, and generated output roots.

sas_target_repo_root() {
  local start dir
  start="${BASH_SOURCE[0]}"
  dir="$(cd "$(dirname "$start")/../.." && pwd)"
  printf '%s\n' "$dir"
}

sas_target_abs_path() {
  local path="$1"
  python3 - "$path" <<'PY' 2>/dev/null || python - "$path" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
}

sas_target_is_under_any_root() {
  local path="$1"; shift
  local abs root_abs root
  abs="$(sas_target_abs_path "$path")"
  for root in "$@"; do
    root_abs="$(sas_target_abs_path "$root")"
    case "$abs" in
      "$root_abs"|"$root_abs"/*) return 0 ;;
    esac
  done
  return 1
}

sas_target_source_roots() {
  local repo="${1:-$(sas_target_repo_root)}"
  printf '%s\n' "$repo/targets/local" "$repo/logs/targets"
}

sas_target_staging_root() {
  local repo="${1:-$(sas_target_repo_root)}"
  printf '%s\n' "$repo/survey/input"
}

sas_target_output_roots() {
  local repo="${1:-$(sas_target_repo_root)}"
  printf '%s\n' "$repo/survey/output" "$repo/logs/nmap" "$repo/survey/artifacts"
}

sas_target_fixture_roots() {
  local repo="${1:-$(sas_target_repo_root)}"
  printf '%s\n' "$repo/survey/fixtures" "$repo/targets/sanitized"
}

sas_target_print_roots() {
  local repo="${1:-$(sas_target_repo_root)}"
  cat <<EOF
SysAdminSuite target intake roots:
- targets/local/ : preferred ignored live source intake
- logs/targets/  : preserved ignored local target/evidence store
- survey/input/  : normalized runtime staging only
Generated output roots:
- survey/output/
- logs/nmap/
- survey/artifacts/
EOF
}

sas_target_list_candidates() {
  local repo="${1:-$(sas_target_repo_root)}"
  local root
  for root in "$repo/targets/local" "$repo/logs/targets"; do
    [[ -d "$root" ]] || continue
    find "$root" -type f \( -name '*.txt' -o -name '*.csv' \) | sort
  done
}

sas_target_require_input_file() {
  local file="$1"
  local role="${2:-target input}"
  local allow_staging="${3:-0}"
  local repo="${4:-$(sas_target_repo_root)}"
  [[ -n "$file" ]] || { echo "[target-intake] ERROR: $role path is required" >&2; return 1; }
  [[ -f "$file" ]] || { echo "[target-intake] ERROR: $role not found: $file" >&2; return 1; }

  local roots=()
  roots+=("$repo/targets/local" "$repo/logs/targets")
  [[ "$allow_staging" == "1" ]] && roots+=("$repo/survey/input")
  if [[ "${SAS_TARGET_ALLOW_TEST_FIXTURES:-0}" == "1" ]]; then
    roots+=("$repo/survey/fixtures" "$repo/targets/sanitized")
  fi

  if ! sas_target_is_under_any_root "$file" "${roots[@]}"; then
    echo "[target-intake] ERROR: $role is outside approved target intake roots: $file" >&2
    echo "[target-intake] Use targets/local/ or logs/targets/ first; survey/input/ only after normalization." >&2
    echo "[target-intake] Set SAS_TARGET_ALLOW_TEST_FIXTURES=1 only for sanitized repo fixture tests." >&2
    return 1
  fi
}

sas_target_require_output_path() {
  local path="$1"
  local role="${2:-generated output}"
  local repo="${3:-$(sas_target_repo_root)}"
  [[ -n "$path" ]] || { echo "[target-intake] ERROR: $role path is required" >&2; return 1; }
  local roots=("$repo/survey/output" "$repo/logs/nmap" "$repo/survey/artifacts")
  if ! sas_target_is_under_any_root "$path" "${roots[@]}"; then
    echo "[target-intake] ERROR: $role is outside generated output roots: $path" >&2
    echo "[target-intake] Use survey/output/, logs/nmap/, or survey/artifacts/." >&2
    return 1
  fi
}
