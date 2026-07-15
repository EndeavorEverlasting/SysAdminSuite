# Workstation Session Lifecycle Capability

## Contract

Route Start, Status, and Stop for the deterministic tmux `dev` workspace.

## Rules

- Create the session detached when absent and reuse it when present.
- If `TMUX` is already set, use or inspect the current session; do not nest tmux.
- GUI close or detach must not imply session stop.
- Stop is explicitly destructive to `dev` and must be labeled as such.
- Status distinguishes backend, socket, session, GUI-launch, and attach state.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
