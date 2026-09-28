# H&H CC Reader QR + Baseline Convergence Plan

Date: 2026-09-28  
Status: planning / implementation not yet authorized by this document  
Repository: `EndeavorEverlasting/SysAdminSuite`  
Planning branch: `plan/hh-cc-reader-qr-baseline-2026-09-28`  
Base: `main@6be2e47097336125caa58306d1063fb39699e60f`  
Related field-acceptance ledger: issue #436  
Related Netstat/baseline documentation: PR #441 (open at planning time)

## Mission

Make CC-reader technician commands usable through two equivalent transports:

1. readable copy/paste text in the technician runbook; and
2. locally rendered QR scan-to-paste when a canonical field launcher exists.

The command authority is the repository-owned launcher/runtime contract. QR is only a transport for that same authority.

The field baseline must remain visible next to the command that produces it. A technician should be able to answer, for every command:

- what am I running;
- what observation does it establish;
- where do I record the result;
- whether QR is currently approved for that action.

## Non-negotiable convergence rule

**One canonical command payload, multiple transports.**

Do not maintain a separate "QR command" and "copy/paste command." The human-readable command is the payload preview. The QR renderer receives that exact string after parameters have been resolved.

Existing repository doctrine applies:

- `QR = pointer, not payload`;
- keep QR capsules short; the existing dispatcher targets roughly 120 characters when practical;
- never embed full scripts, encoded commands, `Invoke-Expression`, download-and-execute chains, credentials, or secrets;
- local/offline QR rendering is the supported field path;
- QR, GUI, dashboard, tutorial, and prose surfaces remain downstream of the proven CMD/runtime contract.

## Current repository reality

### Supported CC-reader workstation probe

The merged field front door is:

```text
Probe-HHCCReader.cmd TARGET_IPV4 [EXPECTED_MAC]
```

This launcher is the current technician authority for the read-only workstation-side reader probe. A device-specific QR may eventually carry a resolved invocation of this launcher because a tracked CMD contract already exists.

The QR must not commit or persist the live target IP/MAC in Git. Live values remain external field evidence.

### Manual PowerShell snippets

The technician runbook also shows read-only PowerShell component snippets for human-readable cross-checks. They remain diagnostic/component evidence, not a replacement for the tracked launcher.

### Remote endpoint correlation

The current runbook uses a bounded manual continuation after a specific endpoint is directly observed and approved:

```powershell
$RemoteEndpoint = "<APPROVED_REMOTE_HOST_OR_IP>"
Test-NetConnection $RemoteEndpoint -Port 443 -InformationLevel Detailed
```

This is **not yet a QR-ready technician contract** because no tracked endpoint CMD front door currently owns the workflow.

Do not solve that gap by QR-encoding the raw two-line script and calling it field-ready.

## Baseline adjacency contract

Every executable snippet/launcher shown to a technician must have these fields immediately adjacent in the runbook.

| Command / action | Baseline established | Findings destination | QR state |
| --- | --- | --- | --- |
| Set/select reader target | target identity supplied for the run | Reader Baseline: Target IPv4 / Expected MAC | parameter input; not standalone QR |
| `Probe-HHCCReader.cmd ...` | active network/profile, source interface/address, same-subnet gate, neighbor/MAC, bounded ICMP, detailed TNC, explicit TCP result, receipt | Reader Baseline | eligible after exact device-specific payload generation |
| `Get-NetNeighbor` | observed neighbor state + observed MAC when available | Reader Baseline | copy/paste diagnostic only |
| bounded `ping` | bounded ICMP observation | Reader Baseline: Ping Received / Notes | copy/paste diagnostic only |
| detailed `Test-NetConnection` to reader | source/interface/path context | Reader Baseline: Source Interface / Source IPv4 / Notes | copy/paste diagnostic only |
| TCP/443 `Test-NetConnection` to reader | reachability to that reader IP/port only | Reader Baseline: TCP 443 / Notes | copy/paste diagnostic only |
| approved remote endpoint correlation | approved endpoint, resolved IP, port, source address/interface, TCP result, evidence reference, ownership classification, approval source | Endpoint Correlation | **blocked until endpoint CMD exists** |

A failed ping does not prove a reader is offline. TCP success proves reachability to the specified endpoint/port only. It does not prove service ownership or firmware authority.

## QR transport contract

### Payload shape

Terminal-oriented QR capsules use a **single-line payload**.

- Do not use literal CR/LF inside a command capsule.
- Prefer one short launcher invocation over PowerShell statement composition.
- Use straight ASCII quotes, spaces, hyphens, and switches in command payloads.
- If a value requires quoting, the displayed payload and QR payload must contain the same quote characters.
- Scanner suffix behavior is not part of the QR payload.

### Scan behavior

Default field posture is **scan to paste, review, then execute**.

- Standard scanner profile should not append Enter/Return by default.
- The technician scans into the intended terminal/input box.
- The visible scanned text is reviewed.
- The technician presses Enter manually.
- An alternate auto-submit scanner profile must not become the default merely for convenience.

This prevents a scanner configuration detail from silently converting "scan" into "execute."

### Round-trip proof

A QR is not accepted because an image was generated.

For every canonical payload fixture:

1. build the exact payload string;
2. render locally/offline;
3. decode the generated image;
4. require decoded text to equal the original payload exactly;
5. test with the intended physical scanner profile when available;
6. verify the scanner does not alter quotes, spaces, hyphens, or append an unapproved suffix;
7. only then classify that payload shape as scanner-ready.

Repository proof remains below live field acceptance until a physical scanner and target workflow are exercised.

### Renderer boundary

Reuse the repository's existing QR implementation before inventing another:

- `GUI/Start-SysAdminSuiteGui.ps1` already has QRCoder-backed `New-QRBitmap`, `Get-QRPayload`, and QR view helpers.
- `QRTasks/Invoke-TechTask.ps1` already establishes the short-dispatcher pattern and explicitly documents `QR = pointer, not payload`.
- `docs/dashboard/QR_CONVERGENCE_PLAN.md` and `docs/dashboard/QR_IMPLEMENTATION_READINESS.md` already require local/offline rendering and exact payload preview.

The implementation sprint should extract or wrap the smallest reusable renderer surface. Do not fork a second QR algorithm into the CC-reader lane.

## Planned implementation lanes

### P0 — documentation and evidence contract

Status: current planning lane.

- Put baseline expectations immediately beside each CC-reader snippet.
- Mark QR state explicitly: READY/ELIGIBLE, DIAGNOSTIC_ONLY, or BLOCKED_PENDING_LAUNCHER.
- Keep the technician runbook readable when no QR image is present.
- Add command-transport evidence fields so COPY_PASTE and QR_SCAN can be distinguished during acceptance.
- Keep live reader identities and generated device-specific QR images outside Git.

Proof ceiling: documentation/evidence-schema contract only.

### P1 — bounded remote-endpoint launcher

Create a tracked technician front door before any remote-endpoint QR is field-ready.

Proposed shape:

```text
Probe-HHCCReaderEndpoint.cmd APPROVED_REMOTE_HOST_OR_IP [PORT]
```

The exact name may change during implementation if a current canonical naming authority requires it.

Requirements:

- one explicit endpoint only;
- one explicit port only, defaulting to 443 only if the contract chooses to preserve that current behavior;
- no CIDR/range input;
- no wildcard discovery;
- no port sweep;
- no endpoint ownership inference;
- resolve hostname/IP deterministically;
- capture source interface/address, resolved destination, destination port, TCP result, and bounded diagnostic context;
- write sanitized machine-readable evidence under an ignored local evidence root;
- expose a concise final classification;
- register command/artifact/outcome contracts as required by the harness;
- add focused tests proving the no-scan/no-mutation/no-live-H&H boundary.

Proof ceiling: repository launcher contract. No endpoint ownership or firmware authority.

### P2 — shared local QR payload renderer

Reuse/extract the existing QRCoder-based capability into a repository-owned helper suitable for command capsules.

Requirements:

- no network/CDN dependency;
- input is the exact canonical payload string;
- render PNG without changing the payload;
- display/write the exact payload next to the QR;
- fail instead of silently truncating command payloads;
- preserve a short-payload warning threshold rather than mutating the command;
- support deterministic synthetic fixture generation in tests;
- do not persist live H&H payloads in tracked paths.

Important: the existing GUI helper currently permits payload truncation for some display-oriented QR data. **Command capsules must never silently truncate.** A command renderer must fail closed when the requested payload exceeds its accepted contract.

### P3 — QR capsule builder for approved CC-reader launchers

Build QR from an already resolved canonical invocation.

Inputs:

- canonical launcher ID/path;
- approved runtime parameters;
- scanner profile;
- optional human label.

Outputs:

- exact payload preview;
- locally rendered QR;
- payload length;
- round-trip decode result;
- classification such as `QR_READY` / `PAYLOAD_TOO_LONG` / `ROUNDTRIP_MISMATCH`.

Do not put live target data into source-controlled fixture/output paths.

### P4 — technician document integration

Only after P1-P3 prove the runtime contract:

- place QR images beside the same readable command in generated/exported technician artifacts;
- keep the text command primary and selectable;
- label QR as "scan to paste";
- show the baseline fields directly beneath the command/QR pair;
- keep a non-QR fallback complete;
- never require network access to obtain/render the QR.

The Google Drive runbook remains the live H&H field-document authority. Repository docs stay provider-neutral and contain no private Drive URL, live IP/MAC, or field screenshot.

### P5 — physical-scanner acceptance

Use one representative scanner and a non-production/synthetic command fixture first.

Acceptance matrix:

- PowerShell console;
- CMD when the launcher is a CMD;
- scanner suffix disabled;
- optional configured suffix behavior tested separately;
- straight quotes preserved;
- spaces preserved;
- hyphens/switches preserved;
- no dropped/duplicated characters;
- no unexpected line break;
- scan-to-paste requires human Enter;
- exact decoded payload equals preview.

Then perform a coordinator-approved CC-reader read-only field run. Record command transport as `QR_SCAN` and preserve the same baseline/evidence requirements as copy/paste.

Proof ceiling: scanner transport acceptance for the tested scanner/profile and tested launcher. Not firmware acceptance.

## Findings schema convergence

The external field workbook should distinguish transport from result:

- `Command Transport`: `COPY_PASTE` / `QR_SCAN`;
- `QR Round-Trip Verified?`: `YES` / `NO` / `NOT_APPLICABLE`;
- optionally `Scanner Profile` when physical scanner acceptance begins.

Transport never changes the evidence classification. A successful QR scan is not a successful network probe.

## Agent operating contract

Any agent encountering this lane must:

1. Read repository root `AGENTS.md` and route through `field-workflow` for QR/technician work.
2. Inspect current `main`, issue #436, PR #441 or its successor/integration state, and the current QR convergence/readiness docs.
3. Reuse existing QR renderer/dispatcher concepts before adding code.
4. Declare an isolated writer branch/worktree and owned scope before mutation.
5. Preserve unrelated work; do not "clean up" adjacent QR/dashboard/GUI code opportunistically.
6. If another active branch owns the same file/surface, do not compete. Either choose a non-overlapping artifact or wait/rebase after integration.
7. Keep live H&H evidence outside Git.
8. Do not QR-wrap a technician executable path that lacks its canonical CMD/runtime contract.
9. Keep copy/paste text complete even after QR is added.
10. Validate exact payload round-trip; QR-image generation alone is not proof.
11. Keep scanner acceptance, network-probe acceptance, endpoint ownership, and firmware readiness as separate proof levels.
12. Record new durable decisions here or in a superseding canonical plan; do not let chat-only decisions become hidden requirements.

## Isolation / contribution rule

Parallel contributions are welcome when they are additive and non-overlapping.

Agents may independently work on:

- endpoint-launcher contracts/tests;
- shared offline QR renderer extraction;
- QR round-trip tests;
- synthetic scanner fixtures;
- technician-document generation;
- evidence-schema validation.

They must not independently rewrite the same authority. When two lanes converge, reconcile through the canonical launcher/payload contract rather than copy-pasting one implementation into another.

## Firmware boundary

Nothing in this QR plan changes the firmware decision gate.

QR can reduce technician typing. It cannot establish:

- firmware ownership;
- entitlement;
- authoritative current firmware;
- authoritative target package;
- supported update method;
- rollback authority;
- successful update.

Those remain management-baseline requirements.

## Completion definition

This program is not complete until all of the following are true:

- copy/paste baseline path remains usable;
- remote endpoint has a tracked bounded CMD front door;
- QR uses the same canonical payload rather than a parallel command;
- renderer works offline;
- command payloads never silently truncate;
- synthetic round-trip tests pass;
- physical scanner acceptance is recorded;
- H&H live evidence remains external;
- documentation shows the baseline beside each command;
- repository changes are reviewed, validated, and integrated into current `main`.

Until then, the runbook's readable snippets remain the fallback authority.
