# Repository Freshness Harness Status

## Working

- The repository has a canonical fresh-agent intake workflow, codebase map, command/validator/artifact registries, scoped skills, hooks, and operator reports.
- `harness/workflows/repository-freshness-before-launch.yaml` defines the Git freshness gate that must run before an agent treats a missing local launcher or validator as repository truth.
- The gate distinguishes the executing worktree from the fetched remote ref and requires the selected executing commit to be proven before canonical command selection.
- Repository-network access must be explicitly authorized before the workflow contacts the configured Git remote; routing into freshness is not authorization.
- The default branch is preserved in an isolated worktree unless explicit default-branch update authority exists.
- A clean owned non-default branch may advance through a fast-forward-only update only when branch-update authority is explicit.
- A dirty, diverged, separately owned, or unauthorized-to-update worktree is preserved; current repository behavior is executed from an isolated worktree at the fetched commit instead.

## Repaired failure

The recurring failure was simple but costly: **fetching origin/main did not update local main**. The remote contained newer tracked deployment surfaces while the executing worktree still pointed at an older commit. A missing launcher in that stale worktree was then incorrectly treated as if the launcher did not exist in the repository.

That interpretation is now forbidden by the harness. A fresh agent must prove the relationship between local `HEAD` and the intended fetched remote commit before it concludes that a tracked path is absent. The agent may fetch only with repository-network authority and may update a branch only with the corresponding branch-update authority. Otherwise it preserves the branch and uses an isolated worktree.

## Known traps

`git fetch origin` updates remote-tracking refs such as `origin/main`; it does **not** move the checked-out `main` branch or update files in the current worktree. Therefore:

- `origin/main` may contain a launcher that the local worktree does not yet contain.
- a successful fetch is not repository convergence;
- freshness routing does not grant permission to contact the remote;
- a clean stale `main` is not permission to mutate the default branch;
- **do not invent an alternate deployment path** because a launcher is missing from an unrefreshed or stale executing worktree;
- a dirty worktree is not permission to reset or clean local work merely to reach the refreshed commit.

## Required repair behavior

1. Inspect `git status --short`, current branch, local `HEAD`, and the intended/default branch relationship.
2. Require explicit repository-network authority before contacting the configured Git remote.
3. Fetch the intended remote ref without force only after that authority is established.
4. Resolve the exact fetched commit and compare local `HEAD` to it.
5. If the current branch is the default branch, preserve it in an isolated worktree unless explicit default-branch update authority exists.
6. If a non-default branch is clean, owned, strictly behind, and branch-update authority is explicit, use a fast-forward-only update.
7. If dirty, diverged, separately owned, or update authority is absent, preserve it and create an isolated worktree at the fetched commit.
8. Verify the expected tracked launcher or authority in the selected executing tree.
9. Only then choose and run the canonical command from the harness command/deployment-state registries.

## Hook proof

Pre-commit validates the exact staged snapshot. Pre-push validates repository-freshness contracts against the exact pushed ref-update tip in a temporary detached worktree, so dirty or staged-only local state cannot make an invalid pushed snapshot appear valid.

## Validation

```text
python harness/validators/validate-repository-freshness-contracts.py
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

The freshness validator is wired into the repository-owned pre-commit, exact-tip pre-push, and harness registry CI gates.

## Remaining proof limits

This harness repair proves authorized repository selection and preservation behavior only. It does not prove a target is reachable, that a deployment ran, that a restart occurred, or that application/runtime acceptance succeeded. Those claims remain owned by their registered deployment/runtime artifacts.
