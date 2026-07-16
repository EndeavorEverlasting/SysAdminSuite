# AgentSwitchboard GNHF Request Construction Capability

## Contract

Construct one SysAdminSuite sprint request that conforms to the pinned AgentSwitchboard regular-request version without copying the external schema.

## Rules

- Require an objective, repository and branch context, owned and forbidden scope, expected artifacts, safety constraints, and desired proof level.
- Carry validators as compiler context and require them in the compiled prompt validation order; do not add fields that the external regular-request schema forbids.
- Resolve runtime paths only in ignored local evidence; tracked fixtures use portable sentinels.
- Reject missing or overlapping scope, secret-like material, and dependence on unprovided chat history.
- Keep the request declarative. It grants neither target mutation nor local execution.

## Used by

- `.claude/skills/gnhf-prompt-adoption/SKILL.md`
