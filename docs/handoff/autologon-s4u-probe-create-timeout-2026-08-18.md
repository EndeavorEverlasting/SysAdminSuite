# AutoLogon S4U probe-create timeout field checkpoint

## Proven floor

The protected field transaction independently proved stages 1 through 8:

- transport preflight PASS;
- canonical software-source resolution PASS;
- source CIFS ticket PASS;
- baseline capture PASS;
- exact safe first-install baseline eligibility PASS (`intent_only`);
- final-step gate PASS with path-safe evidence placement;
- approved source SHA-256 capture PASS;
- target staging/hash verification PASS.

The transaction then timed out during the bounded Task Scheduler `/Create` call for the passwordless S4U probe task. The outer exact staging cleanup subsequently passed. No S4U probe result, installer execution, after-state capture, reboot, or automatic-sign-in proof was reached.

## Failure class

A bounded native timeout proves only that the controller-side `schtasks.exe` process did not return within its budget. It does not prove that the remote Task Scheduler service failed to commit the exact checkpointed task before the client process was terminated.

The previous bounded-native contract gave every native scheduler operation the same 30-second limit. It also returned a task-create timeout without reconciling the exact GUID-unique task identity.

## Repair

`SasBoundedNative.psm1` now recognizes only GUID-unique AutoLogon S4U Probe/Install `/Create` operations:

- requested create timeouts below 60 seconds are raised to a bounded 60-second effective window;
- a create that still times out is followed by exactly one bounded `/Query` against the same target and exact task name;
- only a successful exact query converts the ambiguous controller timeout into reconciled success;
- an absent task, query timeout, or query error preserves the original create timeout and therefore falls into the pilot's existing exact cleanup path;
- generic scheduler creates, deletes, queries, and unrelated task names retain their requested timeout behavior.

The returned bounded-native object records the requested/effective timeout policy, the initial timeout fact, whether reconciliation occurred, and the exact reconciliation result.

`Repair-SasBoundedNativeS4UCreateRuntime.ps1` applies the same function-bounded change to an already-sealed protected runtime. It backs up the module, parser-validates the transformed module, restores the original on failure, is CRLF/LF-safe and idempotent, and records that it performs no Git, network activity, target contact, or target mutation.

## Terminal timeout recovery v3

A follow-up protected recovery exposed a second durability gap: the pilot had already written its terminal `S4U_PROBE_CREATE_TIMEOUT` result, so the tracked interrupted-run discovery and exact-recovery scripts treated the run as terminal and refused the same exact cleanup that was still safe and required.

The recovery contract now admits that terminal result only when all of the following are simultaneously true:

- the pilot result uses the expected v2 schema and names the exact same run and target;
- the terminal and nested Probe lifecycle classifications are both exactly `S4U_PROBE_CREATE_TIMEOUT`;
- the nested Probe lifecycle names the exact checkpointed Probe task;
- the Install lifecycle and installer exit code are absent;
- no after-state snapshot or pre-reboot AutoLogon-ready state exists;
- the outer staging cleanup is already verified;
- no reboot or automatic-sign-in proof exists;
- the existing local evidence scan finds no installer worker/result/lifecycle or after-state evidence.

Every other terminal pilot result remains excluded from discovery and is rejected by exact recovery. The accepted path still queries, deletes if necessary, and verifies absence of only the checkpointed GUID-unique Probe task; invokes the existing `ProbeOnly` exact remote run-root cleanup; verifies task absence again; records recovery schema v3; and never launches the installer.

This promotes the field-proven local recovery behavior into the tracked repository without broadening cleanup or weakening any deployment gate.

## Regression contract

Windows PowerShell 5.1 fixtures prove:

- an exact S4U Probe/Install create requested at 30 seconds receives a 60-second effective bound;
- a timed-out create whose exact task query succeeds is reconciled without inventing a second task identity;
- a timed-out create whose exact task query does not prove existence remains a timeout;
- generic Task Scheduler create and S4U delete operations remain at their requested timeout;
- the protected-runtime repair works for CRLF and LF module shapes and is idempotent.

Static interrupted-recovery contracts additionally require the terminal timeout admission to remain exact-run, exact-target, exact-task, Probe-only, cleanup-verified, installer/after-state/reboot-free, and schema-v3 recorded. They explicitly reject restoring the old unconditional terminal-result skip/refusal behavior.

## Proof ceiling

Repository and CI proof cannot establish that the protected target accepts S4U task creation. A completed exact recovery proves only that the previously checkpointed Probe task and Probe-only remote run root were absent after bounded cleanup and that the recovery itself did not launch the installer.

The next protected field attempt must apply or verify the local bounded-native S4U create repair, re-establish protected-network authority, and perform exactly one supported crash-safe AutoLogon retry. Stage 9 (`Probe task create`) must PASS, or the new exact reconciliation evidence must prove the timed-out create committed, before later probe execution, installer execution, after-state, restart, or terminal completion claims are made.
