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

The transaction then timed out during the bounded Task Scheduler `/Create` call for the passwordless S4U probe task. The outer exact staging cleanup subsequently passed. No installer execution, after-state capture, reboot, or automatic-sign-in proof was reached.

## Failure class

A bounded native timeout proves only that the controller-side `schtasks.exe` process did not return within its budget. It does not prove that the remote Task Scheduler service failed to commit the exact checkpointed task before the client process was terminated.

The current task lifecycle treats `/Create` timeout as definitive failure without reconciling the exact task name. Cleanup can then prove exact absence, but the progress stream does not report cleanup PASS when a prior task error already exists.

## Repair direction

The stage-9 repair must remain fail-closed and bounded:

1. give remote task creation a dedicated 60-second bound rather than sharing the 30-second general native-operation bound;
2. if `/Create` still times out, immediately query the exact checkpointed task name;
3. continue only when that exact query proves the task exists;
4. otherwise preserve a timeout/reconciliation classification and enter exact cleanup;
5. always emit explicit cleanup PASS when exact task absence is verified after a prior failure;
6. never infer task creation from generic scheduler state or create a second task name.

## Proof ceiling

Repository and CI proof cannot establish that the protected target accepts S4U task creation. The next field attempt must first prove the previous timed-out probe task is absent and the exact staging run root is absent, apply the tracked runtime repair, then perform exactly one crash-safe retry. Stage 9 (`Probe task create`) must pass or explicitly report timeout reconciliation before later probe execution or installer claims are made.
