# Harness Discipline

Harness discipline is the operational posture for every repo mutation: merging,
cherry-picking, squashing, closing, deleting branches/PRs, commenting on PRs,
and managing worktrees. It applies to software, harnesses, automation, repo
tooling, MCP/local-agent work, deployment scripts, and game/app automation.

## Core loop

Every harness-governed operation follows this loop:

```text
request
  -> evidence (git state, branch list, diff, log, CI status)
  -> bounded plan (name scope, forbidden scope, expected artifacts)
  -> coherent action (one useful tracked implementation slice)
  -> preservation checkpoint (recoverable boundary, not completion proof)
  -> targeted validation (smallest relevant parser, contract, or test)
  -> repair (only proven failures)
  -> preservation checkpoint (when repair changes tracked work)
  -> broader validation (only after useful progress is recoverable)
  -> completion artifacts (changed files, final commit SHA, push confirmation)
  -> report (what changed, what didn't, what was skipped)
  -> next decision
```

Skip a step only when the step is impossible in context, and name the skip.

For a small docs-only or single-file mutation, the action commit may be both the preservation checkpoint and the completion commit. The report must still distinguish preservation proof from validation proof.

## Naming convention

Every serious harness operation must declare these fields before acting:

| Field | Meaning |
|-------|---------|
| Repo | Absolute path or short name |
| Branch | Current branch or target branch |
| PR/sprint | PR number or sprint name |
| Lane | Which agent lane owns this work |
| Scope | What this operation may change |
| Forbidden scope | What this operation must not change |
| Expected artifacts | Files, commits, or reports this operation should produce |

## Incremental checkpoint discipline

Harness-governed work must preserve useful progress before expanding the cost or risk of the operation.

### Required checkpoint boundary

Create a preservation checkpoint after the first coherent tracked implementation slice and before any of the following:

- broad or full-suite validation;
- long-running tests or builds;
- runtime or device proof;
- repository-wide refactoring;
- extended diagnostics;
- external API or model work subject to context, token, time, or quota limits;
- switching agents, models, worktrees, or execution environments.

### Acceptable checkpoint forms

In priority order:

1. A bounded WIP commit on the owned feature branch.
2. A patch or bundle that includes both modified tracked files and newly created files.
3. A documented exact blocker with `git status --short`, `git diff --stat`, and recovery paths.

A plain `git diff` patch is insufficient when untracked files are part of the implementation. Newly created owned files must be staged, committed, or copied into the recovery artifact explicitly.

### Checkpoint safety

Before checkpointing:

- confirm the current branch and worktree;
- review the staged file list;
- exclude unrelated dirty files;
- exclude secrets, credentials, runtime evidence, registry exports, generated logs, device identities, and machine-local artifacts;
- record the checkpoint commit SHA or recovery artifact path.

### Resume contract

A resumed agent must:

1. inspect the latest checkpoint;
2. verify its changed-file boundary;
3. run the smallest failing or pending validation first;
4. repair only the proven failure;
5. avoid repeating completed discovery or implementation;
6. create a new checkpoint before expanding validation again.

### Proof boundary

A preservation checkpoint proves only that work can be recovered.

It does not prove:

- tests pass;
- the build passes;
- runtime behavior works;
- a PR is mergeable;
- the sprint is complete.

### Harness report fields

Every interrupted or resumed sprint report must include:

- latest checkpoint SHA or artifact path;
- files preserved;
- files deliberately excluded;
- last completed validation;
- first pending or failing validation;
- exact resume command.

### Machine-readable checkpoint fields

Planning and completion artifacts should use these fields when a substantial sprint crosses a checkpoint boundary:

```json
{
  "checkpointRequired": true,
  "checkpointReason": "before_broad_validation",
  "checkpointType": "wip_commit",
  "checkpointSha": "abc123...",
  "preservedFiles": [],
  "excludedDirtyFiles": [],
  "lastCompletedValidation": "",
  "nextValidationCommand": ""
}
```

### Future validator seam

A later harness refactor should add a validator that fails planning or completion artifacts when a substantial sprint has:

- changed or created tracked files;
- started broad validation;
- but recorded no checkpoint SHA or recovery artifact.

Include a negative fixture for the Bluetooth interruption failure mode: a recovery patch made with `git diff` alone does not preserve untracked files.

## Checkpointed refactoring discipline

Refactoring must be planned as recoverable slices, not one uninterrupted edit.

For each slice:

1. Name the invariant being preserved.
2. Name the owned files.
3. Make the smallest coherent structural change.
4. Run the narrowest relevant parser, contract, or targeted test.
5. Create a preservation checkpoint.
6. Expand to the next slice only after the current slice is recoverable.
7. Run broad validation only after all bounded slices have checkpoints.

Required checkpoints include:

- before renaming or moving multiple files;
- before changing shared contracts or schemas;
- before updating all callers;
- before running the full test suite;
- before runtime proof;
- before delegating the next phase to another agent.

When interrupted:

- preserve the current diff and every owned untracked file;
- record whether the slice is structurally complete;
- record the first failing or unrun validation;
- provide the exact smallest resume command;
- do not ask the next agent to reload the full original planning context.

Never mix unrelated dirty files into a refactoring checkpoint. Never treat a WIP checkpoint as completed or validated work.

If a repo-local skill named `Planning a Refactoring` or equivalent exists, it must include this checkpointed refactoring rule. Do not guess the skill path; verify the path from the repository before editing it.

## Operation-by-operation discipline

### Merge

| Step | Requirement |
|------|-------------|
| Pre-merge evidence | `git status --short`, `git log --oneline <base>..<head> -10`, `git diff --stat <base>..<head>`, CI status |
| Plan | Name base branch, head branch, merge strategy (merge commit, squash, rebase). State whether the merge is authorized by scope. |
| Action | Execute the merge. |
| Artifacts | Merge commit SHA, updated branch state. |
| Validation | `git status --short`, `git log --oneline -3`, verify no unrelated files changed. |
| Report | Name commit SHA, changed files, any conflicts resolved, any skipped checks. |

Do not merge when:
- The worktree is dirty.
- CI is red and the failure is not proven unrelated.
- The PR contains files outside its declared scope.
- The merge would introduce secrets, credentials, or live data.

### Cherry-pick

| Step | Requirement |
|------|-------------|
| Pre-pick evidence | `git log --oneline --decorate` on source branch, `git status --short` on target, `git diff` of the specific commit. |
| Plan | Name source commit SHA, target branch, reason the commit belongs on the target. Verify the commit is not already in the target history. |
| Action | `git cherry-pick <sha>`. |
| Artifacts | Cherry-pick commit SHA, updated branch state. |
| Validation | `git diff HEAD~1` to confirm only intended changes landed. `git status --short` to confirm clean tree. |
| Report | Name original SHA, cherry-pick SHA, files changed, conflicts resolved (if any). |

Do not cherry-pick when:
- The commit conflicts with target and the resolution would change behavior.
- The commit depends on context not present in the target.
- The cherry-pick would silently expand scope.

### Squash

| Step | Requirement |
|------|-------------|
| Pre-squash evidence | `git log --oneline <base>..<head>`, `git diff --stat <base>..<head>`, branch ownership. |
| Plan | Name the range of commits being squashed, the target commit message, and why squashing is appropriate (e.g., cleaning WIP history before merge). |
| Action | `git rebase -i` or `git merge --squash`. |
| Artifacts | Single squashed commit SHA, commit message. |
| Validation | `git log --oneline -1`, `git diff --stat HEAD~1`, verify the squashed commit contains all intended changes and no extra files. |
| Report | Number of commits squashed, resulting SHA, changed files, any dropped changes. |

Do not squash when:
- Individual commit history is required for audit or review.
- The squash would silently drop a behavioral change.
- The PR has already been reviewed commit-by-commit.

### Close PR

| Step | Requirement |
|------|-------------|
| Pre-close evidence | PR status, review comments, CI status, whether work is merged or abandoned. |
| Plan | State why the PR is closing (merged, superseded, abandoned, stale). State whether the branch should be deleted. |
| Action | `gh pr close <number>`. |
| Artifacts | Closed PR URL, closure comment if not automatic. |
| Validation | `gh pr view <number> --json state,closedAt`. |
| Report | PR number, title, final state, branch deletion status. |

Do not close a PR silently. Always leave a closure comment naming:
- Whether the work was merged and where.
- Whether the branch was deleted.
- Whether the work is superseded by another PR.
- Whether the PR is stale and when it may be reopened.

### Delete branch

| Step | Requirement |
|------|-------------|
| Pre-delete evidence | `git branch --merged <base>` to confirm the branch is fully merged. `git worktree list` to confirm no worktree holds the branch. `git log --oneline <base>..<branch>` to confirm zero ahead commits. |
| Plan | Name the branch, confirm it is merged, confirm no worktree holds it, confirm no open PR references it. |
| Action | `git branch -d <branch>` (local), `git push origin --delete <branch>` (remote). |
| Artifacts | Deletion confirmation (local and remote). |
| Validation | `git branch --list <branch>`, `git branch -r --list origin/<branch>`. |
| Report | Branch name, whether local and remote were deleted, any worktree that held it. |

Do not delete when:
- The branch is not fully merged.
- A worktree currently checks out the branch.
- An open PR references the branch.
- The branch has uncommitted work in any worktree.

### Comment on PR

| Step | Requirement |
|------|-------------|
| Pre-comment evidence | PR context, existing comment thread, open review items. |
| Plan | State what the comment communicates (status update, review finding, blocker, handoff, closure note). |
| Action | `gh pr comment <number> --body "..."`. |
| Artifacts | Comment URL. |
| Validation | `gh api repos/{owner}/{repo}/issues/<number>/comments --jq '.[-1].body'`. |
| Report | Comment content summary, position in thread. |

Every PR comment must include:
- What changed since the last comment.
- What is still open.
- What the next action is.

Do not leave comments that assert completion without evidence (validator output, CI status, git state, or file proof).

## Worktree discipline

| Step | Requirement |
|------|-------------|
| Pre-create evidence | `git worktree list`, branch availability, disk space. |
| Plan | Name the branch, the worktree path, the sprint or PR it serves. |
| Action | `git worktree add <path> <branch>`. |
| Artifacts | Worktree path, branch association. |
| Validation | `git -C <path> status --short`, `git -C <path> log --oneline -1`. |
| Report | Worktree path, branch, HEAD commit, clean/dirty state. |

Do not create worktrees when:
- The target branch is already checked out in another worktree.
- The path already exists and is not an empty directory.
- The worktree would live under a gitignored or non-repo path without explicit operator intent.

When cleaning up worktrees:
- Verify `git status --short` is clean or stash/commit dirty work first.
- `git worktree remove <path>` (clean) or `git worktree remove <path> --force` (dirty, after operator authorization).
- Delete the branch if it is merged and no longer needed.

## Evidence minimum

Every harness-governed operation must leave at least one of:

- A commit SHA with a descriptive message.
- A `git status --short` proving clean or known-dirty state.
- A `git log --oneline` snapshot.
- A validator or test output.
- A PR comment or closure note.

Do not claim completion without proof. Do not claim PASS without validator output.

## Connected parts

This discipline connects to:

- [`AGENTS.md`](../AGENTS.md) — agent instructions and hard rules
- [`docs/OPERATIONAL_POSTURE.md`](OPERATIONAL_POSTURE.md) — lane model and low-waste posture
- [`docs/SPRINTS.md`](SPRINTS.md) — sprint working rules
- [`docs/LOCAL_DEVELOPMENT_HARNESS.md`](LOCAL_DEVELOPMENT_HARNESS.md) — local harness layers
- [`docs/HARNESS_COMPLETION_PLAN.md`](HARNESS_COMPLETION_PLAN.md) — harness completion roadmap
- [`docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md`](DEPLOYMENT_TEARDOWN_DOCTRINE.md) — deployment mutation rules
- [`docs/handoff/sysadminsuite-agent-coordination.md`](handoff/sysadminsuite-agent-coordination.md) — agent lanes and hard rules
- [`Config/operational-posture.json`](../Config/operational-posture.json) — machine-readable posture authority
