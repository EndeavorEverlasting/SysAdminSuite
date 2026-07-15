#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
PROFILE_PATH=""
OUTPUT_PATH=""
FIXTURE_MODE=false

usage() {
    printf "Usage: %s [--profile PATH] [--output PATH] [--fixture]\n" "$(basename "$0")"
    printf "  --profile PATH   Path to developer-workstation-profile sample JSON\n"
    printf "  --output PATH    Path to write machine-readable JSON inventory\n"
    printf "  --fixture        Emit synthetic Linux-native fixture\n"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE_PATH="$2"; shift 2 ;;
        --output)  OUTPUT_PATH="$2";  shift 2 ;;
        --fixture) FIXTURE_MODE=true; shift ;;
        *) usage ;;
    esac
done

find_repo_root() {
    local cursor="$SCRIPT_DIR"
    while [[ -n "$cursor" && "$cursor" != "/" ]]; do
        if [[ -f "$cursor/targets/README.md" && -d "$cursor/survey" ]]; then
            echo "$cursor"
            return 0
        fi
        cursor="$(dirname "$cursor")"
    done
    return 1
}

get_tool_check() {
    local cmd="$1"
    local version_cmd="${2:---version}"
    local status="FAIL" reason="$cmd not found" version="" path=""

    if command -v "$cmd" >/dev/null 2>&1; then
        path="$(command -v "$cmd")"
        local output
        if output=$("$cmd" $version_cmd 2>&1 | head -1); then
            version="$output"
            status="PASS"
            reason="$cmd found with version"
        else
            status="PASS"
            reason="$cmd found but version not obtainable"
        fi
    fi

    printf '{"status":"%s","reason":"%s","version":%s,"path":%s}' \
        "$status" "$reason" \
        "$( [[ -n "$version" ]] && printf '"%s"' "$version" || printf 'null' )" \
        "$( [[ -n "$path" ]] && printf '"%s"' "$path" || printf 'null' )"
}

get_agent_check() {
    local agent_id="$1"
    local cmd="$2"
    local version_cmd="${3:---version}"
    local status="FAIL" reason="$cmd not found" version=""

    if command -v "$cmd" >/dev/null 2>&1; then
        local output
        if output=$("$cmd" $version_cmd 2>&1 | head -1); then
            version="$output"
            status="PASS"
            reason="$cmd found with version"
        else
            status="PASS"
            reason="$cmd found but version not obtainable"
        fi
    fi

    printf '{"agent_id":"%s","status":"%s","reason":"%s","version":%s}' \
        "$agent_id" "$status" "$reason" \
        "$( [[ -n "$version" ]] && printf '"%s"' "$version" || printf 'null' )"
}

get_repo_relative_path() {
    local root="$1"
    local git_root
    if git_root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"; then
        echo "$git_root" | sed "s|$HOME|~|g"
    else
        echo "$root" | sed "s|$HOME|~|g"
    fi
}

if $FIXTURE_MODE; then
    INVENTORY=$(cat <<'FIXTURE_EOF'
{
  "schema_version": "sas-developer-workstation-inventory/v1",
  "generated_at": "2026-07-14T18:00:00Z",
  "detected_platform": "linux",
  "execution_environment": "native",
  "checks": {
    "wezterm": {
      "status": "PASS",
      "reason": "WezTerm found with version",
      "version": "20240203-115803-5022569c",
      "path": "/usr/bin/wezterm"
    },
    "shell": {
      "status": "PASS",
      "reason": "bash found with version",
      "version": "GNU bash, version 5.2.21(1)-release",
      "path": "/usr/bin/bash"
    },
    "multiplexer": {
      "status": "PASS",
      "reason": "tmux found with version",
      "version": "tmux 3.4",
      "path": "/usr/bin/tmux"
    },
    "repository": {
      "status": "PASS",
      "reason": "SysAdminSuite repository detected",
      "relative_path": "~/projects/SysAdminSuite"
    },
    "agent_commands": [
      {
        "agent_id": "opencode",
        "status": "PASS",
        "reason": "opencode found with version",
        "version": "0.1.0"
      },
      {
        "agent_id": "agy",
        "status": "FAIL",
        "reason": "agy not found",
        "version": null
      },
      {
        "agent_id": "goose",
        "status": "PASS",
        "reason": "goose found with version",
        "version": "1.0.0"
      }
    ],
    "agent_switchboard": {
      "status": "FAIL",
      "reason": "AgentSwitchboard not found on PATH",
      "version": null,
      "path": null
    },
    "wsl": {
      "status": "SKIP",
      "reason": "WSL not applicable on Linux native",
      "distributions": []
    }
  },
  "selected_profile": "linux-native",
  "eligible_profiles": ["linux-native"],
  "proof_ceiling": "Presence is not successful launch. Version output is not authentication readiness. Inventory does not prove installation or repair."
}
FIXTURE_EOF
)
    ENGLISH="Developer Workstation Inventory
================================

Platform: linux
Environment: native
Generated: 2026-07-14T18:00:00Z

[PASS] WezTerm: WezTerm found with version
[PASS] Shell: bash found with version
[PASS] Multiplexer: tmux found with version
[PASS] Repository: SysAdminSuite repository detected
[PASS] AgentSwitchboard: AgentSwitchboard not found on PATH

Agent Commands:
  [PASS] opencode: opencode found with version
  [FAIL] agy: agy not found
  [PASS] goose: goose found with version

Selected Profile: linux-native
Eligible Profiles: linux-native

Proof Ceiling: Presence is not successful launch. Version output is not authentication readiness. Inventory does not prove installation or repair."
else
    DETECTED_PLATFORM="unsupported"
    EXECUTION_ENV="unknown"

    if [[ "$(uname -s)" == "Linux" ]]; then
        DETECTED_PLATFORM="linux"
        EXECUTION_ENV="native"
    elif [[ "$(uname -s)" == "MINGW"* || "$(uname -s)" == "MSYS"* || "$(uname -s)" == "CYGWIN"* ]]; then
        DETECTED_PLATFORM="windows"
        EXECUTION_ENV="native"
    fi

    GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"

    WEZTERM_JSON="$(get_tool_check "wezterm" "--version")"
    SHELL_JSON="$(get_tool_check "bash" "--version")"
    MULTIPLEXER_JSON="$(get_tool_check "tmux" "-V")"

    REPO_ROOT=""
    if root="$(find_repo_root)"; then
        REPO_ROOT="$root"
        REPO_REL="$(get_repo_relative_path "$root")"
        REPO_JSON=$(printf '{"status":"PASS","reason":"SysAdminSuite repository detected","relative_path":"%s"}' "$REPO_REL")
    else
        REPO_JSON='{"status":"FAIL","reason":"SysAdminSuite repository not found","relative_path":null}'
    fi

    AGENT_JSONS=()
    for agent_spec in "opencode:opencode" "agy:agy" "goose:goose"; do
        IFS=':' read -r agent_id agent_cmd <<< "$agent_spec"
        AGENT_JSONS+=("$(get_agent_check "$agent_id" "$agent_cmd")")
    done
    AGENT_ARRAY="[$(IFS=,; echo "${AGENT_JSONS[*]}")]"

    SWITCHBOARD_JSON="$(get_tool_check "agent-switchboard" "--version")"

    WSL_JSON='{"status":"SKIP","reason":"WSL not applicable on Linux native","distributions":[]}'

    INVENTORY=$(cat <<EOF
{
  "schema_version": "sas-developer-workstation-inventory/v1",
  "generated_at": "$GENERATED_AT",
  "detected_platform": "$DETECTED_PLATFORM",
  "execution_environment": "$EXECUTION_ENV",
  "checks": {
    "wezterm": $WEZTERM_JSON,
    "shell": $SHELL_JSON,
    "multiplexer": $MULTIPLEXER_JSON,
    "repository": $REPO_JSON,
    "agent_commands": $AGENT_ARRAY,
    "agent_switchboard": $SWITCHBOARD_JSON,
    "wsl": $WSL_JSON
  },
  "selected_profile": null,
  "eligible_profiles": [],
  "proof_ceiling": "Presence is not successful launch. Version output is not authentication readiness. Inventory does not prove installation or repair."
}
EOF
)

    # Resolve eligible profiles if profile sample is available
    PROFILE_FILE="$PROFILE_PATH"
    if [[ -z "$PROFILE_FILE" && -n "$REPO_ROOT" ]]; then
        CANDIDATE="$REPO_ROOT/Config/developer-workstation-profile.sample.json"
        if [[ -f "$CANDIDATE" ]]; then
            PROFILE_FILE="$CANDIDATE"
        fi
    fi

    if [[ -n "$PROFILE_FILE" && -f "$PROFILE_FILE" ]] && command -v python3 >/dev/null 2>&1; then
        PROFILE_RESOLVE=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    p = json.load(f)
platform = sys.argv[2]
env = sys.argv[3]
eligible = []
for ep in p['terminal']['execution_profiles']:
    if ep['enabled'] and ep['platform'] == platform:
        if ep['environment'] == env:
            eligible.append(ep['id'])
print(json.dumps({'eligible': eligible, 'selected': eligible[0] if eligible else None}))
" "$PROFILE_FILE" "$DETECTED_PLATFORM" "$EXECUTION_ENV" 2>/dev/null || echo '{"eligible":[],"selected":null}')

        ELIGIBLE=$(echo "$PROFILE_RESOLVE" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['eligible']))" 2>/dev/null || echo '[]')
        SELECTED=$(echo "$PROFILE_RESOLVE" | python3 -c "import json,sys; v=json.load(sys.stdin)['selected']; print(json.dumps(v) if v else 'null')" 2>/dev/null || echo 'null')

        INVENTORY=$(echo "$INVENTORY" | python3 -c "
import json, sys
inv = json.load(sys.stdin)
inv['eligible_profiles'] = json.loads(sys.argv[1])
inv['selected_profile'] = json.loads(sys.argv[2])
print(json.dumps(inv, indent=2))
" "$ELIGIBLE" "$SELECTED" 2>/dev/null || echo "$INVENTORY")
    fi
fi

# Render English summary
if command -v python3 >/dev/null 2>&1; then
    ENGLISH=$(echo "$INVENTORY" | python3 -c "
import json, sys
inv = json.load(sys.stdin)
lines = ['Developer Workstation Inventory', '================================', '']
lines.append(f\"Platform: {inv['detected_platform']}\")
lines.append(f\"Environment: {inv['execution_environment']}\")
lines.append(f\"Generated: {inv['generated_at']}\")
lines.append('')

checks = [
    ('WezTerm', inv['checks']['wezterm']),
    ('Shell', inv['checks']['shell']),
    ('Multiplexer', inv['checks']['multiplexer']),
    ('Repository', inv['checks']['repository']),
    ('AgentSwitchboard', inv['checks']['agent_switchboard']),
]
for name, check in checks:
    icon = {'PASS': '[PASS]', 'SKIP': '[SKIP]', 'FAIL': '[FAIL]'}[check['status']]
    lines.append(f\"{icon} {name}: {check['reason']}\")

wsl = inv['checks'].get('wsl', {})
if wsl and wsl.get('status') not in ('SKIP', None):
    lines.append('')
    lines.append('WSL Distributions:')
    for dist in wsl.get('distributions', []):
        d_icon = {'PASS': '[PASS]', 'SKIP': '[SKIP]', 'FAIL': '[FAIL]'}[dist['status']]
        lines.append(f\"  {d_icon} {dist['name']}: {dist['reason']}\")

lines.append('')
lines.append('Agent Commands:')
for agent in inv['checks']['agent_commands']:
    a_icon = {'PASS': '[PASS]', 'SKIP': '[SKIP]', 'FAIL': '[FAIL]'}[agent['status']]
    lines.append(f\"  {a_icon} {agent['agent_id']}: {agent['reason']}\")

lines.append('')
lines.append(f\"Selected Profile: {inv['selected_profile']}\")
lines.append(f\"Eligible Profiles: {', '.join(inv['eligible_profiles'])}\")
lines.append('')
lines.append(f\"Proof Ceiling: {inv['proof_ceiling']}\")
print('\n'.join(lines))
" 2>/dev/null || true)
fi

# Output
if [[ -n "$OUTPUT_PATH" ]]; then
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    echo "$INVENTORY" > "$OUTPUT_PATH"
    SUMMARY_PATH="${OUTPUT_PATH%.json}-summary.txt"
    if [[ -n "${ENGLISH:-}" ]]; then
        echo "$ENGLISH" > "$SUMMARY_PATH"
    fi
fi

# Stdout
if [[ -n "${ENGLISH:-}" ]]; then
    echo "$ENGLISH"
fi
echo "---JSON---"
echo "$INVENTORY"
