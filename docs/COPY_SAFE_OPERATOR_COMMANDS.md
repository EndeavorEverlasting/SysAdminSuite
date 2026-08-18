# Copy-Safe Operator Commands

## Contract

SysAdminSuite field instructions separate **commands** from **terminal transcripts**.

A technician must never be asked to paste text containing a shell prompt such as `PS C:\...>` or a PowerShell continuation marker such as `>>`. Those strings are display metadata from an interactive terminal. They are not part of the command and become executable garbage when pasted back into PowerShell.

When a field workflow needs more than one shell statement, the workflow belongs behind a tracked repository launcher. The operator gets:

1. one launcher to open;
2. only the concrete field values the launcher requests;
3. a bounded result and durable evidence path.

Do not reconstruct a terminal session from chat output.

## Northwell printer queue proof capsule

Printer mapping already has a canonical machine-wide launcher:

```text
Map-NorthwellPrinter-SystemWide.cmd
```

After a shared queue is mapped, use the proof capsule instead of pasting a diagnostic PowerShell block:

```text
Prove-NorthwellPrinter-Queue.cmd
```

The proof capsule asks for the canonical `\\server\queue`. It may also accept a printer IP **for diagnostics only**; that IP is never used to create or remap a printer.

The proof engine performs one bounded transaction:

- validates the shared-queue contract;
- records local Spooler and queue state;
- resolves the print server;
- probes TCP 445 and RPC Endpoint Mapper TCP 135 with bounded waits;
- performs one bounded remote queue query while observing the actual RPC TCP connections selected afterward;
- optionally issues one bounded Windows test page and asks whether physical output was observed;
- writes a structured JSON result under `%LOCALAPPDATA%\SysAdminSuite\field-runs\printer-queue-proof`.

A command acknowledgement or accepted test-page request is not physical-print proof. `LIVE_PHYSICAL_PRINT_PROOF_PASS` is emitted only when the operator reports that the requested physical printer actually produced the page.

## Copy-safe output rule for agents and UI

Inline executable payloads must be one physical line and contain executable text only. Do not include:

```text
PS C:\Users\someone>
>>
```

Do not include output tables, error prose, or a second shell transcript in the same copy target. If the action cannot fit safely in one complete command, add or reuse a tracked script/CMD launcher and give the operator that launcher instead.
