# Rework Prevention Skill

## Trigger

Use this skill when work is resuming after a failed run, terminal crash, shell/network change, stale launcher, source/catalog mismatch, hidden exit code, uncertain cleanup, or repeated diagnostic side trip.

Use it alongside the normal task skill. It is a recovery and execution-discipline overlay, not a product authority.

Do not use it to modify `AGENTS.md`, change product behavior, infer a device profile, commit live evidence, expose secrets, or perform destructive cleanup.

## Required inputs

- repository root and current branch
- requested goal and owned/forbidden scope
- latest known run/evidence when available
- current Git/PR state
- current network classification when the next command is network-sensitive
- target/profile/lane state only when already proven by an authorized source

## Load order

1. Read `AGENTS.md` without modifying it.
2. Read `CODEBASE_MAP.md`.
3. Read `harness/api/rework-prevention-registry.json`.
4. Read `harness/workflows/rework-prevention-recovery.yaml`.
5. Read `harness/api/harness-validator-registry.json` and `harness/api/harness-artifact-registry.json`.
6. Read only the product/task skill selected by the normal router.

## Procedure

### Evidence before retry

Recover the latest proven boundary before issuing a retry. Prefer tracked state, run artifacts, machine-local session state, and PR/commit evidence over remembered chat state. If cleanup is unknown, treat it as unproven until exact run-owned resources are checked or absence is proven.

### Terminal is metadata

CMD versus PowerShell may be recorded for diagnostics, but it must not determine the workflow. Prefer repository-owned launchers and commands that do not depend on interactive variables, pasted functions, or manually reconstructed `try`/`catch`/`finally` fragments.

### Network is execution state

Every network-sensitive command must state and verify its required network class. A wrong-network result stops at that boundary and returns one exact network transition plus the canonical next command. Do not compensate with unrelated probing.

### Source readiness precedes mutation

For multi-package or bundle operations, prove all sources before target staging or execution. Record expected entrypoints, actual inventory, hashes, missing/unexpected files, and drift. Do not guess a replacement filename to satisfy stale metadata.

### Recovery is run-scoped

Recovery may inspect and remove only resources owned by the exact failed run. Recover checkpoint/result evidence first when possible, preserve proven completed work, verify cleanup or absence, and block a new mutating run while cleanup remains unproven.

### Exit codes and checkpoints are evidence

Wrappers and dispatchers propagate nonzero child exits. Long-running workflows emit stable phase/package checkpoints into the run artifact immediately so a new shell or conversation can resume from the last proven boundary.

### Focused validators before broad suites

Run the smallest validator that owns the changed surface, repair that failure, and rerun it before broader suites. Classify broad-suite failures as changed-surface or baseline before expanding scope. Do not spend a field window repairing unrelated architecture.

## Failure handling

- Preserve the failure boundary and artifact.
- Map the failure signal to `known_failure_patterns` in the rework-prevention registry.
- Apply only the listed prevention controls plus the owning task workflow.
- Never weaken a validator to obtain green output.
- If a real external gate remains, name the owner, dependency, executable action, expected artifact, and completion condition.

## Validation

Run:

```text
python harness/validators/validate-rework-prevention-contracts.py
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

Then select additional changed-surface validators from `harness/api/harness-validator-registry.json`.

## Expected outputs

- no repeated operator reacclimation when evidence already contains the state
- one explicit next network for network-sensitive work
- source-readiness proof before target mutation
- exact run-scoped recovery when cleanup is uncertain
- preserved completed work on resume
- propagated failures and stable checkpoints
- focused validation evidence
- one exact next command/action when a genuine unproven gate remains

## Proof ceiling

This skill proves that recovery and rework-prevention rules are selected and enforced by harness contracts. It does not itself prove a live source share, target mutation, deployment result, cleanup result, reboot, or runtime observation.
