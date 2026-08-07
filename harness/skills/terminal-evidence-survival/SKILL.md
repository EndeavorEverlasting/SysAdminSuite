# Terminal Evidence Survival Skill

## Trigger

Use this harness-scoped skill when a field terminal closed, crashed, vanished, or may disappear before its diagnostic output can be inspected; when an operator asks how to recover evidence from an interrupted run; or when a registered target-mutating command has a crash-safe front door.

For the current AutoLogon field lane, the operator-facing command is `Run-AutoLogonCrashSafe.cmd HOST`. The wrapper delegates to the existing `sas autologon Remote HOST` product path internally; do not hand the direct inner command to a technician when the crash-safe front door is available.

## Required inputs

- requested goal;
- canonical harness command id;
- explicit target and mutation authority when the underlying action mutates a target;
- current repository branch/ref;
- any preserved latest-pointer or run-root path when recovering a prior interrupted run.

## Procedure

1. Read `harness/api/terminal-evidence-survival-registry.json` before choosing an operator command.
2. If the command id has a registered crash-safe front door, use that front door instead of reconstructing the inner PowerShell command.
3. For AutoLogon deployment, run `Run-AutoLogonCrashSafe.cmd HOST`. The crash-safe PowerShell runner creates its stable run root and initial `field-run-result.json` before starting the child product transaction.
4. Require the runner to preserve `operator-transcript.txt`, `autologon-child-output.txt`, `offline-evidence-recovery.txt`, and both child/recovery exit codes. The latest pointer is `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`.
5. On normal child completion, require offline evidence recovery through `Show-SasOperatorEvidence.ps1` and preserve the resulting `last-evidence.json` index when available.
6. If the terminal already vanished, inspect `last-autologon-field-run.json` first. Then use `sas evidence` only for offline discovery of existing artifacts. Do not re-contact or mutate the target merely to reconstruct lost console output.
7. Distinguish the crash-safe field envelope from the canonical product deployment artifact. `field-run-result.json` proves evidence survival and child/recovery disposition; `autologon_field_deployment_result.json` remains the product deployment proof.
8. Keep all generated field evidence machine-local and untracked. Commit only the harness contracts, registries, validators, workflows, reports, and tests.
9. Run `python harness/validators/validate-terminal-evidence-survival.py` before broader validation.

## Failure handling

- A vanished terminal is not permission to rerun the target mutation. Recover local evidence first.
- A nonzero child exit remains a failure even when diagnostics were preserved.
- A nonzero offline-recovery exit also fails the crash-safe envelope and must be reported separately.
- Never swallow an exit code to keep a window open; persist first, then propagate the original failure.
- If the latest pointer is missing or malformed, report that as the smallest evidence-survival failure and do not infer deployment state from memory.
- If preserved evidence is ambiguous about post-apply state, follow the product lane's existing fail-closed recovery contract rather than starting a fresh deployment.

## Expected outputs

- selected crash-safe front door and inner command id;
- stable run root;
- `field-run-result.json`;
- `operator-transcript.txt`;
- `autologon-child-output.txt`;
- `offline-evidence-recovery.txt`;
- `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`;
- child and recovery exit codes;
- canonical product artifact path when one was actually produced;
- one smallest actionable next gate after evidence inspection.

## Proof ceiling

This skill proves routing and preservation discipline around an already-implemented crash-safe field runner. It can establish that evidence survives shell loss and remains recoverable offline. It does not prove that a live target was contacted, mutated, restarted, automatically signed in, or accepted by an operator unless the corresponding product/runtime artifacts independently prove those states.
