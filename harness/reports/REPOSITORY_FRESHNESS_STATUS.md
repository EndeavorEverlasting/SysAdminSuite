# Repository Freshness Harness Status

## Working

- The repository has a canonical fresh-agent intake workflow, codebase map, command/validator/artifact registries, scoped skills, hooks, and operator reports.
- `harness/workflows/repository-freshness-before-launch.yaml` now defines the Git freshness gate that must run before an agent treats a missing local launcher or validator as repository truth.
- The gate distinguishes the executing worktree from the fetched remote ref and requires the selected executing commit to be proven before canonical command selection.
- A clean, owned branch that is strictly behind its intended remote may advance only through a fast-forward-only update.
- A dirty, diverged, or separately owned worktree is preserved; current repository behavior is executed from an isolated worktree at the fetched commit instead.

## Repaired failure

The recurring failure was simple but costly: **fetching origin/main did not update local main**. The remote contained newer tracked deployment surfaces while the executing worktree still pointed at an older commit. A missing launcher in that stale worktree was then incorrectly treated as if the launcher did not exist in the repository.

That interpretation is now forbidden by the harness. A fresh agent must prove the relationship between local `HEAD` and the intended fetched remote commit before it concludes that a tracked path is absent. If a launcher is expected, the agent checks the path at the refreshed commit and then updates the clean owned branch or creates an isolated worktree.

## Known trap

`git fetch origin` updates remote-tracking refs such as `origin/main`; it does **not** move the checked-out `main` branch or update files in the current worktree. Therefore:

- `origin/main` may contain a launcher that the local worktree does not yet contain.
- a successful fetch is not repository convergence;
- a missing launcher after fetch is not a reason to invent an alternate deployment path;
- a dirty worktree is not permission to reset or clean local work merely to reach the refreshed commit.

## Required repair behavior

1. Inspect `git status --short`, current branch, and local `HEAD`.
2. Fetch the intended remote ref without force.
3. Resolve the exact fetched commit.
4. Compare local `HEAD` to that commit.
5. If clean, owned, and strictly behind, use a fast-forward-only update.
6. If dirty, diverged, or ownership is unclear, preserve it and create an isolated worktree at the fetched commit.
7. Verify the expected tracked launcher or authority in the selected executing tree.
8. Only then choose and run the canonical command from the harness command/deployment-state registries.

## Validation

```text
python harness/validators/validate-repository-freshness-contracts.py
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

The freshness validator is also wired into the repository-owned pre-commit, pre-push, and harness registry CI gates.

## Remaining proof limits

This harness repair proves repository selection and preservation behavior only. It does not prove a target is reachable, that a deployment ran, that a restart occurred, or that application/runtime acceptance succeeded. Those claims remain owned by their registered deployment/runtime artifacts.
