# Repository Sprint Skill

Use this skill for repository intake, sprint ranking, Git/PR lifecycle work, interrupted-agent recovery, worktree decisions, or evidence-led execution.

## Capability dependencies

- [Repository Evidence](../../capabilities/repository-evidence.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Operator next-command dependency

When this skill is about to emit, execute, or ask an operator to run a SysAdminSuite-owned next command, load [`harness/skills/operator-command-handoff/SKILL.md`](../../../harness/skills/operator-command-handoff/SKILL.md) first. A repository sprint does not get to bypass workstation prerequisites merely because repository implementation is complete.

The operator handoff must compose **path -> freshness -> network intent -> command -> restoration**. In particular, relocate to the canonical machine/profile path, refresh and safely converge repository truth, capture the starting network and resolve the command's required intent, execute the registered front door, and restore/return the network posture when required. Do not emit a bare product command and defer those prerequisites to a later corrective snippet.

## Workflow

1. Run compact Git and PR preflight using available tools.
2. Preserve dirty or concurrent work; isolate the lane when ownership differs.
3. Read `AGENTS.md`, `CODEBASE_MAP.md`, and only the product/harness files relevant to the task.
4. Build a compact evidence ledger: identity, center of gravity, workstreams, harness/product inventory, validation, unresolved signals, risks, and important paths.
5. Rank bounded sprint candidates by unblock value, size, risk, proof ceiling, and collision risk.
6. Execute the highest-value safe slice; do not stop at a plan when a useful tracked change is available.
7. Checkpoint before broad validation or runtime proof.
8. Validate, review the diff, commit, push, and open/update the PR when the environment allows.
9. Report exact Git state and proof level. If one next command is still required and it is SysAdminSuite-owned, route it through `harness/skills/operator-command-handoff/SKILL.md` before emitting it; otherwise report the exact external/user-only gate.

## Guardrails

- Floor before furniture: repair unsafe repository state before feature work.
- Shared contracts before duplicated reports, dashboards, or adapters.
- Do not merge, close, delete, force-push, or remove worktrees without current evidence.
- Do not turn an evidence harvest into a tracked census document unless downstream workflows require it.
- Do not use sprint completion as a reason to skip canonical relocation, pull-latest/currentness proof, network-intent selection, or required network restoration in an operator handoff.
