# Workstation Inventory Capability

## Contract

Observe terminal, execution-domain, WSL/native-Linux, tmux, keepalive, WezTerm GUI, shortcut, and agent readiness state without mutation.

## Rules

- Use the repository inventory entrypoint for the active platform.
- Treat Windows-native, Windows-WSL, and Linux-native as separate domains.
- Presence in one domain never proves readiness in another.
- Report stopped, stale, missing, malformed, and unsupported states explicitly.
- Inventory artifacts may contain live data and stay in ignored run roots.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
