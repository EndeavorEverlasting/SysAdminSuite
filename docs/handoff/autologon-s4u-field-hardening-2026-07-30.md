# AutoLogon S4U field hardening — 2026-07-30

## Purpose

Preserve the field-proven findings from the July 30 Cybernet AutoLogon deployment work so a new terminal, workstation, or agent does not rediscover the same launcher, path, Kerberos, and evidence-root failures.

This handoff intentionally contains no live username, password, AutoLogon secret, or authorized target identifier.

## Proven wins now represented in the repository

1. **Kerberos target readiness now produces every ticket the S4U consumer requires.**
   - `SasSoftwareDeploymentLowNoise.psm1` requests both `CIFS/<target>` and `HOST/<target>` for `kerberos_smb_task` readiness.
   - SMB/admin/Task Scheduler probing does not continue until both tickets are issued.
   - `test_autologon_kerberos_s4u_contracts.py` locks the producer/consumer contract so `service_tickets.host.issued` cannot silently regress to an unpopulated field.

2. **Long repository paths must be shortened without leaving approved evidence roots.**
   - The portable launcher on this sprint already owns a temporary `SUBST` repo alias for long paths.
   - Direct/manual recovery must alias the *repository root* and keep evidence under the aliased repo (`<drive>:\runs` or `<drive>:\survey\output\runs`).
   - Do not redirect deployment evidence to an arbitrary short folder such as `%LOCALAPPDATA%\SASAL`; `SasRunContext` correctly rejects output outside approved repo-local roots.

3. **Fresh-box operator bootstrap is per Windows user / PC.**
   - If `%LOCALAPPDATA%\SysAdminSuite\bin\sas.cmd` does not exist, install the portable operator command once from a checkout, then run the Guest-side refresh workflow.
   - `SAS_OPERATOR_REFRESH_READY` plus the printed field-ready HEAD is the sync proof before moving to the protected network.

4. **Approved software-source aliases must be canonicalized before Kerberos CIFS use.**
   - `SasSoftwareSourceIdentity.psm1` resolves the catalog-approved server alias to its canonical FQDN.
   - The canonical name is accepted only when it resolves to at least one address also returned for the approved alias.
   - The resolver emits the canonical `CIFS/<fqdn>` SPN and canonical UNC root without collecting credentials or ticket bytes and without target mutation.
   - The approved catalog alias remains the authority; DNS canonicalization is a runtime Kerberos-access identity, not an alternate package source.

## Field proof achieved after the HOST-ticket correction

A bounded read-only Kerberos readiness run reached `kerberos_smb_task_ready` with all of the following true:

- domain joined
- TGT present
- CIFS ticket requested and issued
- HOST ticket requested and issued
- TCP 445 reachable
- ADMIN$ authorized
- TCP 135 reachable
- Schedule service running
- scheduled-task query authorized

This proves the earlier `KERBEROS_S4U_KERBEROS_IDENTITY_BLOCKED` result was a producer/consumer contract defect, not evidence that the operator identity lacked the required target authorization.

## Software-source identity proof

The next bounded diagnostic reached:

`SOFTWARE_SOURCE_KERBEROS_READY_FQDN_ONLY`

The proof established all of the following without target mutation:

- TGT remained present.
- The catalog-approved short server alias resolved to a canonical FQDN.
- The short CIFS ticket was not issued.
- The canonical FQDN CIFS ticket was issued.
- The same approved installer was readable through the canonical FQDN UNC path.
- Target mutation remained false.

Therefore the source failure was not package absence, target authorization, or a missing TGT. It was a source-name/SPN mismatch: the S4U caller requested CIFS for the catalog short alias even though Kerberos and SMB access were proven on the DNS-canonical identity.

## Canonical-source field proof

A bounded field patch then used the approved alias only as source authority, required alias/canonical address overlap, requested the canonical CIFS SPN, and read the same approved installer through the canonical UNC.

That run advanced past `KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED` and reached the baseline guard. This proves the canonical source identity correction is functionally correct for the AutoLogon lane.

The run stopped at:

`KERBEROS_S4U_DIRTY_BASELINE`

No AutoLogon installation or restart was performed by that attempt. The next action is evidence inspection, not reinstall. The baseline is considered clean only when both are true:

- `snapshot.autologon.status == not_configured`
- no installed-software row matches `NW AutoLogon Setup`

Any other state must be classified from the captured `baseline_snapshot.json` before deciding whether the target is already configured, partially configured, or has package-only residue.

## Current remaining deployment blocker

The current blocker is the target's dirty AutoLogon baseline, not Kerberos transport or software-source access.

Do not blindly rerun the installer. Inspect the newest S4U `baseline_snapshot.json` and report at minimum:

- `postinstall_set_autologon`
- `auto_admin_logon`
- `default_user_name`
- `default_domain_name`
- `force_auto_logon`
- `auto_logon_count`
- `default_password_present` (presence only; never the value)
- `expected_user_match`
- `autologon.status`
- any installed-software rows matching `NW AutoLogon Setup`

At the latest stop:

- `autologon_applied = false`
- `pre_reboot_autologon_ready = false`
- `automatic_reboot_performed = false`
- the baseline capture completed before installation

## Non-regression boundaries

- Keep the protected-network gate before target contact.
- Keep the current named-domain S4U principal and `/NP` passwordless task model.
- Do not collect or serialize `DefaultPassword`.
- Do not weaken the clean-baseline, hash, final-step, cleanup, or restart-observation gates.
- Do not treat automatic desktop sign-in observation as required for deployment-complete classification.
- Do not reinstall clinical-core applications merely to reach AutoLogon when they are already independently proven accepted.
- After a terminal failure or crash, inspect recorded evidence before mutation or retry.

## Required successful terminal classification

AutoLogon-only deployment is complete only at:

`AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`

That classification remains downstream of clean pre-reboot AutoLogon state, required restart initiation, observed SMB offline/online restart cycle, and restart-task cleanup verification.