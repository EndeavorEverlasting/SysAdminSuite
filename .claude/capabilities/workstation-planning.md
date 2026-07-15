# Workstation Planning Capability

## Contract

Translate inventory and the v3 profile into a read-only, domain-correct workstation plan.

## Rules

- Plan is the default posture and creates no user-home or service state.
- Select non-Docker WSL for the Windows tmux backend and local tmux for native Linux.
- Keep Windows PowerShell 7 as fallback/admin, never as the tmux host.
- Name missing prerequisites and exact action-required reasons.
- Planning is not configuration, launch, behavior, or persistence proof.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
