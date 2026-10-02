# H&H CC Reader Remote Operations Program

Date: 2026-09-28
Status: P04 architecture + bounded endpoint-correlation prototype
Repository: `EndeavorEverlasting/SysAdminSuite`

## Program boundary

This program separates two goals that must not be conflated:

1. **Technician-workstation command distribution** can advance now through canonical SysAdminSuite launchers.
2. **CC-reader software/firmware deployment** remains blocked until an authoritative management/control-plane path, entitlement, package/version, supported method, and rollback/validation contract are proved.

Live H&H values and private external evidence remain outside tracked source.

## Daily bookmark contract

The external technician runbook owns the operator's dated re-entry point:

- STARTED: evidence-backed initial state;
- YESTERDAY: prior dated bookmark or explicit no-record state;
- TODAY: exact primary start and optional parallel start;
- TOMORROW: branch-dependent continuation.

Repository source does not depend on that private document. The durable repository contribution is the reusable command/program contract.

## Existing executable seam

`Probe-HHCCReader.cmd TARGET_IPV4 [EXPECTED_MAC]` is the canonical reader probe. It already owns:

- repository refresh;
- same-subnet gate;
- optional expected-MAC gate;
- bounded read-only neighbor/ICMP/Test-NetConnection/TCP evidence;
- ignored local JSON receipt;
- no reader mutation.

Do not create a second reader-probe engine.

## New endpoint-correlation seam

Prototype front door:

```text
Probe-HHCCReaderEndpoint.cmd READER_IPV4 REMOTE_ENDPOINT PORT APPROVAL_REF [EXPECTED-MAC]
```

Documentation-only example:

```text
Probe-HHCCReaderEndpoint.cmd 192.0.2.10 service.example.invalid 443 EVIDENCE-REF-001 AA-BB-CC-DD-EE-FF
```

Call stack:

```text
technician
  -> refresh current SysAdminSuite
  -> canonical Probe-HHCCReader reader same-subnet/device gate
  -> one observed REMOTE_ENDPOINT + one explicit PORT + one APPROVAL_REF
  -> Test-NetConnection
  -> ignored local endpoint JSON receipt
  -> terminal classification
```

The endpoint probe accepts one DNS hostname or IPv4 address, one explicit TCP port, and one non-secret approval/evidence reference token. It refuses CIDR/ranges/wildcards and does not scan. The approval reference is recorded for auditability; the launcher cannot independently validate the external human approval source.

TCP success proves only that the technician workstation reached that endpoint/port. It never proves PAX, AxiaMed, Bank of America, Payment Fusion, firmware ownership, or management authority.

## Success path

```text
reader evidence exposes endpoint + port
-> human approval + non-secret approval/evidence reference
-> reader same-subnet/device gate passes
-> bounded endpoint test completes
-> REMOTE_ENDPOINT_CORRELATION_COMPLETE
-> local receipt
-> external findings reconciliation
```

The terminal classification is valid even when `TcpTestSucceeded=false`; the observation completed.

## Failure paths

### No endpoint evidence

```text
no specific hostname/IP
-> do not run endpoint launcher
-> external no-endpoint branch
-> management-plane discovery
```

### Reader-network mismatch

```text
canonical Probe-HHCCReader
-> NETWORK_MISMATCH / NETWORK_AMBIGUOUS
-> STOP
-> do not interpret endpoint reachability
```

### Reader identity mismatch

```text
canonical Probe-HHCCReader
-> DEVICE_MISMATCH / DEVICE_UNRESOLVED
-> STOP
-> do not interpret endpoint reachability
```

### Endpoint input invalid

```text
CIDR/range/wildcard/unsupported host form
-> fail closed before Test-NetConnection
```

## P04 parallel decomposition

### P0 — bookmarks + copy/paste contract

External field-document lane. Preserve dated intent and complete copy/paste fallback.

### P1 — canonical reader-probe acceptance

Existing implementation. Issue #436 owns field acceptance.

### P2 — endpoint-correlation launcher

This successor lane, rebased semantically onto current `main`.

Owned files should remain isolated from PR #441 where possible:

- `Probe-HHCCReaderEndpoint.cmd`
- `scripts/Invoke-SasHhCcReaderEndpointProbe.ps1`
- `Tests/survey/test_hh_cc_reader_endpoint_probe_contracts.py`
- harness registry entries
- this program document

### P3 — QR transport

Existing `docs/HH_CC_READER_QR_BASELINE_PLAN.md` remains canonical. QR transports the exact launcher payload; it does not create a parallel command authority.

### P4 — technician-workstation distribution

Use the repository refresh/sealed-runtime path so authorized technician workstations receive current canonical launchers. Private cloud evidence is never a runtime dependency.

### P5 — management-plane discovery

Parallel field/management lane. Canonical ledger: `docs/HH_CC_READER_NETSTAT_BASELINE.md` section **Management-plane candidate disposition (2026-10-01)**.

Current state:

- operator-selected target remains `2.0.15.260522`;
- Kiosk4 device diagnostics are closed and must not be restaged for this discriminator;
- public/package search for exact build `2.0.15.260522` is exhausted without an authoritative mapping;
- H&H public Board material now identifies **Experian as the merchant-services vendor and credit-card-terminal provider as of September 2023**; current 2026 continuity is not yet proved;
- PAX public material links AxiaMed to A80 devices, remote Control Center management/update, and Payment Fusion; Bank of America acquired AxiaMed in 2021, making those names one downstream vendor-chain hypothesis rather than separate owners;
- mechanism discovery is now governed by `harness/api/hh-cc-reader-firmware-policy.json`; **management owner is an output, not a prerequisite supplied by a client or coworker**;
- **Payment Fusion Control Center / Healthcare Omni-Channel** is the strongest estate-facing management-surface match and is currently `CREDENTIAL_GATE`: current Bank of America documentation proves Control Center automatic terminal updating plus IngEstate remote terminal communication / terminal software repository capability, but this execution environment has no authorized H&H/AxiaMed/Payment Fusion read role;
- **PAXSTORE OTA firmware push** is the strongest firmware-delivery match and is currently `CREDENTIAL_GATE`: current PAX role documentation shows that **Readonly Firmware List + Terminal Management** is sufficient to inspect firmware/update and terminal state, while the observed public account lacks that estate scope; Full/write/push access is not required for discovery;
- the exposed local AxiaMed **TMS/NTMS/update** lane is `NOT_APPLICABLE`: the captured unlocked menu and Diagnostic exploration expose no local firmware/update control and must not be restaged;
- provider-managed automatic update is now `CREDENTIAL_GATE`: platform capability is proved by current Bank of America Control Center/IngEstate documentation and PAXSTORE policy-based distribution, while H&H enrollment, policy assignment, and target package mapping still require authorized read access;
- the exact reopen artifact remains the **Estate-authority evidence packet** defined in `docs/HH_CC_READER_NETSTAT_BASELINE.md`, but its `SOURCE_SURFACE` and `MANAGEMENT_OWNER` fields are populated from mechanism discovery rather than by asking a human to identify the owner;
- no additional reader diagnostics, owner-identification requests, or generic public package archaeology are required for P5.

Required outputs before P6:

- one named mechanism/control surface advances from `CREDENTIAL_GATE` to authorized read access for the representative A80 (Payment Fusion Control Center / IngEstate or PAXSTORE); discovery needs read-only firmware/update, terminal, policy/job, and package state only;
- representative-terminal record and authoritative current firmware;
- exact package/release mapping for target `2.0.15.260522` (or a surfaced conflict; do not silently substitute another build);
- supported remote assignment/update method;
- reboot/reconnect behavior;
- rollback/exception path;
- post-update acceptance contract.

#### PROVEN_PATH acceptance record

Canonical machine owner: `harness/api/hh-cc-reader-firmware-policy.json` section `proven_path_acceptance`.
Executable seam: `harness/api/hh_cc_reader_estate_authority.py`.

Promotion is proposed only when the evaluator returns `packet_state=COMPLETE`, `proposed_disposition=PROVEN_PATH`, and `mutation_authorized=false`. Package absence is recorded as `package_conflict=true` without silent target substitution. Local TMS/NTMS (`terminal-tms-pull`) remains ineligible.

#### Read-only estate evidence checklist

Canonical machine owner: `harness/api/hh-cc-reader-firmware-policy.json` section `readonly_estate_checklist` (12 ordered required observations). Operator work populates a sanitized observation packet; the evaluator scores the checklist and refuses forbidden discovery mutations.

#### P5 program design and call-stack prototype

**User outcomes:** bind the representative A80 to an authoritative estate surface; close P5 with a PROVEN_PATH acceptance record; keep mutation unauthorized until a separately authorized P6 pilot.

**Domain vocabulary:** MechanismCandidate, Disposition, EstateObservation, AuthorityPacket, ProvenPathAcceptanceRecord, ReadOnlyChecklistItem, PackageConflict, MutationAuthorization.

**Chosen seam (after comparison):** extend the existing firmware policy with acceptance/checklist records and a local evaluator (same pattern as evidence-provenance). Rejected alternatives: prose-only checklist (not executable); separate parallel registry (split authority with no gain while the firmware policy already owns mechanism dispositions).

**Success call stack:**

```text
OPERATOR_READONLY_OBSERVATION
  -> validate_session_and_role
  -> reject_forbidden_mutation
  -> bind_representative_terminal
  -> score_readonly_checklist
  -> assemble_authority_packet
  -> evaluate_proven_path_transition
  -> RESULT_PROVEN_PATH_MUTATION_DENIED
```

**Failure call stacks exercised by fixtures:** blocked authority; discovery mutation rejected; incomplete packet remains `CREDENTIAL_GATE`; ineligible TMS/NTMS rejected; package-absence conflict without substitution.

**Deployment operating model:** local offline Python evaluator only. No PaaS/container/Kubernetes tier is decision-relevant; live portal adapters remain future successor work behind credentials this runtime does not possess.


### P6 — one-reader deployment pilot

Blocked until P5 is proved. A future deployment command must be a separate explicitly authorized mutation lane and must not be inferred from endpoint reachability.

## Proof ceilings

- same-subnet proof != identical reader ACL/identity;
- reader probe != remote-service ownership;
- endpoint TCP success != management ownership;
- Connectivity Test green != firmware authority;
- workstation command distribution != reader deployment;
- repository tests != field acceptance;
- one-reader pilot != fleet readiness.

## Collision rules

- refresh current `main` and active PRs before mutation;
- The Netstat/baseline documentation lane is independently owned; do not compete on `docs/HH_CC_READER_FIELD_PROBE.md`, `docs/HH_CC_READER_NETSTAT_BASELINE.md`, or their field-probe contract tests;
- preserve `Probe-HHCCReader.cmd` as reader-probe authority;
- live H&H values never enter tracked source;
- additive agents may own endpoint launcher, QR, field evidence schema, or management discovery independently when file ownership does not collide;
- converge through command contracts, not copied implementations.
