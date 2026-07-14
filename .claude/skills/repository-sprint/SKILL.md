# Repository Sprint Skill

Use this skill for repository intake, sprint ranking, Git/PR lifecycle work, interrupted-agent recovery, worktree decisions, or evidence-led execution.

## Capability dependencies

- [Repository Evidence](../../capabilities/repository-evidence.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Workflow

1. Run compact Git and PR preflight using available tools.
2. Preserve dirty or concurrent work; isolate the lane when ownership differs.
3. Read `AGENTS.md`, `CODEBASE_MAP.md`, and only the product/harness files relevant to the task.
4. Build a compact evidence ledger: identity, center of gravity, workstreams, harness/product inventory, validation, unresolved signals, risks, and important paths.
5. Rank bounded sprint candidates by unblock value, size, risk, proof ceiling, and collision risk.
6. Execute the highest-value safe slice; do not stop at a plan when a useful tracked change is available.
7. Checkpoint before broad validation or runtime proof.
8. Validate, review the diff, commit, push, and open/update the PR when the environment allows.
9. Report exact Git state, proof level, gaps, and one next command.

## Guardrails

- Floor before furniture: repair unsafe repository state before feature work.
- Shared contracts before duplicated reports, dashboards, or adapters.
- Do not merge, close, delete, force-push, or remove worktrees without current evidence.
- Do not turn an evidence harvest into a tracked census document unless downstream workflows require it.
