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
4. When AutoLogon or S4U failed before stage 1, or Windows PowerShell StrictMode reported a Count-property bootstrap failure and the controller may be stale, run `harness/workflows/repository-freshness-before-launch.yaml` first. After freshness classification, load `harness/workflows/prestage-bootstrap-safety.yaml` and `harness/skills/prestage-bootstrap-safety/SKILL.md` before product diagnosis or any field rerun.
5. When repository commands are available before a protected-network transition but may be unavailable afterward, load `harness/workflows/controller-network-mode-serialization.yaml` and `harness/skills/controller-network-mode-serialization/SKILL.md`. Finish repository proof and serialize checkout identity before changing network mode. Git may be unavailable after the protected-network transition.
6. Build a compact evidence ledger: identity, center of gravity, workstreams, harness/product inventory, validation, unresolved signals, risks, and important paths.
7. Rank bounded sprint candidates by unblock value, size, risk, proof ceiling, and collision risk.
8. Execute the highest-value safe slice; do not stop at a plan when a useful tracked change is available.
9. Checkpoint before broad validation or runtime proof.
10. Validate, review the diff, commit, push, and open/update the PR when the environment allows.
11. Report exact Git state, proof level, gaps, and one next command.

## Guardrails

- Floor before furniture: repair unsafe repository state before feature work.
- Shared contracts before duplicated reports, dashboards, or adapters.
- Do not merge, close, delete, force-push, or remove worktrees without current evidence.
- Do not turn an evidence harvest into a tracked census document unless downstream workflows require it.
- A pre-stage bootstrap signature does not authorize target contact, target mutation, S4U task diagnosis, or product-code edits; prove the executing repository tree first.
- Finish Git-dependent repository proof before a protected-network transition and honor `no_git_after_transition` when that environment can block Git.
- A remaining `PRODUCT_RUNTIME_GIT_DEPENDENCY` belongs to a separately authorized product-code lane.
