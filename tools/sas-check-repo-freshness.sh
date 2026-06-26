#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
write_json=""
quiet=0

usage() {
  cat <<'EOF'
Usage: tools/sas-check-repo-freshness.sh [--write-json PATH] [--quiet]

Read-only SysAdminSuite source-clone freshness check. It compares local main
with origin/main, reports whether the local copy is behind, and never applies
updates. Use the approved updater for mutation: git pull --ff-only origin main
after operator approval and a clean main branch.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-json)
      [[ $# -ge 2 ]] || { echo "missing value for --write-json" >&2; exit 1; }
      write_json=$2
      shift 2
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/ }
  value=${value//$'\r'/ }
  printf '%s' "$value"
}

emit_state() {
  local mode=$1 branch=$2 ahead=$3 behind=$4 safe=$5 can_auto=$6 update_available=$7 manual_reason=$8 reason=$9 exit_code=${10}
  local generated
  generated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local json
  json=$(printf '{"mode":"%s","installRoot":"%s","branch":%s,"ahead":%s,"behind":%s,"safe":%s,"canAutoUpdate":%s,"updateAvailable":%s,"manualReviewReason":%s,"reason":"%s","generatedAt":"%s"}' \
    "$(json_escape "$mode")" \
    "$(json_escape "$repo_root")" \
    "$(if [[ -n "$branch" ]]; then printf '"%s"' "$(json_escape "$branch")"; else printf 'null'; fi)" \
    "$ahead" \
    "$behind" \
    "$safe" \
    "$can_auto" \
    "$update_available" \
    "$(if [[ -n "$manual_reason" ]]; then printf '"%s"' "$(json_escape "$manual_reason")"; else printf 'null'; fi)" \
    "$(json_escape "$reason")" \
    "$generated")

  if [[ -n "$write_json" ]]; then
    mkdir -p "$(dirname "$write_json")"
    printf '%s\n' "$json" > "$write_json"
  fi

  if [[ "$quiet" -eq 0 ]]; then
    printf '%s\n' "$json"
  fi

  exit "$exit_code"
}

if [[ ! -d "$repo_root/.git" ]]; then
  emit_state "none" "" 0 0 true true false "" "No .git folder found. ZIP or field-package copies use manifest-based update checks." 0
fi

if ! command -v git >/dev/null 2>&1; then
  emit_state "git" "" 0 0 false false false "git is not available on PATH." "git is not available on PATH." 1
fi

if ! git -C "$repo_root" fetch --quiet origin >/dev/null 2>&1; then
  emit_state "git" "" 0 0 false false false "git fetch origin failed." "git fetch origin failed." 1
fi

branch=$(git -C "$repo_root" branch --show-current 2>/dev/null || true)
counts=$(git -C "$repo_root" rev-list --left-right --count main...origin/main 2>/dev/null || true)
if [[ -z "$counts" ]]; then
  emit_state "git" "$branch" 0 0 false false false "Could not compare local main with origin/main." "Could not compare local main with origin/main." 1
fi

read -r ahead behind <<<"$counts"
ahead=${ahead:-0}
behind=${behind:-0}

manual_reasons=()
if [[ "$branch" != "main" ]]; then
  manual_reasons+=("Current branch is '$branch'. Switch to main before updating.")
fi

if [[ -n "$(git -C "$repo_root" status --short)" ]]; then
  manual_reasons+=("Working tree has local changes. Commit, stash, or discard them before updating.")
fi

if [[ -n "$(git -C "$repo_root" log --branches --not --remotes --oneline)" ]]; then
  manual_reasons+=("Local-only commits exist. Push or preserve them before updating.")
fi

if [[ "$ahead" -gt 0 ]]; then
  manual_reasons+=("Local main is ahead of origin/main. Manual review required.")
fi

manual_reason=""
if [[ "${#manual_reasons[@]}" -gt 0 ]]; then
  manual_reason="${manual_reasons[*]}"
fi

safe=true
can_auto=true
if [[ -n "$manual_reason" ]]; then
  safe=false
  can_auto=false
fi

update_available=false
if [[ "$behind" -gt 0 ]]; then
  update_available=true
fi

reason="Already up to date."
if [[ "$behind" -gt 0 && "$can_auto" == "true" ]]; then
  reason="origin/main is $behind commit(s) ahead of your local main. Update before surveying so you are using the latest SysAdminSuite code."
elif [[ "$behind" -gt 0 ]]; then
  reason="origin/main is $behind commit(s) ahead of your local main, but automatic update needs manual review: $manual_reason"
elif [[ -n "$manual_reason" ]]; then
  reason="$manual_reason"
fi

if [[ "$safe" != "true" ]]; then
  emit_state "git" "$branch" "$ahead" "$behind" false false "$update_available" "$manual_reason" "$reason" 20
fi

if [[ "$update_available" == "true" ]]; then
  emit_state "git" "$branch" "$ahead" "$behind" true true true "" "$reason" 10
fi

emit_state "git" "$branch" "$ahead" "$behind" true true false "" "$reason" 0
