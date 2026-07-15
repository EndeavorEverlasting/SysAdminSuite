# Workstation Managed Configuration Capability

## Contract

Route authorized configuration to bounded, backup-first application entrypoints.

## Rules

- Require explicit Apply or Repair authorization.
- Preserve user-owned `.wezterm.lua`, `.tmux.conf`, and shell startup content outside managed blocks.
- Treat Lua as file content; never send it to a shell prompt.
- Reject malformed configurations that cannot accept a bounded include.
- Never authenticate agents or forward secrets during configuration.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
