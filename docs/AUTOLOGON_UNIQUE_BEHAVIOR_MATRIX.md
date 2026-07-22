# AutoLogon unique-behavior reconciliation matrix

## Purpose

This document preserves the distinct contributions that were converged into the current AutoLogon workflow. It is an architecture ledger, not an operator runbook. Use `AUTOLOGON_DEPLOYMENT_WORKFLOW.md` for commands and launch order.

## Current reconciliation

| Contribution | Preserved behavior | Current authority | Proof boundary |
|---|---|---|---|
| State delta | Before/After capture; baseline failure reduction; already-configured reduction; expected-account and password-value-name presence; no password-value read | `Invoke-SasAutoLogonStateDelta.ps1`, normalized by `Invoke-SasAutoLogonDeployment.ps1` | State transition only; no reboot, sign-in, current-token access, application behavior, or actor identity |
| Final-step gate | Run ID, host eligibility, approved catalog, and Before snapshot are mandatory; no bypass | `Invoke-SasAutoLogonFinalStepGate.ps1`, owned in live order by `Invoke-SasAutoLogonDeployment.ps1` | Local prerequisite result only; no installer or runtime proof |
| Approved catalog | One enabled AutoLogon identity, pinned installer filename, `CopyThenInstall`, vendor-validated arguments required | `configs/software-packages/approved-apps.json` | Package identity and policy only; no source, install, or behavior proof |
| Canonical transport | Closed request, fresh P02 decision, Kerberos/SMB scheduled-task front door, result retrieval, run-scoped teardown | `Invoke-SasValidatedSoftwareDeployment.ps1` through `Invoke-SasAutoLogonDeployment.ps1` | Deployment execution and cleanup only |
| Current-token access | Expected-account match before bounded local/mapped/UNC path access; optional unique create/remove marker | `Invoke-SasAutoLogonSessionAccessProof.ps1` | Signed-in token access only; no deployment history or application behavior |
| Technician runtime | Safe start, process ACK, bounded ready wait, disposable trigger, concrete observed behavior | `Invoke-SasAutoLogonTechnicianRuntimeProof.ps1` through its `.cmd` launcher | Observed signed-in application behavior; fixture output never becomes live proof |
| Proof receipt | Source digest, size, classification, proof level, reason codes, confirmation, and privacy status only | Frozen schemas; fixture receipt emitted by dedicated AutoLogon E2E | Continuity record only; reviewers must verify against retained operator-local source |

## Canonical order

1. Complete prerequisite package/application configuration and any earlier required reboot.
2. Run the dedicated AutoLogon fixture profile.
3. Run one fresh authorized Kerberos/SMB preflight.
4. Review one closed `-WhatIf` request.
5. Run one-target canonical deployment; the application captures Before, enforces the final-step gate, deploys, cleans, and captures After.
6. Inspect the public-safe deployment result; runtime must still be pending.
7. Perform the separately approved attended reboot and directly observe automatic sign-in.
8. Run current-token access proof from the actual AutoLogon session.
9. Run the approved disposable application behavior proof and record the exact proof level.
10. Expand only with product-owner and change approval.

AutoLogon remains the final security-sensitive product mutation. No later stage may rewrite a plan, fixture, installer exit, state delta, process ACK, or session match as a higher proof claim.

## Refusal and recovery mapping

| Condition | Disposition |
|---|---|
| Request, package digest, arguments, or authorization incomplete | Block before target work |
| Preflight is not `kerberos_smb_task_ready` | Block; do not fall back to WinRM |
| Baseline failed | Skip target; preserve evidence |
| Already configured | Skip reinstall; review existing posture |
| Final-step gate failed | Block; correct the named prerequisite |
| Deployment or result retrieval failed | Stop expansion; preserve evidence; do not blindly retry |
| Cleanup or zero-remnant proof failed | Cleanup review required; remove only identified run-scoped SysAdminSuite artifacts |
| State result requires review | Stop before reboot/expansion and reconcile state |
| Reboot or automatic sign-in not observed | Runtime incomplete |
| Current-token access failed | Runtime failed or incomplete; do not substitute admin/remoting access |
| Application behavior failed or was not observed | Runtime failed or incomplete; a process ACK is insufficient |
| Approved rollback procedure absent | Live pilot blocked |

## Safety invariants

1. No password value is read, rendered, or committed.
2. No direct legacy WinRM AutoLogon command is authorized.
3. No silent fallback, gate bypass, unattended reboot example, or automated rollback is provided.
4. Operator-local hostnames, accounts, package paths, and raw evidence remain ignored.
5. Fixture and public-safe receipt data contain no target identity or raw corporate evidence.
6. Normal Windows, endpoint, installer, and audit evidence is preserved.
