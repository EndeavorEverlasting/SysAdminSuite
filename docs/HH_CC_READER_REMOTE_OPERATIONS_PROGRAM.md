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

Parallel field/management lane. Required outputs:

- actual management owner/control plane;
- entitlement;
- authoritative current firmware;
- target package/version;
- supported remote update method;
- validation/rollback contract.

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
