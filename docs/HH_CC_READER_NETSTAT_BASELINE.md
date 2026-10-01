# Health & Hospitals CC Reader Netstat Baseline and Firmware Decision Gate

## Status

**Discovery state:** quiescent at estate-authority boundary (device diagnostics closed; package/entitlement incomplete).
**Firmware procedure:** not yet proven; mutation not authorized.
**Field evidence authority:** operator-managed external evidence workspace.
**Repository role:** reusable parameterized procedure, safety boundaries, and acceptance semantics only.
**Reopen artifact:** Estate-authority evidence packet (below). Do not restage reader diagnostics for this gap.

This document intentionally contains no live H&H target IP, MAC, credential, screenshot, private external-workspace identifier, or raw field output.

## Client inventory firmware evidence

The client-provided inventory includes a field named `Active Outdated`. Treat that field as client estate classification evidence, not as a vendor release-feed label.

Current interpretation:

- `Active Outdated = Yes` means the client source classifies the row as active-outdated and requiring remediation.
- `Active Outdated = No` means the client source does not classify the row as active-outdated. Firmware versions observed on those rows are therefore **client-accepted baseline candidates**.
- The two distinct firmware versions currently observed under `Active Outdated = No` are `2.0.14.221110` and `2.0.15.260522`.
- `2.0.14.221110` creates an explicit ambiguity: it is numerically older than the selected target yet is still accepted by the client classification. The reason may be policy, hardware/release compatibility, stale source data, or another estate-specific rule; none is proven yet. Preserve the discrepancy instead of rewriting it away.
- This client signal does **not** prove vendor-global latest firmware, package availability in the applicable management tenant, entitlement, or authorization to update.

The machine-readable authority for these semantics is `harness/api/hh-cc-reader-firmware-policy.json`, enforced by `harness/validators/validate-hh-cc-reader-firmware-policy.py`.

## Operator-selected firmware target

**Default target firmware:** `2.0.15.260522`.

The default is not an arbitrary version string. Under the current client evidence set, the harness selects the **highest numeric observed client-accepted candidate** by comparing each dot-separated component as an integer tuple. Of `2.0.14.221110` and `2.0.15.260522`, that produces `2.0.15.260522`.

Carry `2.0.15.260522` forward in reports, pilot planning, and management-path discovery unless one of the policy's explicit supersession conditions is met: stronger H&H estate-specific management/owner evidence, a revised client source that changes the accepted candidate set, or an explicit operator target change.

This is a **fleet-level planning candidate**, not a site-authorized execution target. Organization and site/hospital are independent profile authorities: resolve the specific H&H site before selecting mutation behavior. An independently operated, unknown, ambiguous, conflicting, or unsupported site remains `DISCOVERY_REQUIRED` and must not inherit the fleet candidate as execution authority.

Evidence semantics remain strict:

- `2.0.15.260522` is the current **default planning target**, not proof that a particular PAXSTORE/processor tenant has exposed or authorized the corresponding package.
- `Active Outdated = No` is not vendor-global proof that every associated firmware is current; it is client estate evidence that those rows are not presently classified as active-outdated.
- Discovery work should seek the exact package/release mapping for `2.0.15.260522`, the owning management plane, and the supported assignment method.
- Do not silently replace the target with another version because a vendor portal, generic guide, coworker device, or agent proposes a different build. Surface the conflict and reconcile it against the machine policy and stronger estate-specific evidence.
- Firmware mutation remains gated on authoritative package mapping, a supported update method, and one controlled representative-reader pilot.

## What changed on 2026-09-28

The built-in A80 Netstat surface is now known to require a multi-frame capture rather than a single screenshot.

Current field evidence establishes:

- Netstat begins with an `Active Internet connections (w/o servers)` heading and continues beyond one screen.
- The captured output includes Android/Linux socket rows such as `DGRAM`, `SEQPACKET CONNECTED`, and `/dev/socket/...` paths.
- The current discovery frames do **not** expose a remote management IP/port clearly enough to classify one as proved.
- The device-side Connectivity Test separately exposes service checks that include terminal-management/transaction/polling functions, Payment gateway, Diagnostic service, PAX Store, and **PAX Store Push Service Primary (443)** plus another truncated PAX push entry.
- A Connectivity Test label is a correlation candidate, not proof that the same endpoint is visible in Netstat or that the service owns firmware for this estate.

## Public PAXSTORE capability evidence (does not close the H&H management baseline)

Public PAX Technology documentation materially narrows the control-plane hypothesis:

- PAX describes PAXSTORE as a cloud platform for managing payment devices, including remote application and firmware updates.
- The PAXSTORE Reseller Admin Guide states that terminals communicate with PAXSTORE through the internet, that firmware updates may be pushed to selected terminals, and that reseller administrators can push firmware.
- The same guide exposes a Firmware List containing A80-compatible firmware packages, confirming that A80 firmware is represented in the PAXSTORE management plane.
- PAX North America support guidance also routes customer firmware-update requests through Technical Support. That support-mediated path can coexist with reseller/administrator firmware controls; it is evidence that entitlement and role matter, not evidence that every terminal owner has self-service firmware authority.

Public references:

- https://www.pax.us/marketplace/
- https://www.pax.us/paxstore-knowledge-base/
- https://faqs.pax.us/wp-content/uploads/2020/05/PAXSTORE-Reseller-Admin-Guide_v1.0.pdf
- https://www.pax.us/support/faq/

### Decision consequence

The observed device-side label **PAX Store Push Service Primary (443)** is therefore materially consistent with a PAXSTORE phone-home/control-plane path. It is still only a correlation candidate for this H&H estate.

This evidence does **not** prove:

- which PAXSTORE reseller/merchant/processor tenant owns these readers;
- whether the H&H deployment is enrolled for firmware management;
- which operator or support organization has the required role/entitlement;
- the authoritative current or target firmware package/version;
- that the observed push-service check is the exact transport used for a firmware task on this estate.

For the current Kiosk4 evidence set, `START_TEST` and the built-in Connectivity Test are closed by preserved prior provenance, with `REMOTE_ENDPOINT_CANDIDATE=NONE`. Do **not** schedule or repeat another physical reader window merely to obtain a newer `RUN_ID` or to keep searching for an endpoint. Advance to the firmware management baseline. The endpoint-correlation launcher remains dormant unless preserved/current evidence directly exposes one concrete endpoint+port or a documented revalidation trigger invalidates the prior discriminator.

The management baseline can be closed only by authoritative estate-specific evidence such as the applicable PAXSTORE/processor/reseller terminal record, an approved support case or owner confirmation, or another supported management plane that directly identifies the reader and the allowed firmware task. Coworker anecdote, generic PAXSTORE capability, or a successful Connectivity Test is not sufficient.

## Public H&H merchant-services ownership evidence (narrows P5; does not prove firmware authority)

A public NYC Health + Hospitals Information Technology Committee packet dated September 11, 2023 materially narrows the estate ownership question. In the Experian background presented to the Board, H+H states that **Experian was its current merchant-services vendor, provided the credit-card terminals, and provided the connection used to process credit-card transactions between NYC Health + Hospitals and the bank**.

That is stronger than the prior generic processor/ISV hypothesis list because it is H&H estate-specific evidence. Its proof ceiling is still limited: the statement is dated 2023 and does not identify the A80 model, the 2026 support owner, PAXSTORE enrollment, firmware entitlement, or package `2.0.15.260522`.

The broader public vendor chain is now coherent rather than four unrelated guesses:

- Experian Health currently markets PaymentSafe as its point-of-service patient-payment solution using PCI-compliant card devices.
- PAX's own 2020 AxiaMed partnership announcement states that AxiaMed offered PAX A920 and **A80** devices to healthcare clients, that AxiaMed's cloud Control Center could remotely update/manage PAX Android devices, and that **Payment Fusion** was AxiaMed's SaaS healthcare-payments platform.
- AxiaMed was acquired by Bank of America in 2021. Bank of America currently exposes a Healthcare Omni-Channel Gateway/developer surface for healthcare payment integrations.
- These public relationships make **Experian -> AxiaMed/Payment Fusion -> Bank of America -> PAX A80** a materially supported vendor-chain hypothesis, not proof that this exact H&H reader is enrolled in that chain or that any member owns its firmware package.

Public references:

- https://hhinternet.blob.core.windows.net/uploads/2023/09/202309-it.pdf
- https://www.experian.com/healthcare/products/payment-tools/secure-patient-healthcare-payment-solutions
- https://www.pax.us/about/press-room/pax-technology-inc-and-axiamed-partner-to-provide-optimal-healthcare-payment-experience-with-android-based-a920-a80/
- https://www.nasdaq.com/press-release/bank-of-america-acquires-axia-technologies-inc.-2021-04-02
- https://developer-prod1.merchant-services.bankofamerica.com/

### Decision consequence

- **Experian is now the strongest documented H&H merchant-terminal relationship**, with the important temporal qualifier **as of September 2023**. Current 2026 continuity remains unproved until an H&H owner or Experian account/support record confirms it.
- **AxiaMed, Payment Fusion, and Bank of America are no longer independent free-floating ownership guesses.** They are a linked downstream healthcare-payments chain that may explain the PAX A80 estate, but H&H-specific deployment is still unproved.
- **PAXSTORE and AxiaMed Control Center remain competing/possibly layered device-management hypotheses.** Public evidence does not establish which one exposes firmware `2.0.15.260522` for the representative H&H A80.
- **Agilant remains an implementation/support hypothesis only.** No public evidence found in this pass establishes Agilant as the merchant-services, PAX tenant, processor, or firmware authority.
- The first authority request should therefore target the **H&H owner of the Experian merchant-services/terminal relationship or the corresponding Experian account/support owner** and ask which management surface owns the representative A80 record, whether that surface is PAXSTORE, AxiaMed/Bank of America Control Center/Gateway, or another plane, and whether it exposes package `2.0.15.260522`.

## Management-plane candidate disposition (2026-10-01)

This section is the durable P5 discovery ledger for firmware target `2.0.15.260522`. It does not authorize mutation.

Access is classified independently of capability using exactly these labels:

- `PROVEN_ACCESS` — a live estate login or owner-confirmed entitlement for this surface is in evidence
- `ACCESS_NOT_PROVEN` — the surface may exist, but no credentialed session or owner confirmation is in evidence
- `NOT_APPLICABLE` — the surface cannot satisfy the package/assignment discriminator for this estate
- `BLOCKED_AUTHORITY` — the surface is identified, but the next operation is blocked pending a named authority or credential

Current dispositions from exhausted provider-neutral evidence:

- **PAXSTORE terminal App & Firmware / Push Firmware** — capability proven by public PAXSTORE documentation and materially consistent with the device-side PAX Store Push Service Primary (443) correlation. Estate tenant, enrollment, and package exposure remain unknown. Access: `ACCESS_NOT_PROVEN`. Package `2.0.15.260522`: unresolved. Strongest capability candidate.
- **PAXSTORE reseller administrator firmware list / push** — capability proven by the public Reseller Admin Guide (A80 firmware list and push-to-terminal/group). Which reseller owns the H&H estate remains unknown. Access: `ACCESS_NOT_PROVEN`. Package `2.0.15.260522`: unresolved.
- **PAX North America Technical Support Analyst path** — capability proven as a documented firmware-update route in current PAX NA FAQ material. No open estate support case or analyst confirmation is in evidence. Access: `ACCESS_NOT_PROVEN`. Package `2.0.15.260522`: unresolved.
- **Experian Health merchant-services / terminal relationship** — H&H's September 2023 IT Committee packet states that Experian was the current merchant-services vendor, provided the credit-card terminals, and provided the processing connection between H&H and the bank. This is estate-specific historical ownership evidence, not current 2026 entitlement proof. Access: `ACCESS_NOT_PROVEN`. Current relationship continuity: unresolved. Package `2.0.15.260522`: unresolved. **Strongest documented owner-contact candidate.**
- **AxiaMed / Payment Fusion / Bank of America downstream chain** — PAX publicly documents A80/A920 availability to AxiaMed healthcare clients, AxiaMed Control Center remote device management/update capability, and Payment Fusion as AxiaMed's platform; Bank of America acquired AxiaMed in 2021. This materially supports a downstream payment-device chain but does not prove the representative H&H A80 is enrolled there. Access: `ACCESS_NOT_PROVEN`. Package `2.0.15.260522`: unresolved.
- **Agilant implementation/support hypothesis** — no public evidence found in this pass establishes Agilant as the H&H merchant-services owner, PAX tenant/reseller, processor, or firmware authority. Access: `ACCESS_NOT_PROVEN`. Package `2.0.15.260522`: unresolved.
- **Local A80 admin / Diagnostic Test firmware controls** — field exploration found no proved local firmware-update control. Access: `NOT_APPLICABLE` for remote package assignment.
- **Device Connectivity Test / Netstat alone** — Kiosk4 discriminators are closed by prior provenance (`START_TEST` / Connectivity / `REMOTE_ENDPOINT_CANDIDATE=NONE`). Access: `NOT_APPLICABLE` for package/entitlement resolution. Do not restage another reader window for this gap.
- **Generic public search for exact build `2.0.15.260522`** — exhausted on 2026-10-01 with no authoritative public PAX package/release mapping. Access: `NOT_APPLICABLE`. Cannot close the estate package gate.

**Strongest next authority gate:** confirm whether Experian still owns the H&H merchant-services/terminal relationship in 2026 and, through the H&H relationship owner or Experian account/support owner, identify the exact management surface holding the representative A80 record. Then determine whether that surface is PAXSTORE, AxiaMed/Bank of America Control Center/Gateway, or another plane and whether it exposes the exact package/release corresponding to `2.0.15.260522`, plus the supported assignment/update method, expected reboot/reconnect behavior, rollback/exception procedure, and post-update acceptance checks.

That confirmation must come from the applicable PAXSTORE/processor/reseller terminal record, an approved support case, or named owner confirmation. Until that gate is crossed, leave every credentialed surface at `ACCESS_NOT_PROVEN` and do not assign, push, sideload, or otherwise mutate firmware.

When an exact management surface is identified and the next operation genuinely requires an operator credential or login, stop at that precise boundary and record: exact surface, why it is the strongest candidate, exact evidence needed after login, smallest operator action required, and expected artifact/proof.

## Estate-authority evidence packet (required to reopen firmware work)

The H&H firmware lane is **quiescent** at an external authority boundary. Do not manufacture more repository archaeology, public PAX searching, OpenCode probing, Netstat/START TEST restaging, Connectivity restaging, or endpoint hunting for this gap.

The first authority request should target the **H&H owner of the Experian merchant-services/terminal relationship or the corresponding Experian account/support owner** (strongest documented owner-contact candidate as of the September 2023 Board evidence; 2026 continuity still unproved). That contact is how the packet's `SOURCE_SURFACE` and `MANAGEMENT_OWNER` fields get filled — it is not itself a firmware-mutation authorization.

The lane reopens only when one estate-specific evidence packet is captured in the operator-managed external evidence workspace and indexed to a non-secret `AUTHORITY_PACKET_ID`. Live terminal IDs, credentials, portal URLs with session tokens, screenshots containing restricted data, and private workspace identifiers stay external. Tracked source records only the packet schema, discriminator outcomes, and sanitized classifications.

### Packet identity

Record once per representative reader / management lookup:

```text
AUTHORITY_PACKET_ID=<non-secret packet id>
READER_IDENTITY_REF=<external index key only; no live IP/MAC/serial in Git>
TARGET_FIRMWARE_PLANNING_CANDIDATE=2.0.15.260522
PACKET_CAPTURE_UTC=<ISO-8601>
EVIDENCE_CUSTODIAN=<role or team, not a secret>
SOURCE_SURFACE=<one of the candidate surfaces below>
ACCESS_STATE=PROVEN_ACCESS|ACCESS_NOT_PROVEN|BLOCKED_AUTHORITY
```

### Required answers (all seven)

The packet is incomplete unless every field below is either answered from the named management surface or explicitly marked `UNKNOWN` with a reason:

1. `MANAGEMENT_OWNER` — who owns/manages the terminal record (tenant / reseller / processor / support authority name as shown on that surface)
2. `PACKAGE_EXPOSED_FOR_2_0_15_260522` — `YES` | `NO` | `UNKNOWN` whether that surface exposes `2.0.15.260522`
3. `PACKAGE_RELEASE_ID` — exact package/release/firmware-list identifier that maps to `2.0.15.260522`, or `NONE_OBSERVED`
4. `ASSIGNMENT_METHOD` — how firmware is assigned/pushed (for example terminal push, group push, support-mediated job); quote the surface's own verb when possible
5. `REBOOT_RECONNECT_BEHAVIOR` — required reboot/reconnect/wait behavior during/after the update
6. `ROLLBACK_EXCEPTION_PATH` — rollback, cancel, or exception procedure if the job fails or must be reversed
7. `POST_UPDATE_ACCEPTANCE` — what observation proves success (exact version string on device and/or management record, plus required operational checks)

### Minimum artifact set

For the chosen `SOURCE_SURFACE`, preserve externally (not in Git):

- one terminal-record view that binds the representative reader to the management owner;
- one firmware/package view that shows either the `2.0.15.260522` mapping or an explicit absence;
- the assignment/push affordance or support-case instruction that would initiate an update;
- written reboot/reconnect and rollback/exception text from that same authority;
- the post-update acceptance criterion stated by that authority.

### Close / fail rules

- Packet **COMPLETE** only when all seven answers are filled and `ACCESS_STATE=PROVEN_ACCESS` for the named surface.
- If the surface is identified but login/entitlement is missing, set `ACCESS_STATE=BLOCKED_AUTHORITY` and stop at that exact login boundary — do not widen into reader diagnostics.
- If `PACKAGE_EXPOSED_FOR_2_0_15_260522=NO`, record the conflict against the planning candidate; do not silently substitute another build.
- A complete packet authorizes **management-baseline closure review** only. It still does **not** authorize fleet mutation; P6 remains a separately authorized one-reader pilot.

## Evidence linkage contract

Every controlled evidence window must have one non-secret `RUN_ID` assigned **before** the Identity gate. The operator-managed evidence index must bind that `RUN_ID` to exactly one reader identity and record the window start/end timestamps.

The same `RUN_ID` must label or index:

- every Netstat BASELINE / START_TEST / DURING_TEST / POST_TEST frame from that window;
- the paired Connectivity Test capture;
- the canonical workstation probe receipt **path and receipt timestamp**;
- any bounded endpoint-correlation receipt path produced from evidence in that window;
- operator notes that interpret a delta or unknown.

Do not combine artifacts under one `RUN_ID` when the reader identity changes, a later diagnostic window starts, or provenance cannot be established. Start a new `RUN_ID` instead. Existing launcher receipt schemas do not need to be mutated merely to carry this external linkage; the evidence index owns the association.

## Prior-provenance satisfaction and no-restage rule

Evidence state has two independent fields, and they are never the same field:

- `ARTIFACT_PROVENANCE` — where and when an artifact actually came from: `CURRENT_RUN`, `PRIOR_RUN`, `MISSING`, `INVALID`, or `SUPERSEDED`. An artifact from an earlier run stays `PRIOR_RUN`. It cannot be relabeled `CURRENT_RUN`, copied into a newer run folder, or given a rewritten timestamp.
- `DISCRIMINATOR_STATE` — whether the evidence already possessed answers the factual question: `SATISFIED_CURRENT_RUN`, `SATISFIED_BY_PRIOR_PROVENANCE`, `UNSATISFIED`, `STALE_REVALIDATION_REQUIRED`, `CONFLICT`, or `NOT_APPLICABLE`.

Prior evidence may satisfy a current discriminator without becoming an artifact of the current run. Canonical example for the completed START TEST experiment:

```text
START_TEST_ARTIFACT_PROVENANCE=PRIOR_RUN
START_TEST_DISCRIMINATOR=SATISFIED_BY_PRIOR_PROVENANCE
REMOTE_ENDPOINT_CANDIDATE=NONE
RESTAGE_REQUIRED=NO
```

Rules:

- A missing same-run duplicate never forces a repeat. A newer `RUN_ID`, an empty phase cell, an uncopied prior artifact, or an evidence index that distinguishes prior from current provenance is not by itself an invalidation event.
- Index the earlier artifact as prior provenance with its original `RUN_ID` and timestamp. Do not copy it into the new run folder, do not rewrite its timestamp, and do not claim it occurred in the new run.
- Restage only with a recorded invalidation reason: a different reader identity; a firmware, software, or network/control-plane change; prior evidence illegible or incomplete for this discriminator; conflict with newer evidence; an explicitly new same-window temporal comparison; or an explicit operator reproduction request.
- Same-window proof stays strict: a `BASELINE` from one run and a `POST_TEST` from another run can never be promoted into a proved same-window delta, and cross-window artifacts still may not be combined under one `RUN_ID`.
- When the discriminator is `SATISFIED_BY_PRIOR_PROVENANCE`, record the result and advance to the next unresolved discriminator — currently the firmware management baseline — instead of repeating the completed experiment.

The reusable machine contract is `harness/api/evidence-provenance-registry.json`, validated offline by `harness/validators/validate-evidence-provenance-contracts.py`.

## Canonical Netstat evidence phases

One authorized reader run uses this order:

1. **Identity gate** — resolve the strongest reader identity available from approved field evidence. If identity is unresolved, preserve an unknown-reader state rather than guessing a dashboard row.
2. **BASELINE** — capture the complete Netstat output before pressing Netstat `START TEST` or running another controlled action.
3. **START_TEST** — press the Netstat `START TEST` control only inside the approved diagnostic window and immediately capture the resulting state.
4. **DURING_TEST** — use only while an approved controlled diagnostic action is actually active and the timing is practical.
5. **POST_TEST** — capture a second complete Netstat pass immediately after the controlled action.
6. Compare only legible deltas: sockets added/removed, remote IP/hostname when visible, destination port, protocol, state, and errors.
7. Preserve blurred or partial text as unknown. Do not reconstruct a value from guesswork.

Each complete phase starts at the absolute top. Adjacent frames must overlap enough to reconstruct the scrolling output, and the final frame must prove the absolute bottom was reached or record that it was not.

## Workstation correlation lane

Use the existing tracked technician front door for the reader-side time window:

```text
Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC]
```

The launcher delegates to `scripts/Invoke-SasHhCcReaderProbe.ps1` and records:

- active network/profile/interface context;
- exact one-target same-subnet classification;
- neighbor/MAC state;
- bounded ICMP evidence;
- compact `Test-NetConnection -InformationLevel Detailed` evidence;
- one explicit TCP-port result;
- an ignored local JSON receipt.

Do not hand technicians a reconstructed chain of internal PowerShell commands when the launcher covers the workflow.

### Endpoint-correlation step

When current `main` contains `Probe-HHCCReaderEndpoint.cmd`, it is the repository-owned continuation for one explicitly observed and approved remote hostname/IP plus one explicit port. It must run only after the canonical reader same-subnet/device gate. If that launcher is absent from refreshed `main`, stop rather than substituting a hand-built technician PowerShell chain.

The endpoint continuation records DNS resolution when applicable, source interface/address, destination address/port, and TCP success/failure in ignored local evidence. It must not perform range discovery, broad port scans, ownership inference, configuration changes, or firmware mutation.

### Passive workstation-capture topology caveat

Passive workstation packet capture is supplemental evidence, not a reliable liveness oracle for a peer device on an ordinary switched LAN or Wi-Fi network. Reader-to-gateway unicast may never traverse the technician workstation NIC, even when the reader is fully awake and transmitting. Therefore a quiet `pktmon` window does **not** distinguish "reader asleep/idle" from "capture point is off-path."

If complete outbound-flow observation becomes necessary, capture must occur at a point that actually sees that traffic (for example an authorized gateway/AP capture or an explicitly authorized lab bridge). That is a separate lab/network-observation lane; it must not silently alter this canonical read-only field probe.

## Four-part baseline before firmware configuration

A representative A80 is not ready for firmware configuration until four linked baselines exist.

### A. Identity baseline

Preserve the reconciled device identity and its directly observed model/site/location/network context. Identity evidence is not authorization to mutate the device.

### B. Software baseline

Record the current firmware/build and payment/application version only from a supported read-only surface or the authoritative management plane.

If a version is not exposed, record it as unknown. Do not infer a version from date, model, network destination, or public vendor material.

### C. Network/control-plane baseline

Preserve:

- complete Netstat BASELINE / START_TEST / optional DURING_TEST / POST_TEST evidence;
- Connectivity Test results per service rather than one summary pass/fail;
- the paired workstation probe from the same time window;
- only endpoint correlations directly supported by legible evidence.

### D. Management baseline

Identify the authoritative management plane for this estate and record:

- who owns the entitlement/access path;
- authoritative current firmware;
- authoritative target firmware/package;
- supported assignment/update method;
- expected reboot/reconnect behavior;
- rollback/exception handling;
- post-update validation requirements.

Public or generic vendor behavior is not enough to satisfy this baseline for the H&H estate. Use the **Management-plane candidate disposition (2026-10-01)** ledger above for current typed dispositions; close this baseline only when an estate-specific authority maps the representative reader to package `2.0.15.260522` and the supported update contract.

## Firmware configuration gate

Do not configure, assign, push, or sideload firmware until the management baseline identifies the authoritative target package/version and supported update method for this estate.

Netstat and Connectivity Test can help identify transport behavior and correlation targets. They do not authorize a firmware package.

Once the authoritative update path is known, use one authorized representative A80 for a controlled pilot:

1. freeze and timestamp the complete pre-update baseline;
2. record the authoritative current and target firmware/package;
3. record the supported update assignment/action;
4. execute only the authorized vendor/H&H update path;
5. perform only the reboot/reconnect steps required by that workflow;
6. recapture directly observed firmware/build/application version;
7. recapture Connectivity Test and Netstat post-update behavior;
8. pair the same validation window with the workstation probe;
9. classify the update as accepted only when the expected target version is directly observed and the required approved operational checks remain acceptable;
10. record active technician time, vendor/wait time, reboot/download time, validation time, and exception time separately.

Production throughput is not a mature KPI until that pilot is repeatable.

## Repository and field-evidence boundary

The repository owns reusable logic, parameterization, validators, classifications, and technician launchers.

The operator-managed external evidence workspace owns live reader identities, screenshots, private environment values, and field photos.

Do not add provider-specific workspace URLs/IDs, live infrastructure values, credentials, or raw field evidence to tracked source.

## Proof ceiling

Repository documentation and offline contracts can prove the intended phase order, bounded probe shape, safety boundaries, and absence of live field values. They cannot prove current firmware, target firmware, service ownership, management entitlement, a successful update, or production throughput.

Issue #436 remains the field-acceptance ledger for the existing read-only probe. Network-probe acceptance must not be promoted into firmware-update acceptance.
