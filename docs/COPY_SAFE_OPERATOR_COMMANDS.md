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

The default operational engine:

- validates the shared `\\server\queue` workflow;
- invokes the bounded diagnostic engine with `-NonInteractive` and no test-page switch;
- records current local Spooler, queue, DNS, SMB/RPC transport, and optional TCP 9100 evidence;
- treats remote administrative/status-query timeouts as telemetry degradation when current queue/transport evidence is healthy;
- preserves a previous `physical_output_observed=true` artifact for the same queue as prior physical proof instead of printing again;
- never remaps the printer by IP;
- never modifies Northwell firewall, RPC, or Group Policy;
- preserves the raw diagnostic result unchanged and emits a separate operational result.

## Durable evidence

Every run publishes stable aliases beneath:

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

`latest.txt` is the human-readable summary. `latest.json` is the machine-readable operational result. `LATEST-PATH.txt` points back to the exact per-run directory and raw diagnostic artifact.

Closing a terminal does not remove these files.

To reopen the evidence later without reconstructing a terminal transcript, run:

```text
Open-NorthwellPrinter-Queue-Proof-Logs.cmd
```

That opens the evidence directory plus the stable latest summary/result in Explorer and Notepad.

## Proof precedence

Evidence is ranked by what it actually proves:

1. A previously observed physical page for the same queue is durable end-to-end proof of successful printing at that time.
2. Current local queue state, `WorkOffline`, SMB reachability, optional TCP 9100 reachability, and observed established RPC connections describe current health.
3. A remote `Get-Printer` timeout is status/administrative telemetry. It does not by itself prove that printing is broken.
4. A transient `SynSent` sample does not prove an RPC stall when an established dynamic RPC connection was also observed.

Accordingly, a healthy current queue plus preserved physical proof is classified `QUEUE_OPERATIONAL_PHYSICAL_PROOF_PRESERVED`. A healthy current queue with established transport but a remote status timeout is `QUEUE_OPERATIONAL_STATUS_TELEMETRY_DEGRADED`, not a print failure.

Current hard failures still win: missing local queue, stopped Spooler, unreachable SMB path, or an explicitly supplied printer IP whose TCP 9100 path is unreachable are not hidden by older proof.

## Explicit physical test capability

The lower-level diagnostic engine retains an explicit `-PrintTestPage` switch for a future incident where a physical print genuinely needs to be tested. That switch is **not** part of the normal launcher or normal follow-up workflow.

## Copy-safe output rule for agents and UI

Inline executable payloads must be one physical line and contain executable text only. Do not include:

```text
PS C:\Users\someone>
>>
```

Do not include output tables, error prose, or a second shell transcript in the same copy target. Do not terminate the caller's terminal merely to propagate a diagnostic exit code. If the action cannot fit safely in one complete command, add or reuse a tracked script/CMD launcher and give the operator that launcher instead.
