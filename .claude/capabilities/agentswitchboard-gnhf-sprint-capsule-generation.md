# AgentSwitchboard GNHF Sprint Capsule Generation Capability

## Contract

Compress validated delegation state through the existing SysAdminSuite sprint-capsule workflow and canonical artifact registry.

## Rules

- Reuse `agent_sprint_capsule.generate`, `tools/New-SasSprintCapsule.ps1`, and `SasRunContext`; do not create a second run context.
- Carry the ingested result status, exact validation, claims not made, proof ceiling, and next command into the capsule.
- Register only repository-relative capsule references; keep runtime paths and evidence outside Git.
- A capsule is a handoff artifact, not mutation authorization or higher runtime proof.

## Used by

- `.claude/skills/gnhf-prompt-adoption/SKILL.md`
