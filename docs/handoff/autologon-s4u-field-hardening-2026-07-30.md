# AutoLogon S4U field hardening — 2026-07-30

## Purpose

Preserve the field-proven findings from the July 30 Cybernet AutoLogon deployment work so a new terminal, workstation, or agent does not rediscover the same launcher, path, Kerberos, software-source identity, baseline-classification, or host-eligibility failures.

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

6. **Real deployment targets require explicit operator-local host eligibility authority.**
   - `Test-SasHostEligibility.ps1` intentionally fails closed when `Config/host-eligibility-policy.local.json` is absent, malformed, unmatched, or does not permit the requested execution context.
   - The tracked sample policy is synthetic and must not authorize live hosts.
   - `Set-SasHostEligibilityLocalTarget.ps1` creates or updates only the gitignored local policy after explicit `-ConfirmLocalAuthorization`, inserts an exact escaped hostname pattern for `remote`, and immediately re-runs the existing eligibility validator.
   - Broad wildcard authorization is not required for field deployment and should not be introduced merely to clear the final-step gate.

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

## Host-eligibility field proof

After exact operator-local authorization was created for the already-authorized target, the existing host-eligibility validator returned:

- `eligible = true`
- `decision = allowed`
- `reason_code = PATTERN_MATCH_AND_CONTEXT_ALLOWED`
- `allowed_contexts = remote`

This cleared the prior `KERBEROS_S4U_FINAL_GATE_BLOCKED` / `host_eligibility` stop without disabling or bypassing the final-step gate.

## Interrupted live-run recovery boundary

The first live attempt after host eligibility passed advanced into the S4U AutoLogon lane and printed the normal target/principal/package header. The operator then observed no further console output for an extended period and interrupted the run with `Ctrl-C`.

Because the interruption occurred after the final-step prerequisites had been cleared, the deployment must now be treated as **state unknown until exact-run recovery proves otherwise**. Do not infer `autologon_applied = false` from any earlier result file and do not rerun the installer blindly.

The S4U implementation has long silent sections between the header and the later `Starting AutoLogon remotely...` message. During that interval it may perform transport preflight, source-ticket proof, baseline capture, final-step gate, source hashing, target staging, and the S4U probe task. A `Ctrl-C` can therefore occur before or after target staging/task creation.

Required recovery order after an interruption:

1. identify the newest exact S4U run directory under the current deployment run;
2. inspect local result/lifecycle/checkpoint evidence first;
3. query only exact SysAdminSuite task names/run roots associated with that run;
4. retrieve any completed worker result before cleanup;
5. determine whether AutoLogon was actually installed/configured before considering any retry;
6. perform only exact run-scoped cleanup after evidence retrieval.

No new installer execution is allowed until this recovery classification is closed.

## Current remaining integration boundary

The repository now contains durable canonical software-source identity, intent-only baseline policy, and exact operator-local host-authorization helpers. The executable S4U lane must consume the durable source/baseline modules before the field-hardening branch is considered fully integrated.

The immediate field action is crash recovery for the interrupted run, not another deployment attempt.

Do not weaken the baseline rule into a generic dirty-baseline bypass and do not weaken host eligibility into a broad remote wildcard. Only the exact inert `intent_only` posture and explicitly authorized exact target should pass.

## Non-regression boundaries

- Keep the protected-network gate before target contact.
- Keep the current named-domain S4U principal and `/NP` passwordless task model.
- Do not collect or serialize `DefaultPassword`.
- Keep source identity fail-closed to the approved alias plus verified canonical DNS identity.
- Keep exact operator-local host eligibility; do not replace it with a broad wildcard.
- Do not weaken hash, final-step, cleanup, or restart-observation gates.
- Do not treat automatic desktop sign-in observation as required for deployment-complete classification.
- Do not reinstall clinical-core applications merely to reach AutoLogon when they are already independently proven accepted.
- After a terminal failure or crash, inspect recorded evidence before mutation or retry.

## Required successful terminal classification

AutoLogon-only deployment is complete only at:

`AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`

That classification remains downstream of accepted first-install baseline state, explicit exact-target host eligibility, required pre-reboot AutoLogon configuration, restart initiation, observed SMB offline/online restart cycle, and restart-task cleanup verification.
