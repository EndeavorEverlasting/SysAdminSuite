# P97 — Northwell Printer Session Materialization Capability Frontier

Date: 2026-10-07  
Mode: `P97_EXHAUSTIVE_PRIOR_ART_AND_GAP_ANALYSIS`  
Repository floor: `main@2b63c6afd032c3c36fa6d6e615032fcebeb5cee4`  
Mutation authority: `false` for this research artifact  
Scope: Northwell shared-printer machine registration, standard-user session materialization, driver readiness, deferred logon delivery, and bounded Common Startup fallback.

## Problem statement

The canonical Northwell printer workflow has already proven the durable machine-registration half of the problem: SYSTEM executes `PrintUIEntry /ga` and requested queues are proven under the machine-wide HKLM connection authority. The remaining defect is narrower and must not be allowed to invalidate that proof:

> a queue can be correctly registered for the computer while the currently or subsequently logged-on standard user still fails to receive a usable session connection, whereas a privileged logged-on user can make the path work.

This is not permission to replace system-wide mapping with a per-user-only mapper. It is a requirement to separate the states that the older workflow partially conflated.

## Existing repository truth

The current repository already contains most of the correct foundation:

- `AGENTS.md`, the field-workflow skill, the printer use-case registry, and the evidence policy require Northwell mapping to remain system-wide/per-computer.
- `mapping/Invoke-NorthwellPrinterState.ps1` owns the SYSTEM `/ga` registration path and HKLM proof.
- `mapping/Confirm-NorthwellPrinterActiveUserMaterialization.ps1` and `mapping/Invoke-NorthwellPrinterSharelessActiveUser.ps1` already distinguish machine registration from an active user's session state.
- The active-user materializers already use Task Scheduler `InteractiveToken` semantics and quiet `PrintUIEntry /in`, then verify the user's printer-connection registry state.
- Existing tests deliberately reject direct-IP mapping, `Add-Printer -ConnectionName` as a Northwell fallback, test-page-as-proof substitution, stored-password task flows, and success claims without HKU/HKCU evidence.
- Historical Startup-folder VBS work remains archived. `Next plan.md` records why blind Startup-folder mapping was considered unsafe: it lacked identity gating, evidence, and rollback and would have reintroduced a per-user mapping authority.

Therefore the new design must extend the existing model rather than invent another printer engine.

## Microsoft prior art

### 1. Per-computer registration and user logon are intentionally different phases

Microsoft documents `PrintUIEntry /ga` as adding a per-computer connection that becomes available to users when they log on. The examples explicitly say the per-computer connection is applied when a user logs on.

Source:
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/rundll32-printui

Consequence: HKLM `/ga` proof is durable machine registration, but it is not sufficient proof that a given already-loaded or newly created user session successfully materialized the queue.

### 2. Interactive-token tasks require an existing logged-on user

Microsoft documents `TASK_LOGON_INTERACTIVE_TOKEN` as requiring the user to already be logged on; the task runs only in an existing interactive session. The repository's current active-user finalizer is therefore correctly suited to an already-present session but cannot by itself be the all-future-users delivery mechanism.

Source:
- https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype

Consequence: current-session materialization and future-logon materialization require separate modes.

### 3. Standard-user driver installation is a separate security boundary

Microsoft's printer policy documentation states that, by default, non-administrators cannot install print drivers when `RestrictDriverInstallationToAdministrators` is enabled or not configured.

Source:
- https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-printers#restrictdriverinstallationtoadministrators

Consequence: a privileged-user success paired with a standard-user failure can be caused by driver readiness even when machine `/ga` registration is correct. The implementation must measure this; it must not assume that every standard-user failure is a Task Scheduler or printer-mapping failure.

### 4. Driver staging can preserve the security boundary

Microsoft documents package-aware Point and Print driver staging as an administrator operation and states that, after a driver package is staged in the driver store, a standard user can install that driver.

Source:
- https://learn.microsoft.com/en-us/windows-hardware/drivers/print/point-and-print-with-packages

Consequence: if the standard-user blocker is demonstrably driver readiness, the safe workaround is to make the approved driver ready under administrative/SYSTEM authority and retry session materialization. The workaround is not to disable print-driver security policy.

### 5. Windows has an all-users Common Startup folder

Microsoft documents `CSIDL_COMMON_STARTUP` as the Startup program group for all users, typically:

`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup`

Source:
- https://learn.microsoft.com/en-us/windows/deployment/usmt/usmt-recognized-environment-variables

Consequence: the requested Startup fallback is technically legitimate as a Windows delivery surface, but it must be resolved through the Windows known-folder contract where practical rather than confused with `C:\Users\Public`.

### 6. Enterprise printer management can be policy-owned

Microsoft documents printer management through both Computer Configuration and User Configuration Group Policy.

Source:
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/printing/use-group-policy-to-control-ad-printer

Consequence: GPO is the correct enterprise-scale prior art, but SysAdminSuite must not invent or alter Northwell domain printer policy without explicit organizational authority. The field workflow should remain a bounded endpoint mechanism.

## Root-cause model

Treat these as independent dimensions:

| Dimension | Question | Authoritative evidence |
| --- | --- | --- |
| Machine registration | Is the shared queue durably registered for the workstation? | SYSTEM identity + requested queue in HKLM per-computer printer connections |
| Session materialization | Does this exact logged-on user have the requested connection? | HKU/HKCU printer-connection evidence for the user SID |
| Driver readiness | Can the standard-user session bind the queue without an administrator installing a required driver? | installed/staged driver facts + read-only printer-policy snapshot + controlled retry |
| Delivery timing | Is the user already logged on, absent, or logging on later? | loaded user hives/session evidence |
| Deferred mechanism | What causes a future standard-user session to run materialization? | native `/ga`, logon-triggered task, or Common Startup artifact |
| Cleanup | Did temporary delivery state retire without losing evidence? | explicit cleanup result; cleanup failure is incomplete |

Do not collapse these dimensions into a single boolean called "mapped."

## Capability disposition

### KEEP — canonical machine registration

**Mode M0 — `SYSTEM_GA_REGISTER`**

Mandatory first phase for every Northwell shared-printer add operation.

- Run the existing SYSTEM-owned `PrintUIEntry /ga` path.
- Require current HKLM requested-queue proof.
- Preserve existing queue/hostname/network authority.
- Never skip M0 merely because a user-session fallback will run later.

M0 proves `MACHINE_WIDE_REGISTRATION`, not user-session readiness.

### KEEP/STRENGTHEN — current active-session materialization

**Mode M1 — `ACTIVE_SESSION_DIRECT`**

Use when one or more interactive users are already logged on.

- Reuse the existing InteractiveToken user-session mechanism.
- Run quiet `PrintUIEntry /in` inside each exact loaded interactive user token.
- Verify the queue under each exact user SID.
- Capture task registration/run result and user proof separately.
- If a standard user fails, classify the cause before selecting another mode.

M1 must not silently convert a standard-user failure into "pending next logon."

### MEASURE — native next-logon behavior

**Mode M2 — `NATIVE_GA_NEXT_LOGON`**

Use when no target user is logged on, or specifically to test whether native `/ga` materialization is sufficient for a standard account.

- Complete M0 first.
- Log on with an authorized standard test/user account.
- Observe HKU/HKCU before invoking any helper.
- If the queue appears and is usable, record `NATIVE_GA_STANDARD_USER_PROVEN`.
- If it does not, retain machine registration proof and continue to classification.

This mode prevents unnecessary fallback installation on machines where Windows' native per-computer behavior is adequate.

### ADD — privileged driver-readiness bootstrap

**Mode M3 — `DRIVER_READINESS_BOOTSTRAP`**

Use only when evidence shows that the queue cannot materialize for a standard user because the required driver is unavailable to that user.

Rules:

- Do not change `RestrictDriverInstallationToAdministrators`, Point-and-Print restrictions, approved-server policy, or equivalent client security settings as a workaround.
- Do not guess an INF, driver model, print server, or package.
- Require an approved exact driver/package/server source derived from the target queue or existing organization-approved state.
- Stage/install the required driver under administrative/SYSTEM authority.
- Retry M1 or M2 under a standard user and prove the user connection.
- If exact driver authority cannot be established, return `DRIVER_STAGE_SOURCE_REQUIRED`; do not improvise.

M3 is a prerequisite repair, not another mapping authority.

### ADD — durable deferred logon materializer

**Mode M4 — `DEFERRED_LOGON_TASK`**

Preferred fallback when M0 is proven, the driver is ready, but standard-user native logon materialization is not reliable enough.

Design:

- SYSTEM/admin creates a bounded logon-triggered Task Scheduler artifact.
- The task must run in the logging-on user's interactive security context without storing credentials.
- The task only materializes queues already proven by M0; it does not invent or discover printer assignments.
- Each invocation verifies the exact user connection and writes bounded machine-local evidence.
- The durable task may remain until an explicit retirement condition is met.
- It must be removable by a machine-authority cleanup operation.
- It must not weaken Group Policy or print-driver security.

Task Scheduler is preferred over a persistent Startup script because it gives SysAdminSuite a stronger lifecycle, identity, and cleanup surface.

### ADD — Common Startup one-shot bootstrap

**Mode M5 — `COMMON_STARTUP_ONE_SHOT`**

This is the requested self-deleting fallback, with one essential correction: **self-deleting and durable all-future-users are different semantics**.

A one-shot helper can execute from Common Startup for whichever user next logs on, but after successful self-deletion it cannot independently guarantee execution for every later user. Therefore M5 is valid only as:

- a one-session recovery/bootstrap after M0; or
- a temporary bridge when M0 native next-logon behavior or M4 owns future users.

Safety contract:

- Resolve Common Startup through the Windows known-folder contract where practical.
- Generate a local/untracked artifact containing the exact already-approved queue set; tracked examples remain synthetic.
- Before any `/in`, verify the machine-registration receipt is for the same target/use case/queues.
- Run as the logging-on user and verify HKCU/HKU connection state.
- Emit a success/failure receipt to a machine-local evidence location that the user context can write safely.
- **Delete the Startup launcher/payload only after verified success and durable receipt creation.**
- On failure, preserve the artifact for bounded retry or SYSTEM cleanup and record failure.
- Never self-delete first and then assume success.
- Never call M5 an all-users durability mechanism by itself.

### ADD — Common Startup persistent emergency fallback

**Mode M6 — `COMMON_STARTUP_PERSISTENT`**

Last-resort mode when M4 is unavailable or empirically fails and a client-approved endpoint fallback is still required.

- Same identity, assignment, policy, evidence, and no-credential rules as M5.
- Does **not** self-delete after the first successful user.
- Idempotently no-ops when the exact user already has the connection.
- Retires only through a SYSTEM/admin cleanup path or a separately proven retirement criterion.

M6 is intentionally distinct from M5 so the repository cannot make the impossible claim that one self-deleting execution is also persistent all-user delivery.

## Required classification outcomes

At minimum the implementation must expose closed, machine-readable outcomes equivalent to:

- `MACHINE_REGISTRATION_PROVEN`
- `READY_ACTIVE_SESSION`
- `PENDING_NATIVE_NEXT_LOGON`
- `NATIVE_GA_STANDARD_USER_PROVEN`
- `BLOCKED_DRIVER_NOT_READY`
- `DRIVER_STAGE_SOURCE_REQUIRED`
- `DRIVER_STAGED_RETRY_REQUIRED`
- `BLOCKED_SESSION_TASK`
- `DEFERRED_LOGON_TASK_STAGED`
- `COMMON_STARTUP_ONESHOT_STAGED`
- `COMMON_STARTUP_PERSISTENT_STAGED`
- `STANDARD_USER_FORCED_MATERIALIZATION_PROVEN`
- `BLOCKED_UNCLASSIFIED_STANDARD_USER_FAILURE`
- `CLEANUP_FAILED_INCOMPLETE`

Names may be normalized by the implementation only if the semantics remain closed and validators cover them.

## Security invariants

The following are non-negotiable:

1. SYSTEM `/ga` + HKLM remains the durable Northwell machine-registration authority.
2. No direct-IP printer install.
3. No guessed print server or queue.
4. No stored user password and no password-backed scheduled task.
5. No disabling or weakening print-driver/Point-and-Print policy to make the workflow succeed.
6. No user-session result may be promoted from command exit code alone; verify HKU/HKCU.
7. No driver-readiness conclusion may be inferred merely from "admin works / standard user fails"; collect driver/policy evidence and perform a controlled retry.
8. No Startup helper may contain live assignment data in Git.
9. No Startup helper may run before it is bound to an already-proven M0 receipt for the same queue set.
10. Cleanup failure is not success.
11. One-shot and persistent all-user semantics must remain separate.
12. Health & Hospitals or another organization must not inherit this Northwell behavior.

## P97 decision

The capability frontier is sufficiently understood to move from open-ended research to deterministic implementation.

The preferred operational chain is:

`M0 machine registration -> classify current session -> M1 if user present -> M2 if native next logon is the correct next discriminator -> M3 only for proven driver-readiness gaps -> M4 as primary durable fallback -> M5 as one-shot emergency bridge -> M6 only as persistent emergency fallback`

The remaining unknown is empirical, not architectural: which discriminator explains the observed standard-user failure on the actual Northwell workstation(s). That is owned by the P82 experiment ladder in the companion plan.
