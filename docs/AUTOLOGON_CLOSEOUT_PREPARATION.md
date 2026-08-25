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
2. maintains a dedicated `%LOCALAPPDATA%\SysAdminSuite\autologon-closeout-controller` instead of adopting historical operator checkouts as authority;
3. preserves a dirty, malformed, wrong-origin, or otherwise unusable generated closeout controller before replacement;
4. refreshes provider truth with `git fetch --all --prune --tags` and pins the generated controller to the exact current `origin/main` head;
5. delegates Guest acquisition, dirty `C:\SASAL` preservation, field-ready derivation, installed `sas` refresh, and sealed short-runtime staging to the canonical `scripts\Refresh-SasOperatorCommand.ps1` implementation;
6. requires the resulting `sas-autologon-short-runtime/v2` manifest to identify that same exact current head, Guest preparation, local-filesystem-only runtime transport, removed runtime remotes, and disabled protected Git network activity;
7. runs the canonical full `C:\SASAL\scripts\Test-SasAutoLogonRuntimeSeal.ps1` audit against that exact commit;
8. only after the audit returns `PASS / AUTOLOGON_RUNTIME_SEAL_VERIFIED`, generates a machine-local pinned deployment handoff.

Historical operator checkouts are never reset, cleaned, rebased, or used as current deployment authority by this workflow.

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

The readiness receipt is explicitly non-authoritative. It records the requested target, exact prepared commit, sealed runtime, canonical verification receipt, handoff path, and the facts that preparation performed no target contact, no target mutation, and no crash-safe deployment run.

The generated CMD is the only next command the preparation workflow asks the operator to carry across the network transition. It is pinned to the target and prepared commit and calls only:

```text
C:\SASAL\Bootstrap-SysAdminSuiteAutoLogon.cmd
```

It does not duplicate the network guard, host eligibility, interrupted recovery, S4U apply, cleanup, restart, or evidence implementation.

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
```

CI also parses the preparation surfaces under Windows PowerShell 5.1 and checks patch whitespace.

This proves repository routing, Windows parsing, safe local handoff generation, exact target/commit binding, verified-runtime receipt admission, current-controller isolation, and no-target preparation boundaries. It cannot prove the physical Admin Box network, live target reachability, AutoLogon mutation, restart, automatic sign-in, or operator acceptance; those remain field evidence.
