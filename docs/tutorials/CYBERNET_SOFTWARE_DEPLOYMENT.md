# Cybernet software deployment tutorial

## Audience and current operator workflow

This tutorial is for authorized technicians and Windows administrators deploying the approved Cybernet clinical software stack and, when requested, completing AutoLogon through its separate final lane.

The **primary technician surface** is the installed portable operator command:

```powershell
sas
```

For one explicitly authorized Cybernet, the current field sequence is:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
sas autologon Remote <AUTHORIZED-CYBERNET>
```

Do not reconstruct the deployment from older manual package-set examples when the current operator surface is available.

## Current state model

The clinical workstation software state is intentionally split:

1. `cybernet-clinical-core` — five approved applications;
2. AutoLogon — separate and last through Kerberos SMB/S4U;
3. attended reboot and direct automatic-sign-in observation when runtime proof is requested;
4. runtime proof from the actual AutoLogon desktop session.

The historical six-package LocalSystem `cybernet-clinical-workstation` set is **not** the current field AutoLogon route while canonical SYSTEM AutoLogon remains blocked by failed runtime qualification. The current AutoLogon apply lane is `sas autologon Remote HOST`.

If the five clinical-core applications are already proven installed and accepted, preserve them and skip reinstall. Move directly to the remaining requested AutoLogon state.

## Roles and boundaries

| Location | Operator action | What happens there |
| --- | --- | --- |
| Windows admin workstation or admin VM | Run `sas cybernet Deploy HOST` and review local evidence | Package-set validation, Northwell network gate, dry admission check, live SYSTEM deployment, result collection, cleanup verification |
| Approved software share | Read-only source | Supplies only the exact catalog-pinned MSI/EXE payloads |
| Target Cybernet workstation | No manual command required during clinical-core deployment | Receives run-scoped payloads; Task Scheduler launches approved installers as SYSTEM |
| Windows admin workstation | Run `sas autologon Remote HOST` | Stages and executes the approved AutoLogon installer through Kerberos SMB/S4U without requiring a target-side login |
| Technician at target / attended session | Observe reboot/sign-in and run runtime proof | Directly proves automatic sign-in and actual-session application/runtime behavior |

These lanes do not embed passwords, enable WinRM, weaken firewall policy, or reboot a workstation without separate authorization.

## Prerequisites

Before live deployment confirm:

- the change/ticket, target, maintenance window, and operator are authorized;
- the controller is an approved Windows admin workstation or admin VM on a network accepted by the SysAdminSuite network guard;
- the current Windows identity has the required package-share and target administrative access;
- Git for Windows, Python 3, Windows PowerShell, and Task Scheduler tooling are available;
- the target is one explicit hostname/FQDN for the initial pilot;
- local evidence remains outside Git.

Never paste a password into a deployment command.

## 1. Deploy the five-package clinical core

Run:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

This single invocation performs:

1. exact validation of the tracked `cybernet-clinical-core` package-set membership and order;
2. confirmation that AutoLogon is not part of the clinical-core set;
3. the current PowerShell Northwell network gate;
4. the controller dry run as an admission gate;
5. immediate continuation into live deployment when that admission gate passes;
6. per-package result collection;
7. scheduled-task and run-scoped staging cleanup verification.

The command does **not** reboot the target.

Required terminal status:

```text
CLINICAL_CORE_DEPLOYMENT_COMPLETED
```

Canonical summary:

```text
survey\output\runs\cybernet-clinical-core\cybernet-clinical-core-*\cybernet_clinical_core_deployment_summary.json
```

The summary must identify:

```text
package_set_id=cybernet-clinical-core
autologon_included=false
status=CLINICAL_CORE_DEPLOYMENT_COMPLETED
```

Preserve the referenced controller results CSV. If the deployment returns nonzero or reports `ACTION_REQUIRED`, preserve the emitted evidence and do not blindly rerun the target.

## 2. Technician acceptance for the clinical core

A successful installer exit does not prove the application works. Confirm the expected shortcuts/applications exist and open through the normal technician workflow.

When the five clinical-core applications are already accepted from prior work, preserve that evidence instead of reinstalling them just to reach AutoLogon.

## 3. Apply AutoLogon separately and last

Run:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

This is the current real AutoLogon apply lane. It stages the approved AutoLogon package through Kerberos SMB, executes it through a passwordless S4U scheduled task under the authorized domain principal, validates the resulting pre-reboot state, and performs cleanup.

Required positive classification:

```text
KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING
```

Canonical deployment artifact:

```text
survey\output\runs\autologon-kerberos-s4u\autologon-kerberos-s4u-*\autologon_kerberos_s4u_pilot_result.json
```

The following are **not substitutes** for that positive deployment artifact:

- fixture E2E success;
- transport-only `LIVE CERT PASS`;
- installer process start;
- installer exit code `0` or `3010` by itself;
- expected registry settings without the correlated S4U deployment result.

## 4. Reboot/sign-in is not yet proven — continue when runtime proof is requested

`KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` proves the pre-reboot AutoLogon configuration ceiling only.

**The work item is not finished when deployment plus runtime proof was requested.**

The next state transition is:

1. obtain the separately required authorization for an attended reboot;
2. reboot the same target through the approved site process;
3. directly observe automatic sign-in to the expected workstation account;
4. from that actual AutoLogon desktop, run the runtime proof.

Do not infer reboot/sign-in from the S4U artifact. Do not fall back to fixture, transport, or live-search testing after the positive pre-reboot classification.

## 5. Run actual-session runtime proof

From the actual automatically signed-in desktop session:

```powershell
scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd targets\local\autologon-runtime.json
```

Required runtime classification:

```text
TECHNICIAN_OBSERVED_LIVE_RUNTIME
```

The runtime summary must report:

```text
proof_level=TECHNICIAN_OBSERVED_LIVE_RUNTIME
runtime_proof=true
overall_success=true
```

Pre-reboot deployment and runtime proof are separate artifacts. Neither one substitutes for the other.

## Generic single-package controller — advanced/reference use

The underlying compatibility controller remains:

```text
bash/apps/sas-install-apps.sh
```

Use it only for a specifically approved package-level workflow that is not already covered by the higher-level technician command. A single package must be enabled in `configs/software-packages/approved-apps.json`; an ordered package set must be enabled in `configs/software-packages/windows-native-package-sets.json`.

Example BCA dry run:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy \
  --dry-run
```

Example BCA live run after the approved review gate:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy
```

The controller creates a unique run-scoped staging folder, uses a one-time SYSTEM scheduled task, retrieves the result, and removes only that task and run-scoped staging root.

Do **not** use the generic controller to reconstruct the historical six-package `cybernet-clinical-workstation` live path for AutoLogon. Current field AutoLogon is the S4U lane above.

## Troubleshooting

### `Admin share unavailable or access denied`

Confirm the exact hostname/FQDN, current network context, current Windows admin token, and `\\TARGET\C$` access. Do not add credentials to the command or weaken endpoint policy.

### Northwell network gate stops the deployment

Do not bypass it. Use the bounded network choices offered by SysAdminSuite and rerun only after the approved network posture is confirmed.

### Clinical-core dry run fails

Live clinical-core deployment was not started. Read the emitted `cybernet_clinical_core_deployment_summary.json` and dry-run console log, repair the named gate, and then retry the same authorized target.

### Clinical-core live deployment fails

Preserve the summary, deploy console log, and controller result CSV. Do not blindly retry. Inspect the exact failed package/task/staging/cleanup boundary first.

### AutoLogon S4U deployment fails

Preserve `autologon_kerberos_s4u_pilot_result.json` and classify the exact S4U failure. Do not switch back to the blocked canonical SYSTEM AutoLogon path and do not require a technician to log in locally merely to install AutoLogon.

### AutoLogon reaches `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING`

That is **success for the pre-reboot deployment state**, but it is not runtime proof. If runtime proof is part of the requested work, proceed to the separately authorized attended reboot and direct automatic-sign-in observation. Do not restart diagnostic loops.

### Exit code `3010`

Record `restart required`. No deployment lane in this tutorial authorizes an automatic reboot. Use the separately approved site reboot process.

### Cleanup cannot be proven

Do not classify that deployment stage as complete. Inspect only the unique task and run root named in the controller evidence. Never delete the parent staging tree broadly.

## Operator closeout checklist

- [ ] Exact authorized target used.
- [ ] Five-package clinical core was either already proven accepted or reached `CLINICAL_CORE_DEPLOYMENT_COMPLETED`.
- [ ] Clinical-core controller result CSV retained locally.
- [ ] AutoLogon, when requested, ran through `sas autologon Remote HOST` rather than the historical SYSTEM package-set path.
- [ ] Pre-reboot AutoLogon reached `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` before any runtime claim.
- [ ] Reboot/sign-in was **not** claimed from the pre-reboot artifact.
- [ ] Separately authorized attended reboot was performed when runtime proof was requested.
- [ ] Automatic sign-in was directly observed on the real target.
- [ ] Runtime proof reached `TECHNICIAN_OBSERVED_LIVE_RUNTIME` with `runtime_proof=true` and `overall_success=true` when required.
- [ ] Failed targets were reviewed individually before retry.
- [ ] No credentials, live evidence, or machine-local artifacts were committed.

## Related references

- Start-here operator page: [`../../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md`](../../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md)
- Technical transport reference: [`../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md)
- AutoLogon S4U reference: [`../AUTOLOGON_KERBEROS_S4U_PILOT.md`](../AUTOLOGON_KERBEROS_S4U_PILOT.md)
- Deployment teardown rules: [`../DEPLOYMENT_TEARDOWN_DOCTRINE.md`](../DEPLOYMENT_TEARDOWN_DOCTRINE.md)
- Package qualification boundary: [`../PACKAGE_VM_QUALIFICATION_PROFILES.md`](../PACKAGE_VM_QUALIFICATION_PROFILES.md)
