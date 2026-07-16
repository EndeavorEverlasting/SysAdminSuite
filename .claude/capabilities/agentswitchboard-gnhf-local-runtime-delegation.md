# AgentSwitchboard GNHF Local Runtime Delegation Capability

## Contract

Delegate local execution only through the pinned AgentSwitchboard desktop entrypoint after explicit authorization and fail-closed preflight.

## Rules

- Default to Plan and require a separate explicit local-execution signal before `-Run`.
- Require the AgentSwitchboard checkout and pinned contract to be available, the target repository to be clean and attached, and exactly one of worktree or current-branch mode.
- Treat missing permission, unavailable authority, dirty target, detached HEAD, conflicting modes, and schema mismatch as typed non-success outcomes.
- Preserve returned failed-work references and carry any upstream preservation gap explicitly; do not promise that a failed worktree still exists.
- Keep runtime evidence in AgentSwitchboard-owned ignored storage.

## Used by

- `.claude/skills/gnhf-prompt-adoption/SKILL.md`
