# Terminal Evidence Survival

A field terminal is a display surface, not the evidence store. SysAdminSuite now treats terminal lifetime and evidence lifetime as separate concerns and routes the AutoLogon field command through the already-merged crash-safe front door.

## What survives

For AutoLogon field execution, use:

```text
Run-AutoLogonCrashSafe.cmd HOST
```

The wrapper delegates to the existing AutoLogon `Remote` transaction in a child PowerShell process. Before that child starts, the runner creates a stable machine-local run directory and writes an initial run result. During and after execution it preserves:

- `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run-id>\field-run-result.json`
- `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run-id>\operator-transcript.txt`
- `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run-id>\autologon-child-output.txt`
- `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run-id>\offline-evidence-recovery.txt`
- `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`
- `%LOCALAPPDATA%\SysAdminSuite\last-evidence.json` when bounded offline evidence discovery succeeds.

The field result records the child exit code and the offline evidence-recovery exit code separately. The latest-pointer file records the stable run root and artifact paths so a new shell or agent can resume diagnosis without relying on the vanished console.

## Recovery after a vanished terminal

1. Read `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`.
2. Inspect the referenced `field-run-result.json`, transcript, child output, and recovery output.
3. Run `sas evidence` only when additional offline artifact discovery is needed.
4. Do **not** rerun target mutation merely because the original terminal disappeared.
5. If product state is ambiguous, follow the existing AutoLogon interrupted-run recovery contract using the preserved product artifacts and target lock state.

## What remains unproven

Evidence survival is not deployment success. The crash-safe `field-run-result.json` proves the outer diagnostic envelope and exit disposition; the canonical `autologon_field_deployment_result.json` remains the proof for restart-complete AutoLogon deployment. A transcript or child exit code alone does not prove application, restart completion, automatic sign-in, or operator acceptance.

Generated evidence remains local and untracked. The repository tracks only the registry, workflow, skill, validator, report, schemas, hooks, and CI contracts that enforce this behavior.

## Validation

Run the focused contract first:

```text
python harness/validators/validate-terminal-evidence-survival.py
```

Then run the existing crash-safe product contract and harness completeness floor:

```text
python Tests/survey/test_autologon_crash_safe_field_runner_contracts.py
python Tests/survey/test_operational_harness_completeness_contracts.py
git diff --check
```

Expected focused result:

```text
PASS: terminal evidence survival harness contracts
```
