# Remote-First Workflow

GitHub `origin/main` is the only source of truth for SysAdminSuite development. Local clones that lag behind `main` must not drive branch or merge decisions.

## Before any work

```bash
git fetch origin
git checkout main
git reset --hard origin/main   # only when you have no local commits to keep
```

Record the HEAD SHA from `git rev-parse --short origin/main` in the current [branch convergence ledger](BRANCH_CONVERGENCE_2026-05-27.md).

## Starting a feature

```bash
git checkout -b feature/short-description origin/main
# implement ...
git push -u origin feature/short-description
gh pr create --base main --title "..." --body "..."
```

Rules:

- Branch **only** from `origin/main`, never from stale local `main`, `audit-deployment-*`, or old feature tips.
- One feature lane = one PR into `main`.
- Do not push operational artifacts (live hostnames, trackers, generated `survey/output/`, `survey/artifacts/`).

## Inspecting open work without a trusted local clone

```bash
gh pr list --state open
gh pr view <number> --json headRefName,baseRefName,state,mergeable
git fetch origin
git log --oneline origin/main..origin/<head-branch>
git diff --stat origin/main...origin/<head-branch>
```

Use PR comments (`gh pr comment`) when closing or superseding stale PRs. Link the replacement PR or ledger row.

## When a PR is stale

If a branch is more than a few commits behind `main`:

1. Do **not** use GitHub “Update branch” and merge as-is when the gap is large.
2. Close the stale PR with a supersede comment.
3. Open a **fresh** branch from `origin/main` and cherry-pick or re-apply only the still-needed files.
4. Run CI/contract tests on the fresh branch.

## Direct commits to main

Avoid landing features directly on `main` without a PR. If it happens, add a row to the convergence ledger immediately.

## Related docs

- [BRANCH_CONVERGENCE_2026-05-27.md](BRANCH_CONVERGENCE_2026-05-27.md) — branch and PR classifications
- [PR6_HARVEST_PLAN.md](PR6_HARVEST_PLAN.md) — Neuron PowerShell harvest policy
- Issue [#13](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/13) — convergence control issue
