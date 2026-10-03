# H&H CC Reader Remote Operations Program

Date: 2026-09-28
Status: P04 architecture + P5 evidence-state factoring + bounded endpoint-correlation prototype
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
Probe-HHCCReaderEndpoint.cmd READER_IPV4 REMOTE_ENDPOINT PORT APPROVAL_REF [EXPECTED-MAC] [NETWORK-ENVIRONMENT]
```

Documentation-only example:

```text
Probe-HHCCReaderEndpoint.cmd 192.0.2.10 service.example.invalid 443 EVIDENCE-REF-001 AA-BB-CC-DD-EE-FF HOSPITAL_GUEST_SHARED
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


#### P5 evidence-state semantics — operator-facing and agent-facing

P5 must not collapse every unresolved field into the generic word `UNPROVEN`. Use the strongest precise evidence state:

| Evidence state | Meaning | Typical importance |
| --- | --- | --- |
| `SETTLED_POLICY` | Decision is already established by accepted repository/client evidence and must not be reopened without stronger superseding evidence. | CRITICAL |
| `IMPLEMENTED_VALIDATED` | Repository seam exists and its owning tests/CI have passed at the cited revision. | CRITICAL |
| `LIVE_VALUE_NOT_CAPTURED` | The value must come from an authenticated estate observation and has not yet been recorded. | CRITICAL or USEFUL |
| `DERIVABLE_NOT_POPULATED` | The system can truthfully generate/populate the value from already-known inputs; operator input is unnecessary. | DERIVABLE |
| `UNKNOWN_SURFACE_NOT_EXPOSED` | The authenticated surface was inspected but did not expose the requested datum. This is evidence, not a request to keep hunting indefinitely. | USEFUL |
| `OPTIONAL_NON_BLOCKING` | Useful context that is not required to advance the current acceptance gate. | NEGLIGIBLE |
| `INTERACTIVE_AUTH_REQUIRED` | Only the credential/MFA boundary prevents the next observation. | CRITICAL |

Operator-facing status matrices should also classify importance as `CRITICAL`, `USEFUL`, `DERIVABLE`, or `NEGLIGIBLE`. Raw schema completeness is not equivalent to operator importance.

#### P5 terminology contract

These two questions are different and MUST NOT be conflated:

1. **Planning target selection:** Is `2.0.15.260522` the current firmware planning target?
   **State:** `SETTLED_POLICY` — YES. It is the repository's default planning candidate from the client-accepted set.
2. **Estate package exposure:** Does the authenticated H&H management surface expose a package corresponding to `2.0.15.260522` for the representative estate/terminal?
   **State:** `LIVE_VALUE_NOT_CAPTURED` until observed.

A user/operator saying “yes, use 2.0.15.260522” settles question 1. It does not fabricate question 2.

`package_release_id` means the stable identifier, if any, that the authenticated management surface associates with the package/release/software-repository record corresponding to `2.0.15.260522`. The portal may label it Release ID, Package ID, Firmware ID, Software ID, Repository ID, Version ID, List ID, or another equivalent. It is **not** another firmware version and it is **not** a pre-known universal PAX identifier.

Do not invent a release/package identifier. If the authenticated surface exposes the target package but exposes no separate stable identifier, record that observation explicitly as `UNKNOWN_SURFACE_NOT_EXPOSED` and route the evaluator contract through the conditional compatibility-repair lane below. The operator must not be sent on an indefinite search for a field the surface may not provide.

Current public evidence proves the management capabilities but does not define a universal firmware-package identifier contract:

- Bank of America Healthcare Omni-Channel integrations: Control Center provides terminal management and automatic terminal updating; IngEstate provides remote terminal communication and a terminal software repository: https://developer.merchant-services.bankofamerica.com/healthcareomnichannel/integrations
- Bank of America Payment Fusion Settings API: PFCC manages terminal settings/applications/gateway data and exposes stable identifiers for several management objects, but the public API does not document the private firmware-repository record shape used by the authenticated estate UI: https://developer.merchant-services.bankofamerica.com/healthcareomnichannel/api?apiDef=settings
- PAX MAXSTORE: remote estate management supports application, parameter, and firmware distribution/OTA management, but the public product page does not establish a universal firmware “release ID” field: https://www.paxtechnology.com/maxstore

#### P5 lane versus evaluator

P5 is the **read-only management-plane discovery lane**. The evaluator is P5's deterministic classifier, not the entire P5 activity.

Canonical flow:

```text
authenticated read-only management observation
  -> sanitized authority packet
  -> Evaluate-HHCCReaderEstateAuthority.cmd
  -> harness/api/hh_cc_reader_estate_authority.py
  -> classification + next gate + ignored local receipt
```

The evaluator implementation is already integrated and CI-validated. “Evaluator not yet run against the completed H&H packet” must never be reported as “evaluator unproven.”

#### P5 field-ownership matrix

| Field / decision | Evidence state before live login | Importance | Owner / population rule |
| --- | --- | --- | --- |
| target firmware `2.0.15.260522` | `SETTLED_POLICY` | CRITICAL | repository policy; do not ask operator again |
| `mechanism_id=payment-fusion-control-center` | `SETTLED_POLICY` | CRITICAL | repository policy / current mechanism order |
| `current_disposition=CREDENTIAL_GATE` | `DERIVABLE_NOT_POPULATED` | DERIVABLE | agent/tooling |
| mutation intent/actions = none | `DERIVABLE_NOT_POPULATED` | DERIVABLE | agent/tooling for read-only lane |
| `authority_packet_id` | `DERIVABLE_NOT_POPULATED` | NEGLIGIBLE | generate non-secret session identifier |
| `reader_identity_ref` | `DERIVABLE_NOT_POPULATED` after A80 selection | DERIVABLE | generate sanitized alias from external evidence index |
| authenticated estate access | `INTERACTIVE_AUTH_REQUIRED` | CRITICAL | operator login/MFA; then observation |
| minimum read role | `LIVE_VALUE_NOT_CAPTURED` | CRITICAL | authenticated surface |
| representative A80 present | `LIVE_VALUE_NOT_CAPTURED` | CRITICAL | authenticated surface |
| current A80 firmware value | `LIVE_VALUE_NOT_CAPTURED` | CRITICAL | authenticated terminal record |
| target package exposed | `LIVE_VALUE_NOT_CAPTURED` | CRITICAL | authenticated package/update view |
| package/release record reference | `LIVE_VALUE_NOT_CAPTURED` | USEFUL | surface's own stable identifier if exposed |
| assignment/update affordance | `LIVE_VALUE_NOT_CAPTURED` | USEFUL | observe surface terminology; never invoke |
| reboot/reconnect behavior | `LIVE_VALUE_NOT_CAPTURED` | USEFUL | same authority or linked authoritative documentation |
| rollback/cancel/exception path | `LIVE_VALUE_NOT_CAPTURED` | USEFUL | same authority or linked authoritative documentation |
| post-update acceptance indication | `LIVE_VALUE_NOT_CAPTURED` | USEFUL | same authority or linked authoritative documentation |
| checklist booleans | `DERIVABLE_NOT_POPULATED` | DERIVABLE | derive from captured observations; operator should not hand-manage booleans |
| packet/evaluator classification | `DERIVABLE_NOT_POPULATED` | DERIVABLE | canonical evaluator |
| P6 authorization | not reached | CRITICAL | separate successor gate; never inferred from P5 |

#### P04 successor decomposition for P5 convergence

| Lane | Runtime / owner | Scope | Dependency | Artifact / proof | Completion gate |
| --- | --- | --- | --- | --- | --- |
| P5-A — baseline evaluator receipt | LOCAL_AGENT_RUNTIME | Refresh repo, resolve existing external staged packet if present, run the canonical evaluator exactly once without fabricating live evidence. | current main + staged packet | ignored local evaluator receipt + exact classification/next gate | current packet state is known |
| P5-B — deterministic packet normalization | LOCAL_AGENT_RUNTIME | Populate settled/derivable fields via `Normalize-HHCCReaderEstatePacket.cmd`, generate safe aliases/packet id, derive checklist flags from actual evidence, and reduce operator worksheet to genuine live observations. | P5-A | external sanitized packet + minimal operator worksheet | no derivable/bookkeeping item remains operator homework |
| P5-C — Payment Fusion observation | OPERATOR_OR_PHYSICAL_RUNTIME | Complete authorized login/MFA and observe only the genuine live fields in the matrix. No write actions. | P5-B worksheet + authorized credentials | external observation notes/screenshots + sanitized values | representative A80 and decision-relevant live fields observed or explicitly not exposed |
| P5-D — conditional release-reference compatibility repair | LOCAL_AGENT_RUNTIME | Only if P5-C proves target package exposure but no stable package/release/list identifier is exposed: repair the machine contract so the explicit absence can be represented without inventing an identifier, with negative/positive fixtures and focused regression. | P5-C explicit no-identifier evidence | bounded code/schema/test change + green focused/registered gates | real surface semantics can be represented truthfully |
| P5-E — final P5 evaluation | LOCAL_AGENT_RUNTIME | Update external packet from P5-C (and P5-D if required), rerun canonical evaluator, preserve receipt and exact next gate. | P5-C; P5-D when applicable | COMPLETE/PROVEN_PATH receipt or exact remaining blocker | P5 disposition is no longer ambiguous |
| P6 — one-reader pilot | OPERATOR + LOCAL_AGENT_RUNTIME | Separate mutation-authorized pilot design/execution. | P5-E PROVEN_PATH + explicit pilot authorization | pilot plan, mutation proof, rollback/acceptance evidence | separately authorized pilot completes |

P5-A and P5-B may proceed before the interactive session. P5-C is the only lane that crosses the credential/MFA boundary. P5-D is conditional and must not be preemptively implemented merely because the current schema is stricter than the public evidence. P5-E resumes immediately when its dependencies are satisfied.

#### P5 local-agent acceptance contract

The local implementation agent must:

1. refresh current default-branch/provider truth before execution;
2. run the current staged packet through `Evaluate-HHCCReaderEstateAuthority.cmd` and preserve the receipt;
3. classify every remaining field using the evidence-state and importance vocabularies above;
4. automatically populate every truthful settled/derivable field instead of asking the operator;
5. produce a minimal operator worksheet containing only genuinely live observations;
6. never ask again whether `2.0.15.260522` is the intended planning target unless stronger superseding evidence changes repository policy;
7. never invent a release/package identifier;
8. treat explicit “target package visible but no separate identifier exposed” as evidence that may trigger P5-D, not as operator failure;
9. rerun the same canonical evaluator immediately after live observations are supplied;
10. report proof states separately: evaluator implemented, CI validated, integrated, baseline packet evaluated, live observations captured, completed packet evaluated, PROVEN_PATH established, P6 authorized.

The implementation handoff should prefer precise phrases such as `LIVE_VALUE_NOT_CAPTURED`, `DERIVABLE_NOT_POPULATED`, `IMPLEMENTED_VALIDATED`, `SETTLED_POLICY`, `INTERACTIVE_AUTH_REQUIRED`, `OPTIONAL_NON_BLOCKING`, and `UNKNOWN_SURFACE_NOT_EXPOSED` over generic `UNPROVEN`.

#### PROVEN_PATH acceptance record

Canonical machine owner: `harness/api/hh-cc-reader-firmware-policy.json` section `proven_path_acceptance`.
Executable seam: `harness/api/hh_cc_reader_estate_authority.py`.

Promotion is proposed only when the evaluator returns `packet_state=COMPLETE`, `proposed_disposition=PROVEN_PATH`, and `mutation_authorized=false`. Package absence is recorded as `package_conflict=true` without silent target substitution. Local TMS/NTMS (`terminal-tms-pull`) remains ineligible.

#### Read-only estate evidence checklist

Canonical machine owner: `harness/api/hh-cc-reader-firmware-policy.json` section `readonly_estate_checklist` (12 ordered required observations). Operator work populates a sanitized observation packet; the evaluator scores the checklist and refuses forbidden discovery mutations.

Operator session procedure (not a second authority): `docs/HH_CC_READER_P5_READONLY_SESSION_RUNBOOK.md`. Fill-in template: `docs/examples/hh-cc-reader-proven-path-authority-packet.template.json`.

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

## 2026-10-02 P04 round-trip and batch extension

Canonical execution plan extension: docs/HH_CC_READER_FIRMWARE_ROUNDTRIP_BATCH_PLAN.md

That plan preserves this program as the parent authority while adding the operator-required progression: exact Kiosk4 baseline lock -> governed outdated classification -> restoration proof before mutation -> one-reader target update -> verified restoration to starting state -> dashboard/CSV batch adapter -> reversible batch executor -> SysAdminSuite-style HTML receipts and read-back reconciliation into the existing CC Reader Technician Dashboard.

The existing CC Reader Technician Dashboard remains the operational tracker. New batch plans, restore plans, summaries, and HTML receipts are execution artifacts/adapters, not replacement trackers.

