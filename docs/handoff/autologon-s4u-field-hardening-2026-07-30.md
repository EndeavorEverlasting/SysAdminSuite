# AutoLogon S4U field hardening — 2026-07-30

## Purpose

Preserve the field-proven findings from the July 30 Cybernet AutoLogon deployment work so a new terminal, workstation, or agent does not rediscover the same launcher, path, Kerberos, software-source identity, or baseline-classification failures.

This handoff intentionally contains no live username, password, AutoLogon secret, or authorized target identifier.

## Proven wins now represented in the repository

1. **Kerberos target readiness produces every ticket the S4U consumer requires.**
   - `SasSoftwareDeploymentLowNoise.psm1` requests both `CIFS/<target>` and `HOST/<target>` for `kerberos_smb_task` readiness.
   - SMB/admin/Task Scheduler probing does not continue until both tickets are issued.
   - `test_autologon_kerberos_s4u_contracts.py` locks the producer/consumer contract.

2. **Long repository paths must be shortened without leaving approved evidence roots.**
   - The portable launcher owns a temporary `SUBST` repo alias for long paths.
   - Direct/manual recovery must alias the repository root and keep evidence under the aliased repo (`<drive>:\runs` or `<drive>:\survey\output\runs`).
   - Do not redirect deployment evidence to an arbitrary short folder outside approved repo-local roots.

3. **Fresh-box operator bootstrap is per Windows user / PC.**
   - If `%LOCALAPPDATA%\SysAdminSuite\bin\sas.cmd` does not exist, install the portable operator command once from a checkout, then run the Guest-side refresh workflow.
   - `SAS_OPERATOR_REFRESH_READY` plus the printed field-ready HEAD is the sync proof before moving to the protected network.

4. **Approved software-source aliases must be canonicalized before Kerberos CIFS use.**
   - `SasSoftwareSourceIdentity.psm1` resolves the catalog-approved server alias to its canonical FQDN.
   - The canonical name is accepted only when it resolves to at least one address also returned for the approved alias.
   - The resolver emits the canonical `CIFS/<fqdn>` SPN and canonical UNC root without collecting credentials or ticket bytes and without target mutation.
   - The approved catalog alias remains the source authority; DNS canonicalization is only the runtime Kerberos-access identity.

5. **An inert Northwell AutoLogon intent marker is not an installed/active AutoLogon configuration.**
   - `SasAutoLogonBaselinePolicy.psm1` now encodes the first-install baseline rule.
   - `not_configured` remains accepted when no `NW AutoLogon Setup` package is installed.
   - `intent_only` is accepted only when every inert-state condition is satisfied: `Autologon_YES` intent, `AutoAdminLogon` disabled, no user/domain, no `ForceAutoLogon`, no `AutoLogonCount`, no `DefaultPassword` value present, no expected-user match, and no installed AutoLogon package.
   - Any active, partial, mismatched, password-bearing, or package-present state remains fail-closed.
   - `test_autologon_intent_only_baseline_contracts.py` locks this distinction.

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

A bounded diagnostic reached:

`SOFTWARE_SOURCE_KERBEROS_READY_FQDN_ONLY`

The proof established all of the following without target mutation:

- TGT remained present.
- The catalog-approved short server alias resolved to a canonical FQDN.
- The short CIFS ticket was not issued.
- The canonical FQDN CIFS ticket was issued.
- The same approved installer was readable through the canonical FQDN UNC path.
- Target mutation remained false.

Therefore the source failure was a source-name/SPN mismatch, not package absence, target authorization failure, or a missing TGT.

## Canonical-source field proof

A bounded field patch used the approved alias only as source authority, required alias/canonical address overlap, requested the canonical CIFS SPN, and read the same approved installer through the canonical UNC.

That run advanced past `KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED` and reached the baseline guard. This proves the canonical source identity correction is functionally correct for the AutoLogon lane.

## Baseline field proof

The captured `baseline_snapshot.json` was then classified as an exact inert intent-only first-install baseline:

- `autologon.status = intent_only`
- `postinstall_set_autologon = Autologon_YES`
- `auto_admin_logon = 0`
- no default username
- no default domain
- no `ForceAutoLogon`
- no `AutoLogonCount`
- `default_password_present = false`
- `expected_user_match = false`
- no installed-software row matching `NW AutoLogon Setup`

This state is **not** an active or half-installed AutoLogon configuration. It is an intent marker on an otherwise inactive baseline and is safe for a first AutoLogon installation under the fail-closed policy above.

The previous `KERBEROS_S4U_DIRTY_BASELINE` result was therefore a coarse classifier defect, not proof of a dirty target.

At that stop:

- `autologon_applied = false`
- `pre_reboot_autologon_ready = false`
- `automatic_reboot_performed = false`
- baseline capture completed before installation

## Current remaining integration boundary

The repository now contains the durable canonical software-source identity module and the durable intent-only baseline policy module. The executable S4U lane must consume both before the field-hardening branch is considered fully integrated.

Do not weaken the baseline rule into a generic dirty-baseline bypass. Only the exact inert `intent_only` posture above is eligible.

## Non-regression boundaries

- Keep the protected-network gate before target contact.
- Keep the current named-domain S4U principal and `/NP` passwordless task model.
- Do not collect or serialize `DefaultPassword`.
- Keep source identity fail-closed to the approved alias plus verified canonical DNS identity.
- Do not weaken hash, final-step, cleanup, or restart-observation gates.
- Do not treat automatic desktop sign-in observation as required for deployment-complete classification.
- Do not reinstall clinical-core applications merely to reach AutoLogon when they are already independently proven accepted.
- After a terminal failure or crash, inspect recorded evidence before mutation or retry.

## Required successful terminal classification

AutoLogon-only deployment is complete only at:

`AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`

That classification remains downstream of accepted first-install baseline state, required pre-reboot AutoLogon configuration, restart initiation, observed SMB offline/online restart cycle, and restart-task cleanup verification.
