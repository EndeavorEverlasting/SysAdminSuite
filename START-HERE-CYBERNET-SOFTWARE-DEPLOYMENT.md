# Start Here — Cybernet Software Deployment

Use this page when an authorized technician or administrator asks SysAdminSuite how to deploy the clinical software stack or AutoLogon on a Cybernet workstation.

## Technician quick answer

From an approved Windows administrator workstation with the current SysAdminSuite operator command installed:

```powershell
sas
```

For a full Cybernet software deployment on one explicitly authorized target:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

That command is the complete current field transaction:

1. deploy the five approved clinical applications;
2. deploy AutoLogon **last** through Kerberos SMB/S4U;
3. automatically restart the same target;
4. wait for the target to leave and return on the already-proven SMB service;
5. emit a final deployment artifact.

Required success status:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

Canonical summary:

```text
survey\output\runs\cybernet-software-deployment\cybernet-software-deployment-*\cybernet_software_deployment_result.json
```

The summary must report `autologon_was_last_software_step=true`, `automatic_reboot_performed=true`, `restart_offline_observed=true`, and `restart_online_observed=true`.

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

A dry run may be an internal admission gate, but the same authorized deployment command continues into target mutation. The technician should not be sent through repeated fixture/live-cert loops before the software is deployed.

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

## Hardware-only Cybernet work

The portable operator command keeps hardware configuration separate:

```powershell
sas cybernet Plan <AUTHORIZED-CYBERNET>
sas cybernet Apply <AUTHORIZED-CYBERNET>
sas cybernet Validate <AUTHORIZED-CYBERNET>
```

Those commands own hardware preferences such as power/no-sleep/display/COM behavior. They are not the current software deployment commands.

For the complete hardware/client workflow and safe retry guidance:

- [Complete Cybernet client configuration guide](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md)
- [Cybernet client configuration troubleshooting](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md)

## Technical references

- Full software orchestrator: `scripts/Invoke-SasCybernetSoftwareDeployment.ps1`
- Full software launcher: `Deploy-CybernetSoftware.cmd`
- Five-package clinical-core engine: `scripts/Invoke-SasCybernetClinicalCoreDeployment.ps1`
- AutoLogon S4U apply engine: `scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1`
- AutoLogon restart-complete deployment wrapper: `scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1`
- AutoLogon runtime proof: `scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`
- Approved package-set catalog: `configs/software-packages/windows-native-package-sets.json`
- Approved package catalog: `configs/software-packages/approved-apps.json`
- Detailed software deployment tutorial: `docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md`

## Failure boundary

On any nonzero result, preserve the emitted summary and controller evidence and do not blindly rerun a changed target. Repository docs and CI prove routing/contract shape only; real target deployment still requires the authorized administrator workstation and protected network context.
