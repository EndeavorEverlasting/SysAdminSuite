# Finding continuity — one source event, governed destinations

**Owner:** SysAdminSuite, `harness/api/sas_finding_ingest.py`, under existing
`sas-operational-publication-boundary/v1`. **Status:** local private event
intake implemented. External adapters / unattended event capture **not implemented**.

## Goal and scope

When an agent, workstation tool, or technician makes a meaningful new observation,
**record it once**, with its proof level, before writing a second summary or
starting a new probe. The single private event may feed multiple **independent**
destinations. No downstream destination can alter the authoritative observation.

| Surface | Authority | Implemented behavior | Completion claim |
| --- | --- | --- | --- |
| SAS private evidence | machine-/operator-local event | private event + hash receipt, replay detection | `PERSISTED_LOCAL` only |
| Reusable public SAS | versioned code/contracts, not machine facts | constant-only publication candidate | `CANDIDATE`, **never** auto-committed |
| Operator-controlled Drive/elsewhere | private workspace under operator's account | connector adapter not included in SAS | `NOT_CONFIGURED` until independently verified |
| Chat/agent observation | chat/photo/agent runtime | an authorized agent must submit a typed event | no autonomous chat access from SAS |

A successful local write does **not** prove Drive update, public Git publication,
physical repairs, installed tools, or a target state. Publication progression must
follow `harness/api/operational-publication-boundary.v1.json`.

## Event producer contract

Submit exactly one `sas-finding-event/v1` JSON object per observation. This is an
offline producer; it never signs in to Drive, opens URLs, runs a device probe,
changes a machine, or pushes Git. `event_id` is a stable opaque id; reuse it when
retrying the **same** event. Reusing it for changed evidence must fail `CONFLICT`.
Use a new event for a materially newer observation; do not rewrite history.

```json
{
  "schema_version": "sas-finding-event/v1",
  "event_id": "synthetic-finding-0001",
  "logical_subject_key": "fictional-workstation-01",
  "event_type": "FINDING_RECORDED",
  "occurred_at": "2026-10-09T20:00:00-04:00",
  "evidence_ref": "private-evidence-reference-not-for-publication",
  "category": "hardware",
  "proof_level": "operator_reported",
  "privacy": "private_operational",
  "finding": {
    "summary": "A fictional laptop may require a cooling inspection",
    "details": "No internal inspection or temperature measurement has been performed"
  }
}
```

Use `python harness/api/sas_finding_ingest.py --input PATH` from an
**already refreshed and validated development checkout**, or pipe the JSON via
`--input -` from an authorized agent. This is an agent/API intake, not a new
technician field command or a substitute for the canonical `sas` launcher.
The optional `--output-root` is a private evidence root for fixtures or
explicit operator-selected locations. Otherwise outputs go to the current
user's local SAS evidence area **outside tracked Git**:

- Windows: `%LOCALAPPDATA%\SysAdminSuite\Evidence\Findings`
- Linux: `~/.local/share/SysAdminSuite/Evidence/Findings`

Outputs: `private/<event_id>.json` (entire private event),
`candidates/<event_id>.json` (fixed allowlisted categories/proof levels and
constant reusable text only), `receipts/<event_id>.json` (hash, outcome,
publication state, no raw evidence). Candidate files **remain local and private**
until separately reviewed, implemented as a generalized change, validated,
and committed in an ordinary PR. Private event identifiers, serials, model/
host identity, photos, logs, local paths, private Drive identifiers, URLs,
free-text summaries and timestamps never enter public candidate payloads.

**On every finding:** (1) classify the observation vs inference vs proof;
(2) emit the event with an existing evidence reference or a `no-artifact-yet`
private reference; (3) use the receipt to avoid repeated transcription;
(4) update the private external workspace through an authorized connector
when available; (5) promote reusable *behavior* to Git only through review;
(6) record separate readback proofs. Never skip local preservation because
Drive/Git publication is unavailable. Never retry a physical probe solely
because publication failed.

## Public/private boundary

- SysAdminSuite is public. **No** raw device snapshots, live serials, IPs,
  MACs, hostnames, personal file locations, operator images, or restricted
  records in Git, Issues or PR comments.
- Existing `docs/EXTERNAL_FIELD_EVIDENCE.md` forbids SAS from depending on or
  crawling an arbitrary cloud provider. An optional external connector may
  subscribe to *approved* local events without expanding SAS's authority.
- External publish state starts at `NOT_CONFIGURED`. Do **not** relabel a
  generated publication candidate as pushed, merged, or Drive-synchronized.
- Repository contributions must be reusable patterns, contracts, validators,
  tests, launchers, or adapter interfaces — **not** a public log of private
  observations. The ingest routine will not auto-push even if credentials exist.
- Machine-specific facts are recoverable through the operator's private
  evidence source, not by searching a public repository for a machine alias.
- The code intentionally contains no OAuth secrets, Git push code, cloud API,
  chat polling, file watchers, or target contact.

## Validation

```text
python Tests/survey/test_sas_finding_ingest.py
python -m py_compile harness/api/sas_finding_ingest.py
```

A green result proves local fixture ingestion, idempotency, conflict denial,
private/public splitting, failure isolation, and safe CLI output only.
It does **not** prove unattended ingestion of future conversations, Drive
synced state, Windows field behavior, or hosted Git integration.

## Next integration slice

An event-producing adapter from a real source (assistant bridge, permitted
workstation capture, or operator workflow) must invoke the producer for each
new finding and persist the associated private source reference. A separate
operator-authorized connector adapter should write/update a private Drive
artifact and verify revision/readback. An optional repository agent can
turn a reviewed candidate into a bounded PR with validators. These are
independent, recoverable stages; unavailable providers leave local admission
untouched. Never retype the event into multiple ledgers.
