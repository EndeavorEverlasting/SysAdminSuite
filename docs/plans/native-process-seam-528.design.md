# Native process seam #528 design decision

Decision: INTEGRATION_APPROVED, option B. P95 converged two independently dispatched native subagent research lanes at planning floor 76a4caf2. Audits: [core](../research/native-process-528-core.md), [callers](../research/native-process-528-callers.md). TokenCorridor resolved P04/P95/P07/P08/P82 from refreshed upstream; its #142 dispatcher remains unavailable, so actual local native subagent calls supplied parallel execution. Provisional dispatch JSON is not launch evidence.

## Frozen boundary

Add exported Invoke-SasNativeProcess to scripts/SasBoundedNative.psm1. Keep existing Invoke-SasBoundedNative and S4U reconciliation behavior unchanged. First and only migrated consumer: scripts/Invoke-SasAndroidToolchain.ps1 Invoke-Bounded. Git refresh is deferred.

Inputs: FilePath string, Arguments string array (default empty), TimeoutSeconds integer 1..86400, optional Environment hashtable applied to child only; explicit CommandLine string mutually exclusive with Arguments for a caller-owned shell grammar. No shell fallback or PATH discovery, no implicit CMD behavior. Standard Windows argv quoting handles empty arguments, spaces, quotes and trailing backslashes; caller owns explicit CMD validation/composition.

Result: process_id, nullable exit_code, timed_out, timeout_seconds, output (plain stdout string including empty), error (plain stderr string including empty), started_utc, completed_utc, child_tree_termination_attempted, child_tree_terminated, output_complete. Return one typed object, never mutate caller LASTEXITCODE. Missing/start failure throws; completed native nonzero is data. Timeout never becomes success. Streams stay separate. Finite child wait, finite drain, cleanup only by owned PID. Cleanup acknowledgment must not be described as verified descendant absence. No argument/credential transcript logging in module.

Android adapter retains domain reason classification, existing stdout/stderr log paths and receipt shape, plain stdout source JSON, PSModulePath child override, CMD safety rules, and fixture prohibition. Timeout or incomplete output fails closed. No AndroidProvider M2 rewrite; sealed runtime must include the new module dependency before use.

## Architecture comparison and critique

A direct existing-wrapper reuse rejected: actual stderr-only exit-zero child becomes exit one, merged streams contaminate JSON, timeout ceiling conflicts with Android, and S4U policy is not a neutral primitive. C separate implementations retains repeated lifecycle/exit defects; shared result type alone does not remove them. B preserves compatibility while moving one consumer onto independently tested execution ownership. Do not migrate old S4U adapter during this sprint. Main risks: Windows argv correctness, pipe descendants outliving root, PS5.1 handle lifecycle, child environment isolation, timeout cleanup evidence. Tests must falsify these properties rather than mirror source.

## Implementation lanes and proof

P07 core owns only module addition; regression lane owns Tests process/Android tests. Root owns consumer migration, schema/registry dependency corrections, design and closeout. Isolated branches prevent writer collisions. Real harmless child cases under WindowsPS5.1 and PS7: silent exit zero, stderr-only success, stdout with exit seven, timeout and owned descendants, stream-drain deadline, Unicode/spaces/empty/trailing slash/embedded quote, JSON strings, caller LASTEXITCODE and child environment isolation. Existing S4U fixtures and Git refresh controls remain required. Android seven-group Python contracts and fixture entrypoint E2E; default fixture/loopback E2E, applicable registries, CI and reviews before merge. Read-only PTop Verify may run only after canonical freshness; no Apply, emulator, ADB, firmware, network posture changes, DTop or independent qualification bypass. Proof ceiling: repository integration plus harmless host-native process behavior and bounded read-only PTop verification; no device/production proof.
