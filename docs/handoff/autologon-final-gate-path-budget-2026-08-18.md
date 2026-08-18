# AutoLogon final-step gate path-budget field checkpoint

## Proven floor

The protected Kerberos S4U field transaction has independently proven:

- transport preflight PASS with compacted transport evidence;
- canonical software-source resolution PASS;
- source CIFS ticket PASS;
- baseline capture PASS after the bounded Task Scheduler stderr repair;
- baseline eligibility PASS with the safe `intent_only` baseline;
- no AutoLogon installer execution before the stage-6 failure.

## Current blocker

Stage 6 (`final-step gate`) failed before package hashing, staging, S4U probe, installer execution, after-state capture, or reboot because the requested `autologon_final_step_gate.json` path was approximately 270 characters. The final-step gate previously created `<OutputRoot>\<RunId>\autologon_final_step_gate.json` without projecting the Windows PowerShell 5.1 path budget.

## Repair

`Invoke-SasAutoLogonFinalStepGate.ps1` now uses a conservative 240-character budget. Normal short paths preserve the existing nested `<OutputRoot>\<RunId>\autologon_final_step_gate.json` contract. When only the nested path exceeds the budget, the result is flattened to `<OutputRoot>\autologon_final_step_gate.json`, which remains inside the owning S4U run tree and therefore remains discoverable by the existing local run-status observer.

The gate records the requested path, actual path, 240-character budget, and whether compaction occurred. A pre-existing flattened result for a different run ID is a hard collision and is never overwritten. If the flattened path itself exceeds 240 characters, the gate fails closed before directory creation.

`Repair-SasAutoLogonFinalStepGatePathRuntime.ps1` applies the same bounded behavior to an already-sealed protected runtime without Git, network activity, or target contact.

## Regression contract

Windows PowerShell 5.1 CI proves:

- the permanent final-step gate source parses;
- a normal short path remains nested;
- a synthetic requested path in the approximately 260-280 character field class is flattened below 240 characters;
- gate prerequisite results and run identity are preserved;
- different-run compacted evidence collisions are rejected without overwrite;
- the protected-runtime repair works for CRLF and LF files and is idempotent.

## Proof ceiling

Repository and CI proof cannot claim stage 6 field success. The next protected attempt must re-prove the prior transaction stopped before installer execution, apply the local final-gate path repair, re-establish protected-network authority, and perform exactly one crash-safe retry. A successful field result must show stage 6 PASS before later package-hash, staging, S4U probe/install, after-state, cleanup, restart, and terminal completion proofs are considered.
