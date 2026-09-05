# AutoLogon closeout preparation

## Purpose

`Prepare-SysAdminSuiteAutoLogonCloseout.cmd HOST` is the Guest/Internet preparation front door for an AutoLogon-only closeout. It exists to prevent a field session from spending its deployment window rediscovering stale controller clones, repairing historical field snapshots, or reconstructing the staging/audit sequence by hand.

The preparer **does not deploy AutoLogon** and does not contact the target. It prepares the controller and sealed runtime so the next operator action can be the existing protected deployment transaction.

## Guest / Internet preparation

Run from any current SysAdminSuite checkout:

```cmd
Prepare-SysAdminSuiteAutoLogonCloseout.cmd HOST
```

The preparer:

1. validates the one explicit target only as a hostname/FQDN command-data shape;
2. accepts only the official `EndeavorEverlasting/SysAdminSuite` repository, current `main`, and canonical `C:\SASAL` runtime as closeout authorities; there are no caller overrides for another repository/ref/runtime;
3. acquires a machine-wide named mutex for the whole preparation transaction so two sessions cannot race the shared controller, manifest, runtime verification receipt, sealed runtime, or fixed-path handoff;
4. before any fetch or staging work, disables and archives any prior fixed-path `Run-Prepared-AutoLogon.cmd` and readiness receipt so a failed new attempt cannot leave yesterday's target executable at the documented path;
5. maintains a dedicated `%LOCALAPPDATA%\SysAdminSuite\autologon-closeout-controller` instead of adopting historical operator checkouts as authority;
6. preserves a dirty, malformed, wrong-origin, or otherwise unusable generated closeout controller before replacement;
7. refreshes provider truth with `git fetch --all --prune --tags` and pins the generated controller to the exact current `origin/main` head;
8. delegates Guest acquisition, dirty `C:\SASAL` preservation, field-ready derivation, installed `sas` refresh, and sealed short-runtime staging to the canonical `scripts\Refresh-SasOperatorCommand.ps1` implementation;
9. re-fetches `origin/main` after staging. If main moved while the runtime was being prepared, it repeats the canonical refresh/stage cycle rather than carrying stale proof forward. This convergence is bounded to three passes by default and fails closed without a handoff if main keeps moving;
10. requires the resulting `sas-autologon-short-runtime/v2` manifest to identify the same post-refresh current `origin/main` commit, Guest preparation, local-filesystem-only runtime transport, removed runtime remotes, and disabled protected Git network activity;
11. runs the canonical full `C:\SASAL\scripts\Test-SasAutoLogonRuntimeSeal.ps1` audit against that exact commit;
12. only after the audit returns `PASS / AUTOLOGON_RUNTIME_SEAL_VERIFIED`, uses the handoff generator from that exact sealed runtime to create a machine-local pinned deployment handoff.

Historical operator checkouts are never reset, cleaned, rebased, or used as current deployment authority by this workflow. The preparer's native Git wrapper also preserves the current Windows PowerShell 5.1 empty-output contract used by `sas refresh`, so a successful silent Git check cannot become a null `.Trim()` failure.

## Generated handoff

Successful preparation writes machine-local state beneath:

```text
%LOCALAPPDATA%\SysAdminSuite\autologon-closeout
```

The important files are:

```text
Run-Prepared-AutoLogon.cmd
autologon-closeout-readiness.json
```

Both surfaces are registered in the harness artifact chain. The readiness receipt is explicitly non-authoritative. It records the requested target, exact prepared commit, sealed runtime, canonical verification receipt, handoff path, and the facts that preparation performed no target contact, no target mutation, and no crash-safe deployment run.

The generator refuses to overwrite an existing fixed-path handoff/receipt; the preparer must disable the old pair first. New output is written under unique pending names. The non-executable readiness receipt is published first and the executable fixed-path CMD is published **last**, so a partial generation failure cannot newly expose the documented deployment command before its matching receipt exists.

The generated CMD is the only next command the preparation workflow asks the operator to carry across the network transition. It is pinned to the target and prepared commit and calls only:

```text
C:\SASAL\Bootstrap-SysAdminSuiteAutoLogon.cmd
```

It does not duplicate the network guard, host eligibility, interrupted recovery, S4U apply, cleanup, restart, or evidence implementation.

The harness registers this protected continuation as `autologon-closeout-deploy`; its successful product outcome remains the existing canonical `autologon-field-deployment-result`, not the preparation receipt or generated CMD.

## Protected deployment

After preparation reports:

```text
AUTOLOGON_CLOSEOUT_PREPARATION_COMPLETED
```

transition to an approved protected Northwell network and run the exact `NEXT COMMAND` emitted by the preparer. Normally that is the generated local handoff:

```powershell
& "$env:LOCALAPPDATA\SysAdminSuite\autologon-closeout\Run-Prepared-AutoLogon.cmd"
```

The protected bootstrap re-verifies the prepared commit and complete sealed runtime before the crash-safe transaction. Protected-network admission, canonical target resolution, exact local eligibility, recovery convergence, apply-once behavior, S4U application, cleanup, restart observation, and terminal evidence remain owned by the existing AutoLogon deployment lane.

Do not manually reboot during the supported restart wrapper. Do not blindly rerun a failed transaction after mutation may have begun; use durable evidence and the existing `sas context`, `sas next`, and `sas evidence` surfaces.

## Completion gate

Preparation success is **not** deployment success. The closeout is deployed only when the existing terminal field result proves:

```text
status = COMPLETED
classification = AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

with the existing required host-eligibility, apply, pre-reboot-ready, restart-offline, restart-online, and restart-task-cleanup evidence.

## Validation and proof ceiling

Repository validation for this preparation surface includes:

```text
python Tests/survey/test_autologon_closeout_preparation_contracts.py
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File Tests\PowerShell\AutoLogonCloseoutPreparation.Tests.ps1
python harness/validators/validate-harness-registries.py
python harness/validators/validate-outcome-contracts.py
```

CI also parses the preparation surfaces under Windows PowerShell 5.1, executes the real native-Git helper against a successful silent Git command, executes the generated handoff through `cmd.exe` from paths containing spaces, and checks patch whitespace.

This proves repository routing, machine-wide preparation serialization contracts, stale-handoff invalidation, bounded current-main convergence, Windows parsing, PowerShell 5.1 silent-Git handling, safe local handoff publication, exact target/commit binding, verified-runtime receipt admission, current-controller isolation, and no-target preparation boundaries. It cannot prove the physical Admin Box network, live target reachability, AutoLogon mutation, restart, automatic sign-in, or operator acceptance; those remain field evidence.
