# AutoLogon remote Kerberos/S4U pilot

## Objective

Configure the current approved AutoLogon package on an authorized Cybernet workstation **without anybody logging on to the target first**.

Operator command:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET-HOST>
```

This lane uses the controller's current named domain identity, a fresh Kerberos SMB/Task Scheduler preflight, SMB staging, and a one-time Task Scheduler **S4U** task running at **HighestAvailable**.

The target may be sitting at the Windows sign-in screen. A target user session is not required.

## Why this is separate from LocalSystem

The pinned no-argument `NW_AutoLogon_Setup_x64.exe` already returned exit code `0` as LocalSystem without establishing `AutoAdminLogon=1`. That result remains recorded and blocked.

The S4U lane tests and uses a materially different **security context**, not a different package invocation:

```text
controller current domain administrator
        |
        | Kerberos TGT + target CIFS/HOST service tickets
        v
Kerberos-authenticated SMB / Remote Task Scheduler
        |
        | stage exact EXE locally and verify SHA-256
        v
Task Scheduler: named domain principal / S4U / HighestAvailable
        |
        | no stored password; no target login; local resources only
        v
NW_AutoLogon_Setup_x64.exe
        |
        v
SYSTEM read-only After-state proof + cleanup
```

An S4U success does **not** change or imply:

```text
canonical_system_install_enabled = true
canonical_system_qualification.status = qualified
```

Canonical LocalSystem qualification remains a separate future-candidate lane.

## S4U security boundary

Windows Task Scheduler S4U runs the task as the named user without storing that user's password. The S4U task does not have network or encrypted-file access.

SysAdminSuite deliberately uses that limitation as a boundary:

- the controller obtains the approved package over its own Kerberos-authenticated session;
- the controller stages the exact EXE to `C:\ProgramData\SysAdminSuite\AutoLogonKerberosS4U\<run-id>`;
- source and staged SHA-256 must match;
- the S4U task reads only local staged files;
- the S4U task must prove its SID matches the controller-authorized principal;
- the S4U task must prove it has an administrator token before the installer starts;
- no password is passed to Task Scheduler or written to evidence.

## Required starting state

The controller must be running under the named domain administrator identity that is authorized on the target.

Before mutation the workflow requires:

1. approved Northwell network posture;
2. one canonical target FQDN;
3. a Kerberos TGT in the current controller token;
4. target `CIFS/<fqdn>` and `HOST/<fqdn>` service tickets;
5. authorized target `ADMIN$` / `C$` access;
6. Remote Task Scheduler authorization;
7. a Kerberos service ticket for the approved software source;
8. a clean AutoLogon baseline;
9. the existing AutoLogon final-step gate.

If the current controller identity is not a domain identity or does not have the required target administrator rights, the pilot stops. Do not replace S4U with a target-side interactive login.

## Exact live sequence

` sas autologon Remote <HOST> ` performs:

1. network posture gate;
2. canonical target resolution;
3. current Windows domain identity capture;
4. fresh `kerberos_smb_task` transport preflight;
5. explicit proof of current-token TGT, target CIFS/HOST tickets, admin-share authorization, and Task Scheduler authorization;
6. explicit Kerberos ticket request for the approved software source;
7. transient SYSTEM read-only AutoLogon Before capture and cleanup;
8. clean-baseline requirement;
9. AutoLogon final-step gate;
10. exact package resolution from the approved catalog;
11. source SHA-256 calculation;
12. SMB staging to the target and target SHA-256 verification;
13. harmless one-time S4U probe task under the controller's named domain principal;
14. proof that the S4U execution SID matches the authorized principal and that the task has an administrator token;
15. one-time S4U install task using the same principal and `HighestAvailable`;
16. execution of the staged no-argument `NW_AutoLogon_Setup_x64.exe`;
17. transient SYSTEM read-only After capture;
18. required pre-reboot AutoLogon state validation;
19. S4U task deletion and absence verification;
20. run-scoped staging deletion and absence verification;
21. operator-local result emission.

No stage automatically reboots the workstation.

## Operator acknowledgement

Run:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET-HOST>
```

After the target and current S4U principal are shown, authorize only that target by typing the exact acknowledgement displayed by the launcher:

```text
S4U <SHORT-HOSTNAME>
```

## Successful pre-reboot classification

Proceed to reboot proof only when the result is exactly:

```text
KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING
```

That classification requires all of the following:

- controller Kerberos identity proof passed;
- software-source Kerberos ticket passed;
- clean baseline passed;
- final-step gate passed;
- exact source/staged installer hashes matched;
- S4U probe ran as the expected named domain SID;
- S4U probe proved an administrator token;
- target login was not required;
- no task password was stored;
- installer exit code was `0` or `3010`;
- `SetAutoLogon=Autologon_YES`;
- `AutoAdminLogon=1`;
- `DefaultPassword` value name is present while its data was never read;
- expected workstation-account match passed;
- state is `autologon_ready`;
- state-collector teardown passed;
- S4U task teardown passed;
- run-scoped staging cleanup passed.

## Post-reboot proof

The workflow stops before reboot.

After the successful pre-reboot classification, perform the separately approved reboot and directly prove:

1. Windows completes the reboot;
2. the workstation automatically signs in to the expected workstation account;
3. the current session matches that account;
4. required application/session access works;
5. the runtime proof is recorded before expansion.

Pre-reboot registry success is not automatic-sign-in proof.

## Stop classifications

Preserve the generated run folder and do not blindly retry when the result is not the exact successful classification. Important stop states include:

- `KERBEROS_S4U_TRANSPORT_BLOCKED`;
- `KERBEROS_S4U_KERBEROS_IDENTITY_BLOCKED`;
- `KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED`;
- `KERBEROS_S4U_BASELINE_BLOCKED`;
- `KERBEROS_S4U_DIRTY_BASELINE`;
- `KERBEROS_S4U_TARGET_IDENTITY_BLOCKED`;
- `KERBEROS_S4U_FINAL_GATE_BLOCKED`;
- `KERBEROS_S4U_SOURCE_BLOCKED`;
- `KERBEROS_S4U_STAGE_HASH_BLOCKED`;
- `KERBEROS_S4U_PROBE_FAILED`;
- `KERBEROS_S4U_PRINCIPAL_NOT_ELEVATED`;
- `KERBEROS_S4U_INSTALL_TASK_FAILED`;
- `KERBEROS_S4U_INSTALLER_FAILED`;
- `KERBEROS_S4U_AFTER_CAPTURE_FAILED`;
- `KERBEROS_S4U_POSTCONDITION_FAILED`;
- `KERBEROS_S4U_CLEANUP_REVIEW_REQUIRED`.

## Cybernet convergence

The tracked Cybernet package catalog already separates:

- `cybernet-clinical-core` — the five clinical applications excluding AutoLogon;
- `cybernet-autologon-only` — AutoLogon.

After one S4U AutoLogon pilot reaches the successful pre-reboot classification and the attended reboot/runtime proof passes, the Cybernet production workflow should converge on:

1. hardware configuration;
2. `cybernet-clinical-core` through the existing validated SYSTEM package engine;
3. technician/application acceptance for the clinical core as required;
4. AutoLogon last through the proven Kerberos/S4U lane;
5. post-hardware validation;
6. separately approved reboot and AutoLogon runtime proof.

Do not unblock the existing six-package SYSTEM set merely by changing `canonical_system_install_enabled`; its LocalSystem failure remains valid evidence.
