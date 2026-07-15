# AgentSwitchboard Invocation Capability

## Contract

Build and validate the versioned AgentSwitchboard request/result boundary without unsafe command strings.

## Rules

- Pin invocation and result schema versions supported by SysAdminSuite.
- Pass structured platform, domain, distro, requested agents, operation, and bridge policy.
- Use fixture posture for CI; bounded live probes must not call providers.
- Sanitize stderr and apply a bounded timeout.
- Treat malformed, missing, bridge-only, and authentication-required results as typed outcomes.

## Used by

- `.claude/skills/developer-workstation/SKILL.md`
