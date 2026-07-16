# AgentSwitchboard GNHF Prompt Compilation Delegation Capability

## Contract

Delegate a validated regular request to the AgentSwitchboard-owned compiled-prompt contract without executing the resulting sprint.

## Rules

- Emit exactly one self-contained compiled prompt and one validation result.
- Require one Git mode, bounded iterations/tokens/time, owned and forbidden scope, artifacts, validation order, commit/push contracts, stop condition, proof ceiling, final response contract, and next command.
- Compilation requests never use `-Run`, imply provider success, or authorize environment Apply.
- Keep AgentSwitchboard launchers, validators, and routing code external to SysAdminSuite.

## Used by

- `.claude/skills/gnhf-prompt-adoption/SKILL.md`
