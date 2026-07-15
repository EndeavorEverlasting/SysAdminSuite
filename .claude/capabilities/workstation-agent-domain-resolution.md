# Workstation Agent Domain Resolution Capability

## Contract

Resolve OpenCode, AGY, and Goose independently in the execution domain selected for the workspace.

## Rules

- Prefer healthy WSL/Linux-native commands.
- Use a Windows bridge only when the request and profile permit it.
- Alias or host presence alone is not readiness proof.
- Preserve executable, wrapper, function, alias, missing, native, bridge, and auth state.
- Authentication-required becomes action required; never automate provider login.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
