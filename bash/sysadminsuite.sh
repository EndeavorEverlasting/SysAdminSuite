#!/usr/bin/env bash
set -Eeuo pipefail

SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
SysAdminSuite Bash Runner

Usage:
  ./bash/sysadminsuite.sh <command> [args]

Commands:
  neuron:snapshot       Capture local Neuron-style maintenance snapshot
  neuron:software-ref   Compare observed Neuron software packages to reference
  help                  Show this help

Examples:
  ./bash/sysadminsuite.sh neuron:snapshot
  ./bash/sysadminsuite.sh neuron:software-ref --observed ./GetInfo/Config/NeuronObservedPackages.example.csv
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  neuron:snapshot)
    exec "$SUITE_ROOT/bash/neuron/neuron_maintenance_snapshot.sh" "$@"
    ;;
  neuron:software-ref)
    exec "$SUITE_ROOT/bash/neuron/neuron_software_reference.sh" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 64
    ;;
esac
