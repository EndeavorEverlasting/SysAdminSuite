# Project AI Layer: Harness and Tooling Plan

## Purpose

Capture the AI-layer harness ideas from the agent harness discussion and translate them into SysAdminSuite planning doctrine.

This document is planning material. It does not implement hooks, MCP servers, LSP integration, or agent skills by itself.

## Source

User-provided planning notes from:

- `Anthropic Just Dropped a Masterclass on Building Agent Harnesses`
- Provided link: `https://www.youtube.com/watch?v=coleam00/helpline`

## 1. Global Rules

### Target file pattern

Use layered agent rule files, such as root and path-scoped instruction files, so the agent receives only the rules needed for the active work area.

### Strategy

Keep global files lean. Place specific rules closer to the code or workflow they govern.

Examples:

```text
AGENTS.md
CLAUDE.md
docs/CLAUDE.md
survey/CLAUDE.md
dashboard/CLAUDE.md
tooling/mcp/CLAUDE.md
```

### Objective

Prevent context bloat while keeping domain-specific conventions active where they matter.

For SysAdminSuite, this means:

- Survey rules stay close to `survey/`.
- Dashboard rules stay close to `dashboard/`.
- Harness and MCP rules stay close to `harness/`, `mcp/`, and `tooling/mcp/`.
- Live-data guardrails remain visible wherever agents might touch fixtures, samples, or generated evidence.

## 2. Self-Improving Hooks

### Stop hooks

At the end of an agent session, the harness should be able to summarize what changed and propose documentation updates.

Stop-hook output should answer:

```text
What rule was missing?
What mistake or repeat explanation occurred?
Which instruction file should be updated?
What exact wording should be proposed?
Should the update be automatic, advisory, or operator-approved?
```

Stop hooks must not silently rewrite project rules. They should propose changes first unless a sprint explicitly authorizes automated updates.

### Start hooks

At session start, the harness should load relevant context based on the active path or task type.

Examples:

```text
survey/*      -> load survey workflow, low-noise, live-data, target policy context
dashboard/*   -> load dashboard entrypoint, browser safety, no-command-execution context
scripts/*.ps1 -> load PowerShell preservation and Windows workflow context
tooling/mcp/* -> load read-only MCP/code-intelligence guardrails
```

### Objective

Make the harness remember lessons without bloating every session.

## 3. Path-Scoped Skills

### Strategy

Define specialized workflows that are visible only when working in relevant directories.

Examples:

```text
survey/ skill: Add survey planner
survey/ skill: Add synthetic fixture contract
dashboard/ skill: Add dashboard parser surface
scripts/ skill: Add PowerShell-safe harness script
tooling/mcp/ skill: Add read-only code intelligence tool
```

### Skill shape

Each skill should include:

```text
When to use it
Files to inspect first
Forbidden scope
Expected outputs
Tests to run
Safety checks
Final report format
```

### Objective

Use progressive disclosure. Give the agent expertise only when the context calls for it.

## 4. LSP and MCP Integration

### Strategy

Implement local MCP servers that expose code-intelligence capabilities. Prefer symbol-level navigation over inefficient string-only search when the repo grows large.

### Capability target

The code-intelligence layer should support:

```text
Find definition
Find references
Outline file symbols
Find command surfaces
Find workflow specs
Find artifact schemas
Find policy source
Find dashboard parser ownership
```

### SysAdminSuite first slice

The first implementation should remain read-only:

```text
where_is_command
find_survey_workflows
find_artifact_schema
find_policy_source
find_contract_for_surface
outline_powershell_script
outline_dashboard_parser
```

### Guardrails

The MCP/code-intelligence layer must:

- Read tracked docs, code, and contracts by default.
- Exclude ignored live evidence roots by default.
- Avoid secrets exposure.
- Avoid probe execution.
- Avoid target mutation.
- Return concise structured results rather than large dumps.

### Benefit

Symbol-level and structured repo navigation should reduce wasted tokens, reduce duplicate rediscovery, and make parallel agent work less sloppy.

## 5. Subagents for Exploration

### Strategy

Delegate discovery, repo reconnaissance, and high-token exploration to subagents or isolated research passes.

### Primary session contract

The primary editing session should stay focused on:

```text
bounded implementation
small patch sets
tests
final operator report
```

The exploration subagent should return:

```text
Relevant files
Existing contracts
Collision risks
Missing dependencies
Suggested patch boundary
Tests to run
```

### Objective

Keep the main session sharp. Let exploration happen, but make it return a concise map instead of burying the operator in rubble.

## 6. Action Items

- [ ] Deploy a local MCP/code-intelligence server for symbol and contract search.
- [ ] Configure start-hook and stop-hook behavior in the agent settings layer.
- [ ] Establish a layered `CLAUDE.md` or equivalent agent-rule hierarchy.
- [ ] Define path-scoped skills for `survey/`, `dashboard/`, `scripts/`, and `tooling/mcp/`.
- [ ] Add a read-only exploration subagent pattern for repo reconnaissance.
- [ ] Keep generated evidence, live targets, and operational artifacts outside tracked docs.

## 7. Fit With Current Harness Plan

This plan aligns with the existing SysAdminSuite harness direction:

- English reports make agent output readable.
- Run contexts tie artifacts together.
- Workflow specs make sequence explicit.
- MCP/code-intelligence reduces rediscovery.
- Hooks help keep local rules current.
- Path-scoped skills prevent every session from carrying every rule.

The immediate useful next step is still the same: land English reports, run context, workflow specs, and a synthetic validator before building heavier agent automation.
