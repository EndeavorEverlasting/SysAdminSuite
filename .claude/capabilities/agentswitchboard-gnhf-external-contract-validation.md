# AgentSwitchboard GNHF External Contract Validation Capability

## Contract

Validate request, compiled prompt, launch request, and runtime result kinds against the exact external version pinned by SysAdminSuite.

## Rules

- Read `harness/api/agentswitchboard-gnhf-external-contract.json` before accepting a packet.
- Require the pinned schema version, schema ID, source commit, and Git blob identity for the selected kind.
- Delegate full schema validation to the pinned AgentSwitchboard contract surface; local tests validate the compatibility pin and fail-closed invariants only.
- Reject unavailable authority, version mismatch, unknown kind, extra Git execution modes, or malformed proof fields.

## Used by

- `.claude/skills/gnhf-prompt-adoption/SKILL.md`
