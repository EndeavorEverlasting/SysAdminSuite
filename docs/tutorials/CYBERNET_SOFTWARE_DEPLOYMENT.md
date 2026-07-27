# Cybernet software deployment tutorial

## Audience and current operator workflow

This tutorial is for authorized technicians and Windows administrators deploying the approved Cybernet clinical software stack and AutoLogon.

The primary field surface is:

```powershell
sas
```

For one explicitly authorized Cybernet, a complete software deployment is:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

That command owns the complete ordered software state:

1. five approved clinical applications;
2. AutoLogon **last**;
3. automatic target restart;
4. bounded observation that the target left and returned on the already-proven SMB service.

Required terminal status:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

The historical six-package LocalSystem `cybernet-clinical-workstation` controller remains unsuitable because canonical SYSTEM AutoLogon is still blocked by failed runtime qualification. The current orchestrator therefore composes the proven five-package clinical-core engine with the Kerberos/S4U AutoLogon engine and restart-complete wrapper.

## When the clinical apps are already installed

Preserve accepted application state. Do not reinstall the five clinical apps merely to reach AutoLogon.

Run:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

That command applies AutoLogon and restarts the target automatically. Required success classification:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

The intermediate S4U status:

```text
KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING
```

is an internal apply gate only. It is **not** the technician stopping point because AutoLogon does not become effective until the restart occurs.

## What `sas cybernet Deploy` actually does

The orchestrator validates that the tracked full profile equals the clinical-core order plus `autologon` as the final package ID. It then:

1. runs the current Northwell network gate;
2. dry-runs the five-package clinical core as an internal admission gate;
3. continues into live clinical-core deployment in the same invocation;
4. applies AutoLogon last through Kerberos SMB/S4U;
5. requires clean pre-reboot AutoLogon state and S4U cleanup;
6. creates one bounded SYSTEM restart task;
7. starts the restart;
8. waits for TCP/445 to leave and return;
9. verifies the one-time restart task is absent or removes it;
10. writes the final deployment artifact.

The technician is not required to run a separate fixture, transport live-cert, or runtime-proof loop before deployment can complete.

## Canonical artifacts

Full software deployment:

```text
survey\output\runs\cybernet-software-deployment\cybernet-software-deployment-*\cybernet_software_deployment_result.json
```

Required values:

```text
status=CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
autologon_was_last_software_step=true
automatic_reboot_performed=true
restart_offline_observed=true
restart_online_observed=true
```

AutoLogon-only deployment:

```text
survey\output\runs\autologon-s4u-deployment\autologon-s4u-deployment-*\autologon_s4u_deployment_result.json
```

Required values:

```text
classification=AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
autologon_applied=true
autologon_was_last_software_step=true
automatic_reboot_performed=true
restart_offline_observed=true
restart_online_observed=true
```

## Deployment means mutation, not another test loop

When an authorized technician asks to deploy software, test AutoLogon on the target, or live-cert the path with deployment authority, a green fixture or transport check is only admission. It must not replace the actual deployment step.

The full and AutoLogon-only commands above perform real target mutation. If an internal dry run or preflight fails, the command stops before mutation and records the gate. If those gates pass, the same invocation continues.

Do not tell the technician that a process exit code, fixture result, or transport-only certificate is deployment completion.

## Runtime proof after deployment

Software deployment completes after the required restart cycle. Automatic sign-in is expected to take effect on that restart, but the deployment artifact does not falsely claim somebody visually observed the desktop.

When a separate runtime-proof request exists, run the bounded proof from the actual AutoLogon desktop:

```powershell
scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd targets\local\autologon-runtime.json
```

Required runtime classification:

```text
TECHNICIAN_OBSERVED_LIVE_RUNTIME
```

Runtime proof is a higher evidence ceiling and is not required to call software deployment complete.

## Generic single-package controller — advanced/reference use

The underlying compatibility controller remains:

```text
bash/apps/sas-install-apps.sh
```

Use it only for a specifically approved package-level workflow not already covered by the higher-level technician command. A single package must be enabled in `configs/software-packages/approved-apps.json`.

Example BCA dry run:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy \
  --dry-run
```

Example BCA live run after the approved admission gate:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy
```

Do **not** use the generic controller to reconstruct the historical six-package `cybernet-clinical-workstation` live path for AutoLogon. Current field AutoLogon is the S4U restart-complete lane above.

## Roles and boundaries

| Location | Operator action | What happens there |
| --- | --- | --- |
| Windows admin workstation or approved admin VM | Run `sas cybernet Deploy HOST` | Full ordered software deployment, AutoLogon last, restart, evidence collection |
| Windows admin workstation or approved admin VM | Run `sas autologon Remote HOST` | AutoLogon-only S4U deployment plus restart |
| Approved software share | Read-only source | Supplies exact catalog-pinned payloads |
| Target Cybernet workstation | No manual command required during deployment | Receives staged payloads, executes approved tasks, restarts after AutoLogon |
| Technician target session | Optional runtime proof when separately requested | Directly observes automatic sign-in/application behavior |

The deployment lanes do not embed passwords, enable WinRM, weaken firewall policy, or use the blocked canonical SYSTEM AutoLogon install path.

## Troubleshooting

### Clinical-core stage fails

Preserve `cybernet_clinical_core_deployment_summary.json` and the controller CSV. Do not blindly rerun the target.

### AutoLogon S4U stage fails

Preserve the S4U result and the wrapper result. Do not require a target-side login and do not switch back to the blocked SYSTEM AutoLogon path.

### Restart task cannot be created or started

Deployment is not complete. Preserve `autologon_s4u_deployment_result.json`; fix the exact remote Task Scheduler authorization/failure and retry only after reviewing the target state.

### Target leaves but does not return within the restart window

The result is `ACTION_REQUIRED`. Treat it as restart recovery uncertainty, not as permission to reinstall software blindly.

### Cleanup cannot be proven

Do not classify deployment complete. Only the unique run-scoped task/staging artifacts named in the evidence may be repaired; never perform broad destructive cleanup.

## Operator closeout checklist

- [ ] Exact authorized target used.
- [ ] Five clinical applications completed before AutoLogon in the full profile.
- [ ] AutoLogon was the final software step.
- [ ] Required pre-reboot AutoLogon state passed.
- [ ] Target restart was initiated automatically by the deployment command.
- [ ] Target left and returned on the proven SMB service.
- [ ] Restart task cleanup was verified.
- [ ] Final deployment result reports completion.
- [ ] Failed targets were reviewed individually before retry.
- [ ] No credentials, live hostnames, raw logs, or machine-local evidence were committed.

## Related references

- Start-here operator page: [`../../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md`](../../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md)
- Technical transport reference: [`../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md)
- AutoLogon S4U reference: [`../AUTOLOGON_KERBEROS_S4U_PILOT.md`](../AUTOLOGON_KERBEROS_S4U_PILOT.md)
- Deployment teardown rules: [`../DEPLOYMENT_TEARDOWN_DOCTRINE.md`](../DEPLOYMENT_TEARDOWN_DOCTRINE.md)
- Package qualification boundary: [`../PACKAGE_VM_QUALIFICATION_PROFILES.md`](../PACKAGE_VM_QUALIFICATION_PROFILES.md)
