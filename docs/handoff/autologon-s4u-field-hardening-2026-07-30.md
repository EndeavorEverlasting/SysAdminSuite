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

## Current remaining deployment blocker

After target Kerberos readiness passed, AutoLogon advanced to:

`KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED`

Meaning: the controller could not obtain the required Kerberos service ticket for the **approved software source server** recorded by the package catalog/harness.

At this stop:

- `autologon_applied = false`
- `pre_reboot_autologon_ready = false`
- `automatic_reboot_performed = false`
- no retry should be treated as an already-completed install

The next diagnostic must stay narrow: resolve the approved software-source server from tracked catalog data, inspect/request its CIFS Kerberos ticket, and distinguish name/SPN/ticket issuance from SMB/package availability. Do not broaden to WinRM, subnet discovery, credential prompts, or a different package source.

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
