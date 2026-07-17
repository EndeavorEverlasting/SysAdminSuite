# AgentSwitchboard GNHF Result Ingestion Capability

## Contract

Ingest one validated AgentSwitchboard runtime result while preserving its status, blocker, artifact proof, commit proof, and proof ceiling.

## Rules

- Validate kind and schema version before reading result fields.
- Record blocked and failed results without converting process exit or start acknowledgement into success.
- Require observed artifacts and commit proof for a succeeded runtime result.
- Never raise the returned proof level or proof ceiling; separate contract proof from locally observed runtime behavior.

## Used by

- `.claude/skills/gnhf-prompt-adoption/SKILL.md`
