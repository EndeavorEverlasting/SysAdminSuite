# Cybernet software deployment tutorial

## Audience and current operator workflow

This tutorial is for authorized technicians and Windows administrators deploying the approved Cybernet clinical software stack and AutoLogon, or diagnosing the exact transport dependencies before deployment.

The primary field surface is:

```powershell
sas
```

For one explicitly authorized Cybernet, a complete software deployment is:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

The target argument may be the authorized short hostname or FQDN. The deployment-readiness layer completes a short hostname with the current domain DNS suffix and fails closed when that cannot be done safely.

That command owns the complete ordered transaction:

1. one-target low-noise Kerberos SMB plus Task Scheduler readiness;
2. five approved clinical applications;
3. AutoLogon **last**;
4. automatic target restart;
5. bounded observation that the target left and returned on the proven SMB service.

Required terminal status:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

The historical six-package LocalSystem `cybernet-clinical-workstation` controller remains unsuitable because canonical SYSTEM AutoLogon is still blocked by failed runtime qualification. The current orchestrator composes the proven five-package clinical-core engine with the Kerberos/S4U AutoLogon engine and restart-complete wrapper.

## Optional one-target readiness diagnosis

A separate readiness command exists when the requested goal is diagnosis rather than immediate authorized deployment:

```powershell
sas cybernet Probe <AUTHORIZED-CYBERNET>
```

Equivalent alias:

```powershell
sas network <AUTHORIZED-CYBERNET>
```

This probe is read-only with respect to the target. It performs only:

1. the local approved Northwell network posture check;
2. completion of a short hostname with the current domain DNS suffix when needed;
3. one authorized FQDN DNS resolution;
4. one CIFS Kerberos service-ticket request;
5. TCP 445;
6. `ADMIN$` read authorization;
7. TCP 135 only after `ADMIN$` is authorized;
8. Schedule service state;
9. one reserved nonexistent task query without enumerating the task library.

It stops after the first failed dependency. It never broadens to WinRM, `auto` discovery, Naabu, Nmap, a subnet scan, a package copy, task creation, software installation, target mutation, or restart.

Required live readiness status:

```text
CYBERNET_DEPLOYMENT_READINESS_READY
```

Required transport classification:

```text
kerberos_smb_task_ready
```

Canonical readiness artifact:

```text
survey\output\runs\cybernet-deployment-readiness\cybernet-deployment-readiness-*\artifacts\cybernet_deployment_readiness_result.json
```

Readiness is admission evidence, not deployment completion. A separate Probe is **not required** before `sas cybernet Deploy`; deployment runs a fresh copy of the same readiness gate inside its own transaction and continues only when it passes.

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

1. creates the full deployment result before target contact so failures remain discoverable;
2. runs the current Northwell network posture gate;
3. resolves the one authorized target to an FQDN;
4. runs the staged `kerberos_smb_task` readiness chain;
5. stops before mutation unless readiness is `CYBERNET_DEPLOYMENT_READINESS_READY`;
6. dry-runs the five-package clinical core as an internal admission gate;
7. continues into live clinical-core deployment in the same invocation;
8. applies AutoLogon last through Kerberos SMB/S4U;
9. requires clean pre-reboot AutoLogon state and S4U cleanup;
10. creates one bounded SYSTEM restart task;
11. starts the restart;
12. waits for TCP 445 to leave and return;
13. verifies the one-time restart task is absent or removes it;
14. writes the final deployment artifact.

The technician is not required to run a separate fixture, transport live-cert, or runtime-proof loop before deployment can complete. The optional Probe is diagnostic only and is not another required deployment step.

## Canonical artifacts

Full software deployment:

```text
survey\output\runs\cybernet-software-deployment\cybernet-software-deployment-*\cybernet_software_deployment_result.json
```

Required values:

```text
status=CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
low_noise_transport_preflight_required=true
readiness_status=CYBERNET_DEPLOYMENT_READINESS_READY
readiness_transport_classification=kerberos_smb_task_ready
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

When an authorized technician asks to deploy software, test AutoLogon on the target, or live-cert the path with deployment authority, a green fixture or readiness result is only admission. It must not replace the actual deployment step.

The full and AutoLogon-only commands perform real target mutation. If an internal dry run or readiness gate fails, the command stops before mutation and records the exact gate. If the gates pass, the same invocation continues.

Do not tell the technician that a process exit code, fixture result, readiness result, or transport-only certificate is deployment completion.

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

`--allow-legacy` is the retained **compatibility-controller gate** for this advanced package-level path. It does not grant deployment authorization, credentials, a transport decision, or permission to bypass the higher-level Cybernet deployment orchestration.

Use the compatibility controller only for a specifically approved package-level workflow not already covered by the higher-level technician command. A single package must be enabled in `configs/software-packages/approved-apps.json`.

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

Do **not** use the generic controller to reconstruct the historical six-package live path for AutoLogon. Current field AutoLogon is the S4U restart-complete lane above.

## Roles and boundaries

| Location | Operator action | What happens there |
| --- | --- | --- |
| Windows admin workstation | Run `sas cybernet Probe HOST` | Read-only staged deployment readiness; no target mutation |
| Windows admin workstation or approved admin VM | Run `sas cybernet Deploy HOST` | Integrated readiness, full ordered software deployment, AutoLogon last, restart, evidence collection |
| Windows admin workstation or approved admin VM | Run `sas autologon Remote HOST` | AutoLogon-only S4U deployment plus restart |
| Approved software share | Read-only source | Supplies exact catalog-pinned payloads |
| Target Cybernet workstation | No manual command required during deployment | Receives staged payloads, executes approved tasks, restarts after AutoLogon |
| Technician target session | Optional runtime proof when separately requested | Directly observes automatic sign-in/application behavior |

The deployment lanes use the current Windows admin token and do not embed passwords, enable WinRM, weaken firewall policy, or use the blocked canonical SYSTEM AutoLogon install path.

## Troubleshooting

### Readiness is `ACTION_REQUIRED`

Preserve `cybernet_deployment_readiness_result.json` and the nested transport result. Review the exact failed stage and tested port subset. Do not widen to WinRM, `auto`, Naabu, Nmap, a subnet scan, or an immediate identical retry.

### Clinical-core stage fails

Preserve `cybernet_clinical_core_deployment_summary.json` and the controller CSV. Do not blindly rerun the target.

### AutoLogon S4U stage fails

Preserve the S4U result and the wrapper result. Do not require a target-side login and do not switch back to the blocked SYSTEM AutoLogon path.

### Restart task cannot be created or started

Deployment is not complete. Preserve `autologon_s4u_deployment_result.json`; fix the exact Remote Task Scheduler authorization/failure and retry only after reviewing the target state.

### Target leaves but does not return within the restart window

The result is `ACTION_REQUIRED`. Treat it as restart recovery uncertainty, not as permission to reinstall software blindly.

### Terminal closes or output disappears

Run:

```powershell
sas evidence
```

Do not repeat the readiness probe or deployment just to recreate console output.

### Cleanup cannot be proven

Do not classify deployment complete. Only the unique run-scoped task/staging artifacts named in the evidence may be repaired; never perform broad destructive cleanup.

## Operator closeout checklist

- [ ] Exact authorized target used.
- [ ] Integrated readiness passed as `CYBERNET_DEPLOYMENT_READINESS_READY`.
- [ ] Readiness selected `kerberos_smb_task` and did not probe WinRM.
- [ ] Five clinical applications completed before AutoLogon in the full profile.
- [ ] AutoLogon was the final software step.
- [ ] Required pre-reboot AutoLogon state passed.
- [ ] Target restart was initiated automatically by the deployment command.
- [ ] Target left and returned on the proven SMB service.
- [ ] Restart task cleanup was verified.
- [ ] Final deployment result reports completion.
- [ ] Failed readiness/deployment targets were reviewed individually before retry.
- [ ] No credentials, live hostnames, raw logs, or machine-local evidence were committed.

## Related references

- Start-here operator page: [`../../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md`](../../START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md)
- Low-noise deployment contract: [`../SOFTWARE_DEPLOYMENT_LOW_NOISE.md`](../SOFTWARE_DEPLOYMENT_LOW_NOISE.md)
- Technical transport reference: [`../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](../SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md)
- AutoLogon S4U reference: [`../AUTOLOGON_KERBEROS_S4U_PILOT.md`](../AUTOLOGON_KERBEROS_S4U_PILOT.md)
- Deployment teardown rules: [`../DEPLOYMENT_TEARDOWN_DOCTRINE.md`](../DEPLOYMENT_TEARDOWN_DOCTRINE.md)
- Package qualification boundary: [`../PACKAGE_VM_QUALIFICATION_PROFILES.md`](../PACKAGE_VM_QUALIFICATION_PROFILES.md)
