# Workstation Backend Lifecycle Capability

## Contract

Route backend start, health, repair, and stop to the platform-owned service.

## Rules

- Windows owns a hidden WSL keepalive with exact PID and command-line evidence.
- Native Linux uses the local host and must not be represented by WSL fixture execution.
- Bound startup waits and expose stale ownership state.
- Stop only exact owned resources; never kill by process name or unregister WSL.
- A running backend is not tmux attach or persistence proof.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
