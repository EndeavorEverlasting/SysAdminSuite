# Start Here — Cybernet Software Deployment

Use this page when an authorized technician or administrator asks SysAdminSuite how to deploy the clinical software stack or how to run the smallest useful deployment-readiness probe on a Cybernet workstation.

## Technician quick answer

From an approved Windows administrator workstation with the current SysAdminSuite operator command installed:

```powershell
sas
```

For a full Cybernet software deployment on one explicitly authorized target:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET-HOST-OR-FQDN>
```

That is the complete current field transaction. It automatically:

1. runs the one-target low-noise Kerberos SMB plus Task Scheduler readiness chain;
2. deploys the five approved clinical applications;
3. deploys AutoLogon **last** through Kerberos SMB/S4U;
4. automatically restarts the same target;
5. waits for the target to leave and return on the already-proven SMB service;
6. emits a final deployment artifact.

A separate probe is **not required** before deployment. The deployment command owns the same gate and stops before mutation when readiness is not proven.

Required success status:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

Canonical summary:

```text
survey\output\runs\cybernet-software-deployment\cybernet-software-deployment-*\cybernet_software_deployment_result.json
```

The summary must report:

- `low_noise_transport_preflight_required=true`;
- `readiness_status=CYBERNET_DEPLOYMENT_READINESS_READY`;
- `readiness_transport_classification=kerberos_smb_task_ready`;
- `autologon_was_last_software_step=true`;
- `automatic_reboot_performed=true`;
- `restart_offline_observed=true`;
- `restart_online_observed=true`.

## Low-noise iterative readiness probe

Use the standalone probe only when the requested goal is diagnosis/readiness rather than immediate authorized deployment:

```powershell
sas cybernet Probe <AUTHORIZED-CYBERNET-HOST-OR-FQDN>
```

Equivalent short alias:

```powershell
sas network <AUTHORIZED-CYBERNET-HOST-OR-FQDN>
```

The probe is read-only with respect to the target. It runs this dependency chain and suppresses every later step after an earlier failure:

1. local approved Northwell network posture;
2. one authorized target DNS resolution;
3. one CIFS Kerberos service-ticket request;
4. TCP 445;
5. `ADMIN$` read authorization;
6. TCP 135 only after `ADMIN$` is authorized;
7. Schedule service state;
8. one reserved nonexistent task query without enumerating the task library.

It does **not** probe WinRM, use `auto` transport discovery, run Naabu/Nmap, enumerate the subnet, create a task, copy a package, install software, restart the target, or mutate target state.

Required live readiness status:

```text
CYBERNET_DEPLOYMENT_READINESS_READY
```

Canonical readiness summary:

```text
survey\output\runs\cybernet-deployment-readiness\cybernet-deployment-readiness-*\artifacts\cybernet_deployment_readiness_result.json
```

A failed readiness run is an actionable gate. Review its exact classification and tested port subset; do not broaden ports or repeat the same probe blindly.

## AutoLogon-only deployment

When the five clinical applications are already proven installed and accepted, preserve them. Do **not** reinstall them just to reach AutoLogon.

Run:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

This command:

1. applies the real AutoLogon package through the approved Kerberos/S4U lane;
2. requires the clean pre-reboot AutoLogon state;
3. automatically restarts the same target;
4. waits for the restart cycle to complete.

Required success classification:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

Canonical summary:

```text
survey\output\runs\autologon-s4u-deployment\autologon-s4u-deployment-*\autologon_s4u_deployment_result.json
```

AutoLogon installation is **not deployment-complete before the restart**. The intermediate S4U classification `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` is an internal apply gate, not a technician stopping point.

## Tests and live certs do not replace deployment

When the technician asks to deploy, test AutoLogon on an authorized target, or live-cert the deployment path with mutation authority, SysAdminSuite must run the real deployment lane rather than stop at a fixture, transport-only certificate, dry run, process exit code, or registry expectation.

The integrated low-noise readiness probe is an admission gate inside deployment. It is not a replacement for deployment and must not become a repeated manual loop when mutation is already authorized.

## Runtime proof is optional after deployment

The restart-complete deployment artifact proves that AutoLogon was applied last and the target completed the required restart cycle. It does **not** claim that somebody visually observed the automatic sign-in desktop.

When a separate runtime-proof request exists, direct observation and the bounded runtime proof remain available from the actual AutoLogon desktop:

```powershell
scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd targets\local\autologon-runtime.json
```

Required runtime classification:

```text
TECHNICIAN_OBSERVED_LIVE_RUNTIME
```

Runtime proof is a higher proof ceiling. It is **not a prerequisite for software deployment completion** and must not delay deployment.

## Terminal closed or crashed — recover evidence before retrying

A closed PowerShell window is not a reason to redeploy or repeat a readiness probe.

Run this **offline** first:

```powershell
sas evidence
```

It searches the current checkout plus bounded SysAdminSuite checkouts under the current Windows user's Desktop/OneDrive layouts and prints the newest deployment/runtime artifact plus the next safe action. It performs **no network activity and no target contact**.

Useful variants:

```powershell
sas evidence All
sas evidence AutoLogon
sas evidence Cybernet
sas evidence Runtime
sas evidence Open
```

The stable machine-local recovery index is:

```text
%LOCALAPPDATA%\SysAdminSuite\last-evidence.json
```

When the installed `sas` command is stale or unavailable but the repo is open, use:

```powershell
.\Find-SasEvidence.cmd
```

Full recovery guidance and artifact locations: [Operator Evidence Recovery](docs/OPERATOR_EVIDENCE_RECOVERY.md).

## Hardware-only Cybernet work

The portable operator command keeps hardware configuration separate:

```powershell
sas cybernet Plan <AUTHORIZED-CYBERNET>
sas cybernet Apply <AUTHORIZED-CYBERNET>
sas cybernet Validate <AUTHORIZED-CYBERNET>
```

Those commands own hardware preferences such as power/no-sleep/display/COM behavior. They are not the current software deployment commands.

## Technical references

- Readiness launcher: `Probe-CybernetSoftware.cmd`
- Readiness orchestrator: `scripts/Invoke-SasCybernetDeploymentReadiness.ps1`
- Narrow transport preflight: `scripts/Test-SasSoftwareDeploymentTransport.ps1`
- Full software orchestrator: `scripts/Invoke-SasCybernetSoftwareDeployment.ps1`
- Full software launcher: `Deploy-CybernetSoftware.cmd`
- Five-package clinical-core engine: `scripts/Invoke-SasCybernetClinicalCoreDeployment.ps1`
- AutoLogon S4U apply engine: `scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1`
- AutoLogon restart-complete deployment wrapper: `scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1`
- AutoLogon runtime proof: `scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`
- Crash-safe evidence recovery: `scripts/Show-SasOperatorEvidence.ps1`
- Approved package-set catalog: `configs/software-packages/windows-native-package-sets.json`
- Detailed software deployment tutorial: `docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md`

## Failure boundary

On any nonzero result, preserve the emitted summary and controller evidence and do not blindly rerun a changed target. If the terminal disappeared, use `sas evidence` before deciding whether anything should be rerun. Repository docs and CI prove routing/contract shape only; real target deployment still requires the authorized administrator workstation and protected network context.
