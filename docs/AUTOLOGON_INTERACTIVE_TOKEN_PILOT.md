# AutoLogon interactive-token field pilot

## Purpose

Use this lane when an authorized Cybernet workstation **requires AutoLogon now**, the approved `NW_AutoLogon_Setup_x64.exe` package is still the current package, and canonical LocalSystem execution remains blocked by the recorded failed runtime validation.

This is a separate field-completion lane. It does **not** qualify or promote the package for canonical LocalSystem deployment.

The operator command is:

```powershell
sas autologon Interactive <AUTHORIZED-CYBERNET-HOST>
```

A short hostname or exact FQDN may be supplied. SysAdminSuite resolves the canonical target identity before mutation.

## Why this lane exists

The current pinned no-argument EXE returned exit code `0` as LocalSystem without establishing `AutoAdminLogon=1`. Repeating that same SYSTEM invocation is therefore blocked.

The package may still be run in the already logged-on administrator's interactive Windows session. The pilot uses a one-time Task Scheduler task configured for the existing interactive token and highest available run level. No user password is supplied to or stored by SysAdminSuite.

Success in this lane means only that the approved package configured the required **pre-reboot** AutoLogon state in that interactive administrator context. It does not change:

```text
canonical_system_install_enabled = false
canonical_system_qualification.status = failed_runtime_validation
```

## Required starting state

Before running the pilot:

1. the five non-AutoLogon Cybernet clinical applications must already be deployed and technician-accepted for the target;
2. AutoLogon must be the final product-configuration mutation;
3. one authorized Windows administrator must already be logged on to the target workstation;
4. the controller must have the current authorized Windows administrative token, approved package-share access, target `C$` / `ADMIN$` access, and Remote Task Scheduler access;
5. the target must have a clean AutoLogon baseline: no configured AutoLogon state and no existing `NW AutoLogon Setup` uninstall entry;
6. an attended reboot window and technician must be available after the pre-reboot configuration succeeds.

Do not use this lane to reinstall over an unknown or partially configured AutoLogon state.

## What the command does

` sas autologon Interactive <HOST> ` performs this bounded sequence:

1. requires approved Northwell network posture;
2. resolves the supplied target to one canonical identity;
3. runs a fresh `kerberos_smb_task` preflight;
4. captures a read-only AutoLogon baseline through the existing transient LocalSystem state collector;
5. requires a clean baseline and captures the currently logged-on target user;
6. runs the existing AutoLogon final-step gate;
7. resolves the exact approved AutoLogon package from `configs/software-packages/approved-apps.json` and the approved software source from the harness API;
8. stages only the pinned EXE beneath a unique `C:\ProgramData\SysAdminSuite\AutoLogonInteractive\<run-id>` directory and verifies source/target SHA-256 equality;
9. creates a one-time interactive-token probe task for the captured logged-on user and requires an interactive, matching, elevated administrator token;
10. only after that probe passes, creates a second one-time task that starts the pinned AutoLogon EXE with the approved empty argument set in that same logged-on elevated session;
11. waits for the installer result; an installer window may be visible on the target;
12. captures After state through the read-only LocalSystem collector;
13. requires `SetAutoLogon=Autologon_YES`, `AutoAdminLogon=1`, `DefaultPassword` value-name presence without reading its data, expected workstation-account match, and `autologon_ready` status;
14. deletes the one-time tasks and removes the run-scoped interactive staging directory;
15. writes operator-local evidence under `survey/output/runs/autologon-interactive-token/`.

The workflow never reads the `DefaultPassword` value data and never accepts or stores a target-user password.

## Operator interaction

Run:

```powershell
sas autologon Interactive <AUTHORIZED-CYBERNET-HOST>
```

Review the resolved target and package summary. To authorize the one-target mutation, type the exact acknowledgement shown by the launcher:

```text
INTERACTIVE <SHORT-HOSTNAME>
```

If the installer presents its approved user interface on the target workstation, complete only the expected AutoLogon package interaction. Do not improvise registry edits, alternate switches, or another execution method.

## Required successful result

Do not reboot or expand until the command reports exactly:

```text
INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING
```

That classification requires:

- fresh transport preflight;
- clean baseline;
- final-step gate pass;
- logged-on interactive user found;
- interactive task identity matches that user;
- elevated administrator token proven;
- source/staged installer SHA-256 match;
- installer exit code `0` or `3010`;
- required pre-reboot AutoLogon state present;
- read-only After capture completed;
- one-time task cleanup verified;
- run-scoped staging cleanup verified.

## Attended reboot proof

The pilot does **not** reboot automatically.

After the successful pre-reboot classification:

1. keep a technician present;
2. perform the separately approved reboot;
3. directly observe Windows complete the reboot;
4. directly observe automatic sign-in to the expected workstation account;
5. verify the current signed-in session is the expected AutoLogon session;
6. complete the required application/session-access acceptance;
7. record the runtime result through the existing AutoLogon proof workflow before expanding to additional workstations.

Pre-reboot configuration is not proof that automatic sign-in works after restart.

## Stop conditions

Stop and preserve the run root when the result is anything other than the required successful classification, including:

- `INTERACTIVE_TOKEN_TRANSPORT_BLOCKED`;
- `INTERACTIVE_TOKEN_BASELINE_BLOCKED`;
- `INTERACTIVE_TOKEN_DIRTY_BASELINE`;
- `INTERACTIVE_TOKEN_NO_LOGGED_ON_USER`;
- `INTERACTIVE_TOKEN_FINAL_GATE_BLOCKED`;
- `INTERACTIVE_TOKEN_SOURCE_BLOCKED`;
- `INTERACTIVE_TOKEN_STAGE_HASH_BLOCKED`;
- `INTERACTIVE_TOKEN_PROBE_FAILED`;
- `INTERACTIVE_TOKEN_NOT_ELEVATED`;
- `INTERACTIVE_TOKEN_INSTALL_TASK_FAILED`;
- `INTERACTIVE_TOKEN_INSTALLER_FAILED`;
- `INTERACTIVE_TOKEN_AFTER_CAPTURE_FAILED`;
- `INTERACTIVE_TOKEN_POSTCONDITION_FAILED`;
- `INTERACTIVE_TOKEN_CLEANUP_REVIEW_REQUIRED`.

Do not blindly rerun a changed target. Inspect the generated evidence first.

## Canonical SYSTEM qualification remains separate

An interactive-token success proves only the package's behavior in the existing logged-on elevated administrator session. It is **not** evidence that the EXE works as LocalSystem.

Continue to use `Qualify-AutoLogonSystemPackage.cmd` only when a materially different, evidence-backed SYSTEM candidate becomes available. Only the canonical qualification and separate catalog-promotion workflow may set `canonical_system_install_enabled = true`.
