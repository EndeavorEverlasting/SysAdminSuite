# Start Here — Cybernet Software Deployment

Use this page when an authorized technician or administrator asks SysAdminSuite how to deploy the clinical software stack or finish AutoLogon on a Cybernet workstation.

## Technician quick answer

From an approved Windows administrator workstation with the current SysAdminSuite operator command installed:

```powershell
sas
```

For one explicitly authorized Cybernet, the current software sequence is:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
sas autologon Remote <AUTHORIZED-CYBERNET>
```

These are **deployment commands**, not status-only commands.

- `sas cybernet Deploy HOST` deploys the five approved `cybernet-clinical-core` applications. Its internal dry run is an admission gate and the same invocation continues into live deployment when the gate passes.
- `sas autologon Remote HOST` is the current live AutoLogon apply lane. It stages and executes the approved AutoLogon package through Kerberos SMB and a passwordless S4U scheduled task. A target-side interactive login is not required before the apply.

AutoLogon remains separate and last. Do not route the field deployment through the historical six-package LocalSystem `cybernet-clinical-workstation` set while canonical SYSTEM AutoLogon remains blocked by its failed runtime qualification.

## Required deployment states

### 1. Clinical core

Run:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

The command validates the exact five-package set, runs the current Northwell network gate, performs the package-set dry run, and then continues directly into the live controller. It does not reboot the workstation.

Required terminal state:

```text
CLINICAL_CORE_DEPLOYMENT_COMPLETED
```

Canonical summary:

```text
survey\output\runs\cybernet-clinical-core\cybernet-clinical-core-*\cybernet_clinical_core_deployment_summary.json
```

The summary must identify `package_set_id=cybernet-clinical-core`, five package IDs, and `autologon_included=false`. Preserve the controller result CSV. On any nonzero result, preserve the emitted evidence and **do not blindly rerun the target**.

If the five clinical-core applications are already proven installed and accepted on the workstation, preserve that state and skip this reinstall. Proceed to AutoLogon when it is the remaining requested state.

### 2. Apply AutoLogon

Run:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

Required positive classification:

```text
KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING
```

Canonical deployment artifact:

```text
survey\output\runs\autologon-kerberos-s4u\autologon-kerberos-s4u-*\autologon_kerberos_s4u_pilot_result.json
```

This classification means the real AutoLogon package was executed on the authorized target through the S4U lane, the required pre-reboot Winlogon state passed, and cleanup passed.

**It does not mean reboot or automatic sign-in has been proven.**

A fixture result, transport `LIVE CERT PASS`, process exit code `0`/`3010`, process start, or registry expectation without the positive S4U artifact is not AutoLogon deployment completion.

### 3. Reboot and sign-in proof is the next state, not optional cleanup

After `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING`, the deployment/runtime work item is **not finished** when runtime proof was requested.

The next state transition is:

1. obtain the separately required authorization for an attended reboot;
2. reboot the same workstation through the approved site process;
3. directly observe that the workstation automatically signs in to the expected workstation account;
4. from that actual AutoLogon desktop session, run the bounded runtime proof.

Do **not** claim reboot/sign-in based on the pre-reboot S4U artifact. Do **not** fall back to fixture, transport, or live-search testing after the positive S4U state.

### 4. Runtime proof from the actual AutoLogon desktop

From the actual automatically signed-in workstation session:

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

Only this actual-session evidence proves the runtime behavior ceiling. Pre-reboot deployment and runtime proof are separate artifacts and neither substitutes for the other.

## Hardware-only Cybernet work

The portable operator command keeps hardware configuration separate:

```powershell
sas cybernet Plan <AUTHORIZED-CYBERNET>
sas cybernet Apply <AUTHORIZED-CYBERNET>
sas cybernet Validate <AUTHORIZED-CYBERNET>
```

Those commands own hardware preferences such as power/no-sleep/display/COM behavior. They are **not** the current clinical software deployment or AutoLogon commands.

## Technical references

- Clinical-core deployment implementation: `scripts/Invoke-SasCybernetClinicalCoreDeployment.ps1`
- Clinical-core launcher: `Deploy-CybernetClinicalCore.cmd`
- AutoLogon S4U implementation: `scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1`
- AutoLogon runtime implementation: `scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1`
- Approved package-set catalog: `configs/software-packages/windows-native-package-sets.json`
- Approved package catalog: `configs/software-packages/approved-apps.json`
- Detailed software deployment reference: `docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md`
- AutoLogon S4U reference: `docs/AUTOLOGON_KERBEROS_S4U_PILOT.md`

## Proof boundary

Repository docs, fixtures, and CI prove routing and contract shape only. A real target deployment requires the authorized administrator workstation and protected network context. AutoLogon runtime proof additionally requires the separately authorized reboot and direct observation of automatic sign-in on the real target.
