#!/usr/bin/env bash
# SysAdminSuite QR Field Command Capsule Launcher
# QR -> profile -> approved survey lane -> evidence package

set -Eeuo pipefail

PROFILE_ID=""
PROFILE_DIR="profiles"
DRY_RUN=0
ARGS=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/sas_qr_run.sh --profile <id> [--dry-run] -- <survey arguments>

Example:
  bash scripts/sas_qr_run.sh --profile neuron-hostname-survey -- \
    --manifest GetInfo/Config/NeuronTargets.unresolved.csv \
    --nmap-xml survey/artifacts/site_neuron_discovery.xml \
    --output survey/output/neuron_resolved_targets.csv \
    --review-output survey/output/neuron_probe_review.csv
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }
profile_value() {
  local file="$1" key="$2"
  awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    index($0, k "=") == 1 {
      print substr($0, length(k) + 2)
      exit
    }' "$file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE_ID="${2:-}"; shift 2 ;;
    --profile-dir) PROFILE_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --) shift; ARGS+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown launcher argument: $1" ;;
  esac
done

[[ -n "$PROFILE_ID" ]] || fail "--profile is required"
[[ "$PROFILE_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "Unsafe profile id"

PROFILE="$PROFILE_DIR/$PROFILE_ID.profile"
[[ -f "$PROFILE" ]] || fail "Profile not found: $PROFILE"

DECLARED_ID="$(profile_value "$PROFILE" profile_id)"
RUNNER="$(profile_value "$PROFILE" runner)"
SCRIPT="$(profile_value "$PROFILE" script)"
MUTATION_ALLOWED="$(profile_value "$PROFILE" mutation_allowed)"

[[ "$DECLARED_ID" == "$PROFILE_ID" ]] || fail "Profile id mismatch"
[[ "${MUTATION_ALLOWED,,}" == "false" ]] || fail "Field capsules must be non-mutating by default"
[[ -n "$RUNNER" && -n "$SCRIPT" ]] || fail "Profile missing runner or script"
[[ -f "$SCRIPT" ]] || fail "Survey lane not found: $SCRIPT"
command -v "$RUNNER" >/dev/null 2>&1 || fail "Runner not found: $RUNNER"

printf 'QR field command capsule\n'
printf 'Profile: %s\n' "$PROFILE_ID"
printf 'Lane: %s %s\n' "$RUNNER" "$SCRIPT"
printf 'Arguments:'
printf ' %q' "${ARGS[@]}"
printf '\n'

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: approved survey lane was not executed"
  exit 0
fi

exec "$RUNNER" "$SCRIPT" "${ARGS[@]}"
