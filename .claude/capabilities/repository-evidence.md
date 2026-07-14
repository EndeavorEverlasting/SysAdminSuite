# Repository Evidence Capability

## Contract

Recover operational truth from the repository before selecting or changing work.

## Required evidence

- repository root, current branch, HEAD, remotes, worktrees, and dirty/conflicted state;
- recent commits and changed files;
- active PRs, stacked branches, review findings, and collision risks when available;
- local operating law, manifests, entrypoints, validators, workflows, schemas, plans, and handoffs relevant to the task;
- exact unavailable tools and the command that must be run later.

## Invariants

- Repository content and Git history outrank remembered chat context.
- Timestamps and filenames are weak evidence without content or history.
- Preserve dirty work before checkout, restore, rebase, clean, branch deletion, or worktree removal.
- Use an isolated worktree when the current dirt belongs to another lane.
- Distinguish `FACT`, `INFERENCE`, and `UNKNOWN` in evidence-led planning.
- Do not crawl dependencies, build output, or generated evidence unless directly relevant.

## Used by

- `.claude/skills/repository-sprint/SKILL.md`
