#!/usr/bin/env bash
# Repo-wide Naabu doctrine conformance checks. Read-only; no network access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'test_repo_naabu_doctrine_conformance: FAIL: %s\n' "$*" >&2
  exit 1
}

run_contracts() {
  bash tests/bash/smoke-naabu-profiles.sh
  bash Tests/bash/test_naabu_profile_sync.sh
  bash Tests/bash/test_cybernet_detect_contracts.sh
  bash Tests/bash/test_naabu_pipeline_contracts.sh
  bash Tests/bash/test_naabu_package_contracts.sh
  bash Tests/bash/test_packet_probe_contracts.sh
}

check_raw_naabu_commands() {
  local bad=0
  local path line_no line text

  while IFS=: read -r path line_no text; do
    [[ -n "${path:-}" ]] || continue

    if [[ "$text" != *"-silent"* ]]; then
      printf 'missing -silent: %s:%s:%s\n' "$path" "$line_no" "$text" >&2
      bad=1
    fi

    if [[ "$text" != *"-ec"* && "$text" != *'$ecFlag'* ]]; then
      printf 'missing -ec or ecFlag gate: %s:%s:%s\n' "$path" "$line_no" "$text" >&2
      bad=1
    fi
  done < <(
    git grep -n -I -E 'naabu[[:space:]]+-(list|host)' -- \
      '*.md' '*.sh' '*.ps1' '*.psm1' '*.json' '*.go' '*.js' ':!Config/cybernet-naabu-profiles.json' || true
  )

  [[ "$bad" -eq 0 ]] || fail "raw naabu command strings must preserve -silent and -ec"
}

check_doctrine_references() {
  local skill='.claude/skills/survey-low-noise/SKILL.md'
  local doctrine='docs/LOW_NOISE_SURVEY_DOCTRINE.md'

  grep -q '.claude/skills/survey-low-noise/SKILL.md' AGENTS.md || fail "AGENTS.md must route survey work to the low-noise skill"
  [[ -f "$skill" ]] || fail "missing survey low-noise skill"
  grep -q 'survey/naabu_profiles.json' "$skill" || fail "survey skill must reference survey/naabu_profiles.json"
  grep -q 'low-noise survey discipline' "$skill" || fail "survey skill must preserve low-noise language"
  grep -q 'feature/naabu-docs-consolidation' "$skill" || fail "survey skill must mark H1 as superseded"
  grep -q 'AD registered population = source' "$doctrine" || fail "canonical doctrine must preserve the population authority"
  [[ -f .cursor/rules/naabu-doctrine.mdc ]] || fail "missing .cursor/rules/naabu-doctrine.mdc"
}

run_contracts
check_raw_naabu_commands
check_doctrine_references

echo "test_repo_naabu_doctrine_conformance: PASS"
