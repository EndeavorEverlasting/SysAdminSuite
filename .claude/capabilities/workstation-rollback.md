# Workstation Rollback Capability

## Contract

Restore only files and launch surfaces owned by the recorded workstation backup manifest.

## Rules

- Require explicit Rollback authorization.
- Restore pre-existing files and remove only managed files that were absent before Apply.
- Preserve tmux sessions unless the selected platform rollback contract explicitly stops them.
- A missing or malformed manifest fails closed with rollback required.
- Register rollback evidence without committing local home paths.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
