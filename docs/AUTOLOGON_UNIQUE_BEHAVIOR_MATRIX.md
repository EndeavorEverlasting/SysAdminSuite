# AutoLogon Unique-Behavior Reconciliation Matrix

## Purpose

This document reconciles the unique behavior from PRs #167, #168, and #175 to establish the canonical AutoLogon sequence. AutoLogon is the **final product-configuration mutation** that must occur only after package validation, application acceptance, and completion of package reboots.

## PR Contribution Summary

### PR #167: AutoLogon State Delta

**Unique behaviors:**
- Before/After workstation state-delta workflow
- Stateful technician launcher (double-click `Run-AutoLogonStateDelta.cmd`)
- AutoLogon registry posture capture (never reads DefaultPassword)
- State transitions: `CONFIRMED_STATE_TRANSITION`, `ALREADY_CONFIGURED_BEFORE`, `NO_MATERIAL_CHANGE`, `PARTIAL_CHANGE_REVIEW`, `REGRESSION_REVIEW`, `INCONCLUSIVE`
- Operator state persistence in `survey/output/autologon_state_delta/operator-state.json`
- Maximum 25 explicit approved targets per run

**Proof contributions:**
- P4: PowerShell parser checks
- P6: Fixture Before/After delta pair
- P9: Technician-observed state transition

### PR #168: AutoLogon Deployment Workflow

**Unique behaviors:**
- AutoLogon deployment lane with administrative ACL/profile posture
- Current-token local/share access proof
- Technician runtime proof pack (9 proof stages)
- Canonical package: `\\nt2kwb972sms01\packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe`
- Config-driven technician runner (no PowerShell composition required)
- Process readiness modes: `ProcessAlive`, `RespondingWindow`, `WindowTitle`
- Disposable/non-persistent test acknowledgement required

**Proof contributions:**
- P6: Fixture deployment and staging cleanup
- P7: Technician launcher and command ACK
- P8: Installer exit code and process observation
- P9: `TECHNICIAN_OBSERVED_LIVE_RUNTIME` artifacts

### PR #175: Approved Software Catalog + Acceptance Extraction

**Unique behaviors:**
- Folder-first approved software catalog (`configs/software-packages/approved-apps.json`)
- Per-package acceptance profiles
- Application launch and AutoLogon behavior extraction
- Classifier order (fail-closed): `not_enabled` → `configured_user_mismatch` → `configured_password_missing` → `autologon_ready`
- Corrects password-missing readiness defect
- Bounded application evidence (max 12 explicit process base names)

**Proof contributions:**
- P4: Approved catalog and acceptance profile contracts
- P6: Fixture Before/WhatIf/After/acceptance extraction
- P9: `MACHINE_EVIDENCE_READY_FOR_TECHNICIAN_REVIEW`

## Canonical Sequence

AutoLogon is the **final mutation** in the deployment lifecycle. The canonical sequence is:

```
1. ASSESSMENT (read-only)
   survey/sas-assess-autologon.sh --manifest targets.csv
   -> autologon_assessment.csv
   -> identifies: not_enabled, setup_incomplete, autologon_ready

2. HOST ELIGIBILITY (read-only gate)
   scripts/Test-SasHostEligibility.ps1 -Target HOSTNAME
   -> eligible / not_eligible
   -> BLOCKED if not eligible

3. BEFORE SNAPSHOT (read-only)
   scripts/Start-SasAutoLogonStateDelta.ps1 -Action Before -ComputerName HOSTNAME
   -> run_manifest_before.json

4. FINAL-STEP GATE (read-only validator)
   scripts/Invoke-SasAutoLogonFinalStepGate.ps1 -Target HOSTNAME -RunId RUNID
   -> autologon_final_step_gate.json
   -> overall_pass must be true

5. PACKAGE VALIDATION (read-only)
   scripts/Invoke-SasApprovedSoftwareAcceptance.ps1 -Action Before
   -> application acceptance profile validated

6. APPLICATION INSTALL (mutation)
   scripts/Invoke-SasSoftwareInstall.ps1 -ComputerName HOSTNAME -InstallerRelativePath ...
   -> install execution
   -> staging cleanup

7. REBOOT (if required)
   -> technician observes reboot completion
   -> technician confirms application launch

8. AFTER SNAPSHOT (read-only)
   scripts/Start-SasAutoLogonStateDelta.ps1 -Action After -ComputerName HOSTNAME
   -> run_manifest_after.json

9. STATE DELTA COMPARISON (read-only)
   scripts/Invoke-SasAutoLogonStateDelta.ps1 -Mode Assess
   -> delta decision: CONFIRMED_STATE_TRANSITION, etc.

10. AUTOLOGON MUTATION (final mutation - BLOCKED until steps 1-9 pass)
    scripts/Invoke-SasSoftwareInstall.ps1 -ComputerName HOSTNAME -InstallerRelativePath NW_AutoLogon_Setup_x64.exe
    -> AutoLogon configuration applied

11. POST-REBOOT VERIFICATION (read-only)
    -> technician observes AutoLogon sign-in
    -> technician runs current-token access proof
    -> technician records observed behavior
```

**Key invariant:** AutoLogon mutation (step 10) is BLOCKED until:
- Package validation (step 5) passes
- Application acceptance (step 5) is confirmed
- Required reboots (step 7) are completed
- After snapshot (step 8) is captured
- State delta (step 9) shows successful transition

## Refusal Classifications

| Refusal | Classification | Recovery |
|---------|---------------|----------|
| `run_id_format` invalid | **BLOCKED** — operator error | Generate valid run ID |
| `host_eligibility` failed | **BLOCKED** — safety gate | Add host to policy or choose eligible target |
| `approved_catalog` missing | **BLOCKED** — package not approved | Add package to catalog or pin installer |
| `before_snapshot` missing | **BLOCKED** — evidence missing | Capture Before snapshot first |
| `application_acceptance` not confirmed | **BLOCKED** — prerequisite incomplete | Complete application acceptance extraction |
| `required_reboot` pending | **BLOCKED** — reboot required | Complete required reboot and verify |
| `runtime_proof` missing | **WARN** — not blocking | Capture runtime proof (recommended) |
| `file_access_posture` not verified | **WARN** — not blocking | Verify file access posture (recommended) |

## Post-Reboot Proof Contract

After AutoLogon mutation, the following proof is required:

1. **Observed sign-in:** Technician directly observes AutoLogon sign-in after reboot
2. **Current-token access:** Technician runs `Invoke-SasAutoLogonSessionAccessProof.ps1` inside the AutoLogon desktop session
3. **Application launch:** Technician confirms required applications launched successfully
4. **Behavior recorded:** Technician records concrete observed behavior in `runtime-proof-summary.json`
5. **No staging remains:** Technician confirms no SysAdminSuite staging on target

**Proof level:** P12 (Cybernet AutoLogon post-reboot proof)

## Physical Cybernet Readiness Checklist

Before executing on a physical Cybernet:

- [ ] Console access confirmed
- [ ] Recovery capability confirmed (USB, network restore, or backup)
- [ ] Approved pilot workstations identified (minimum 2)
- [ ] Technician label assigned
- [ ] Before snapshot captured on each pilot
- [ ] Application acceptance confirmed on each pilot
- [ ] Required reboots completed on each pilot
- [ ] AutoLogon mutation authorized by operator
- [ ] Post-reboot verification plan documented
- [ ] Rollback plan documented

## Integration Points

| Component | PR | Integration |
|-----------|----|-------------|
| State-delta workflow | #167 | Steps 3, 8, 9 |
| Deployment lane | #168 | Steps 6, 10 |
| Acceptance extraction | #175 | Steps 5, 7 |
| Final-step gate | #191 | Step 4 |
| Host eligibility | #188 | Step 2 |

## Safety Invariants

1. **AutoLogon is the final mutation** — no other mutations after AutoLogon
2. **Fail-closed** — no `-Force`, environment variable, or undocumented override
3. **Never reads DefaultPassword** — only checks catalog and snapshot existence
4. **Never contacts the target** — only validates local evidence and configuration
5. **Explicit authorization required** — operator must explicitly authorize AutoLogon mutation
6. **Post-reboot proof required** — technician must observe and record AutoLogon behavior