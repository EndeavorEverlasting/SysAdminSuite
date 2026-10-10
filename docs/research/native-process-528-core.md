# #528 P95-Core evidence audit

Floor: `76a4caf2db769a156765d5a1d74e2d0c795978f7`; branch `codex/native-528-core-research`. This lane owns this document only. Parent coordinator owns remote freshness, PTop identity, PR convergence and finding ingestion. Canonical P95 was read from the coordinator's private TokenCorridor resolution artifact. No installation, device, network-transition or production S4U command ran.

## Existing owner and contracts

`scripts/SasBoundedNative.psm1:4-34` owns PID-bound `taskkill /PID /T /F` with a five-second default kill bound. Exit 0 or 128 is considered tree termination; this is command-result evidence, not enumeration proving every descendant absent. `Invoke-SasBoundedPowerShell` (36-95) launches Windows PowerShell 5.1 by absolute Windows path with Unicode encoded script, drains stdout/stderr asynchronously, waits boundedly, and disposes the Process. A timeout returns exit -1, empty output, timeout diagnostic and termination flags. Normal completion then calls parameterless WaitForExit and reads both task Results; descendants retaining pipe handles can therefore outlive the nominal bound. No WorkingDirectory, environment override, cancellation, output cap or native argv interface is exposed.

The base object owns integer `process_id`, `exit_code`, `timeout_seconds`; booleans `timed_out`, `child_tree_termination_attempted`, `child_tree_terminated`; string `output`, `error`, `started_utc`, `completed_utc`. Start failure throws instead of returning this shape. Timeout deliberately discards partial stdout/stderr.

`Invoke-SasBoundedNative` (97-228) serializes executable/arguments into a UTF8 JSON/base64 payload, then runs that payload through the WindowsPS child. Lines 141-151 set ErrorActionPreference Stop, invoke native with `2>&1`, stringify/join lines and exit LASTEXITCODE. Native stream separation is lost; native stderr can become a terminating WindowsPS error. Parent PS7 does not change the child's PS5.1 semantics. The wrapper adds executable/arguments, requested/effective timeouts, policy, initial timeout/error, finite reconciliation attempts and final reconciliation object. Results contain raw arguments/output: privacy remains the caller's responsibility, not automatic sanitization.

Exports (342): Invoke-SasBoundedNative, Invoke-SasBoundedPowerShell, Test-SasBoundedPath, New-SasBoundedDirectory, Copy-SasBoundedFile, Get-SasBoundedFileHash. No third-party module dependency; WindowsPS and taskkill are required. Filesystem adapters (230-340) preserve separate JSON parsing rules. Test-SasBoundedPath treats exit0 as succeeded even if JSON cannot parse; Get-SasBoundedFileHash additionally requires a nonempty parsed hash.

## Domain safety must remain owned

S4U matching (111-135) requires schtasks basename, one Create token, nonempty remote S target and exact Probe/Install GUID task name. It does not constitute authorization and does not validate the executable's provenance. Matching create receives minimum120 seconds. After timeout (160-176), ONLY exact `/Query /S target /TN task` may run, at most three times, per-query bound min(requested,30), with two-second inter-attempt waits. No Create replay occurs. Query exit0 establishes exact-task existence, not task execution or completed AutoLogon configuration. Reconciled result keeps initial timeout/tree flags and initial error although final timed_out becomes false.

`scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1:437-473` persists exact task/run identity BEFORE Create, records attempted state BEFORE mutation, stores create evidence, and fails on timeout/nonzero. Run/result polling follow (482-551); finally Delete and exact absent Query (565-588) are separate obligations. Module import at617. Remote output schema and forbidden password-collection checks (534-543) stay domain-owned. A generic retry policy would risk replaying an already committed remote mutation and must never replace this lifecycle.

Other consumers: SasNetworkIntent imports the module (9-21), tests exact saved WLAN profile using netsh exit (103-105), requests connect (123-125), then independently polls observed network (127-140). Return-SasOperatorToPreviousNetwork also uses netsh. RestartDeployment, InterruptedAutoLogonRecovery and SasAutoLogonSmbStateRecovery use scheduler evidence. Portable/universal launcher installers package this module. Repair-SasBoundedNativeS4UCreateRuntime.ps1:46-71 recognizes literal policy/layout markers; preserving existing implementation avoids invalidating sealed-runtime repair recognition. SasSoftwareDeploymentTransport has a DIFFERENT same-named Invoke-SasBoundedPowerShell (249) with ScriptBlock/Parameters contract: do not conflate or mass replace.

## Actual local evidence

Executed both:

- `powershell.exe -NoProfile -File Tests/PowerShell/AutoLogonS4UTaskCreateTimeoutReconciliation.Tests.ps1`
- `pwsh.exe -NoProfile -File Tests/PowerShell/AutoLogonS4UTaskCreateTimeoutReconciliation.Tests.ps1`

Both exit0, print PASS. Five fixture scenarios cover normal bounded Create, second-query late commit, exhausted three-query window, unrelated Create and Delete. They replace Invoke-SasBoundedPowerShell inside the module: these prove policy/reconciliation behavior, not remote scheduling or process cleanup.

Executed actual harmless native children via the existing module from PS7:

| Native cmd `/d /c` payload | Actual wrapper outcome |
|---|---|
| `exit 0` | exit0, empty stdout; error contains WindowsPS CLIXML module-progress noise |
| `echo native-stderr 1>&2 & exit 0` | **exit1**, empty stdout; native-stderr in error: successful native exit was corrupted |
| `echo native-out & exit 7` | exit7, stdout preserved, CLIXML progress in error |

No timeout-tree runtime proof was claimed. S4U production, WLAN transition, device/ADB, firmware and Apply were skipped because forbidden to this research lane. Parent should preserve private raw run evidence; this document contains only reusable synthetic outcomes.

## P95 recommendation and frozen decision questions

**B: add a narrow neutral process execution interface inside the existing owner, leaving Invoke-SasBoundedNative and its S4U adapter unchanged.** A direct adoption is unsafe for Java stderr-success and separately owned environment/working-directory/long timeout needs. C avoids coupling but leaves duplicated execution/exit bugs untreated. B has evidence of benefit only if ONE selected consumer can adapt without changing source/network/profile semantics.

Suggested contract: executable + explicit correctly encoded arguments, working directory, scoped child environment, requested deadline; typed separate stdout/stderr/exit/timeout/tree cleanup and timestamps. Define start-failure behavior, empty string vs null, timeout partial-output and drain deadline explicitly. No automatic retry, no authorization inferred from path or arguments, no automatic remote reconciliation in neutral primitive. Avoid new module deployment dependencies, keep old result fields/signatures and literal repair markers, and bound ALL waits including stream completion. Test real PS5.1/7 silent/stderr/nonzero/Unicode-space paths and timeout descendants. Existing S4U fixture must remain green unchanged. Root P95 decision must select exact interface, first consumer, rollback and accepted timeout range before implementation.
