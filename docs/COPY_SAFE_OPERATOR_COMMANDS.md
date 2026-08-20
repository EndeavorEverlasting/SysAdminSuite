# Copy-Safe Operator Commands

## Contract

SysAdminSuite field instructions separate **commands** from **terminal transcripts**.

A technician must never be asked to paste text containing a shell prompt such as `PS C:\...>` or a PowerShell continuation marker such as `>>`. Those strings are display metadata from an interactive terminal. They are not part of the command and become executable garbage when pasted back into PowerShell.

When a field workflow needs more than one shell statement, the workflow belongs behind a tracked repository launcher. The operator gets:

1. one launcher to open;
2. only the concrete field values the launcher requests;
3. a bounded result and durable evidence path.

Do not reconstruct a terminal session from chat output.

Do not append `exit $LASTEXITCODE`, `exit $rc`, or another caller-shell `exit` to an operator copy/paste command. A diagnostic command must not close the PowerShell or Windows Terminal session the operator is using to collect and share evidence.

## Source freshness and supersession

**Canonical mainline wins after merge.** Once a registered field capsule has merged or a newer merge has superseded its behavior, operator next-actions resolve from the capsule's declared canonical ref (`main`). A historical PR branch or pinned historical SHA is review evidence, not the field retry source.

A command may pin a PR SHA only while proving that exact **unmerged** PR. After merge, do not carry that branch/SHA forward into a technician command merely because it appeared in an earlier handoff.

**A SHA mismatch is a supersession/reconciliation signal.** If a remote branch no longer equals a previously pinned SHA, the safety check did its job. Stop that stale command and reconcile current repository truth on `main`; the mismatch is not a reason to chase the old commit, recreate an old detached worktree, or force the branch backward.

For registered capsules, source-resolution metadata lives in:

```text
harness\api\copy-safe-operator-command-policy.json
```

The Northwell printer capsule declares:

```text
canonical_ref = main
default_branch_wins_after_merge = true
historical_pr_ref_allowed_for_operator_retry = false
pinned_historical_sha_allowed_after_merge = false
ref_mismatch_action = RECONCILE_CURRENT_MAINLINE
```

## Northwell printer operational capsule

Printer mapping already has a canonical machine-wide launcher:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

After a shared queue is mapped, use:

```text
Prove-NorthwellPrinter-Queue.cmd
```

Despite the compatibility name, the normal launcher is now an **operational check**, not a repeated physical proof transaction.

**The normal launcher never prints a test page.** It does not ask for one and does not pass the diagnostic engine's explicit `-PrintTestPage` switch. A prior successful physical print is durable evidence; follow-up status checks do not consume paper merely to prove the same thing again.

Target identity is part of the proof. When the **latest complete** canonical mapping evidence identifies one unambiguous target for the requested queue, the operational engine recovers that target automatically. The latest mapping root is accepted only after its `Summary.json` reports `CompletedTargets == TotalTargets`, so a partially published pointer or status file cannot become proof. An explicit `-ComputerName` remains available for automation or deliberate override.

If the target cannot be recovered unambiguously, the operational check fails closed as `TARGET_CONTEXT_UNRESOLVED`. It does **not** silently substitute the technician/controller workstation, and it does not fall back to an older successful mapping run. The launcher therefore allows the target hostname to be entered explicitly, which is recommended after multi-target batches.

For a **remote mapped target**, the controller workstation's local `Get-Printer`/CIM state is not target state. The operational engine therefore does not run the local queue diagnostic and then call a missing controller-side queue a remote mapping failure. It evaluates only matching SYSTEM + HKLM mapping evidence inside the latest complete mapping evidence root for that target and queue. A successful result is classified `REMOTE_TARGET_MACHINE_WIDE_REGISTRATION_PROVEN` at proof level `MACHINE_WIDE_REGISTRATION`; it deliberately warns that remote runtime queue state was not observed.

For the **local workstation**, the existing bounded operational diagnostics remain authoritative for current local state. Each local check gives its child diagnostic engine a unique run-scoped diagnostic directory and accepts the raw artifact only from that directory, with the requested printer identity revalidated before classification. Concurrent checks therefore cannot select each other's queue result merely because their timestamps are close.

The default operational engine:

- validates the shared `\\server\queue` workflow;
- accepts one explicit target or recovers one unambiguous target from the latest complete canonical mapping `LATEST-PATH` evidence when `ComputerName` is omitted;
- validates completion of the pointed mapping root before reading target proof;
- fails closed with `TARGET_CONTEXT_UNRESOLVED` when target context is unavailable or ambiguous instead of defaulting to the controller workstation;
- for a remote target, evaluates matching SYSTEM + HKLM target evidence only from the latest complete mapping run, never an older historical success;
- for the local workstation, invokes the bounded diagnostic engine with `-NonInteractive` and no test-page switch;
- isolates the local child artifact under a run-scoped diagnostic directory and verifies its printer identity before use;
- records current local Spooler, queue, DNS, SMB/RPC transport, and optional TCP 9100 evidence only when the local workstation is the target;
- treats remote administrative/status-query timeouts as telemetry degradation when current local queue/transport evidence is healthy;
- preserves a previous `physical_output_observed=true` artifact for the same queue as prior physical proof instead of printing again;
- never remaps the printer by IP;
- never modifies Northwell firewall, RPC, or Group Policy;
- preserves the raw bounded diagnostic result unchanged and emits a separate operational result.

A successful real client-requested document print after the canonical mapping workflow is runtime acceptance evidence that the mapped print path worked for that observed case. Do not demote that outcome merely because lower-level queue, port, CIM, SMB, RPC, or remote status telemetry looks odd.

## Repairing already-captured physical evidence

`Repair-NorthwellPrinter-Queue-Evidence.cmd` is **artifact reclassification only**.

Use it only when a preserved local JSON artifact already records:

```text
physical_output_observed=true
```

and an implementation/classifier bug derived the wrong result from that artifact.

If that condition exists, do **not** contact the printer again. Run:

```text
Repair-NorthwellPrinter-Queue-Evidence.cmd
```

Optionally pass the canonical `\\server\queue` as its first argument. The repair engine reads local JSON evidence only. It performs:

```text
network_activity = NONE
target_contact = NONE
target_mutation = NONE
test_page_requested_by_repair = false
```

The original raw artifact is preserved unchanged. The repair emits a derived `DURABLE_PHYSICAL_PRINT_EVIDENCE_PASS` result and refreshes the stable latest aliases.

The repair launcher is **not required after a successful real document print** merely to make historical diagnostic metadata agree. If the printer has already produced the requested document and no preserved artifact specifically needs reclassification, the correct action is to preserve that runtime acceptance and stop re-proving the printer.

## Durable evidence

Every run or eligible evidence repair publishes stable aliases beneath:

```text
%LOCALAPPDATA%\SysAdminSuite\field-runs\printer-queue-proof
```

The important files are:

```text
latest.txt
latest.json
LATEST-PATH.txt
latest-diagnostic.stdout.txt
latest-diagnostic.stderr.txt
```

`latest.txt` is the human-readable summary. `latest.json` is the machine-readable operational or repaired result. `LATEST-PATH.txt` points back to the exact per-run directory and source/raw artifact.

Closing a terminal does not remove these files.

To reopen the evidence later without reconstructing a terminal transcript, run:

```text
Open-NorthwellPrinter-Queue-Proof-Logs.cmd
```

That opens the evidence directory plus the stable latest summary/result in Explorer and Notepad.

## Proof precedence

Evidence is ranked by what it actually proves:

1. A real document observed printing after canonical mapping is runtime acceptance of the mapped print path for that observed case.
2. Current canonical SYSTEM + HKLM machine-wide registration proof from the latest complete mapping run establishes that the requested queue was registered on the named target; controller-local queue absence cannot invalidate that remote-target proof.
3. A previously observed physical page recorded in durable evidence remains end-to-end proof of successful printing at that time.
4. Current local queue state, `WorkOffline`, SMB reachability, optional TCP 9100 reachability, and observed established RPC connections describe current health only for the machine where those diagnostics actually ran.
5. A remote `Get-Printer` timeout is status/administrative telemetry. It does not by itself prove that printing is broken.
6. A transient `SynSent` sample does not prove an RPC stall when an established dynamic RPC connection was also observed.

Accordingly, a remote target with current matching SYSTEM + HKLM proof is classified `REMOTE_TARGET_MACHINE_WIDE_REGISTRATION_PROVEN`, and the result does not pretend it observed runtime output on that target. If the current target cannot be identified or the latest mapping run is incomplete, the check stops at target-context/evidence failure instead of scavenging historical success. A healthy current local queue plus preserved physical proof is classified `QUEUE_OPERATIONAL_PHYSICAL_PROOF_PRESERVED`. A healthy current local queue with established transport but a remote status timeout is `QUEUE_OPERATIONAL_STATUS_TELEMETRY_DEGRADED`, not a print failure.

Current hard failures still matter when they are current observed failures on the machine being checked: missing local queue, stopped Spooler, unreachable SMB path, or an explicitly supplied printer IP whose TCP 9100 path is unreachable. They do not retroactively erase a previously observed successful print, and they are never transplanted from the controller workstation onto a different remote target.

## Explicit physical test capability

The lower-level diagnostic engine retains an explicit `-PrintTestPage` switch for a future incident where a physical print genuinely needs to be tested. That switch is **not** part of the normal launcher or normal follow-up workflow.

## Copy-safe output rule for agents and UI

Inline executable payloads must be one physical line and contain executable text only. Do not include:

```text
PS C:\Users\someone>
>>
```

Do not include output tables, error prose, or a second shell transcript in the same copy target. Do not terminate the caller's terminal merely to propagate a diagnostic exit code. If the action cannot fit safely in one complete command, add or reuse a tracked script/CMD launcher and give the operator that launcher instead.

Before emitting an operator continuation for a registered capsule, reconcile current repository truth. If the relevant capability is already merged, use canonical `main` and the tracked launcher there. Historical PR worktrees are for review/reproduction only, not for normal field continuation.
