# Health & Hospitals CC Reader Netstat Baseline and Firmware Decision Gate

## Status

**Discovery state:** active.
**Firmware procedure:** not yet proven.
**Field evidence authority:** operator-managed external evidence workspace.
**Repository role:** reusable parameterized procedure, safety boundaries, and acceptance semantics only.

This document intentionally contains no live H&H target IP, MAC, credential, screenshot, private external-workspace identifier, or raw field output.

## Operator-selected firmware target

**Default target firmware:** `2.0.15.260522`.

This is the operator-selected default target for the H&H A80 rollout and should be carried forward by agents, reports, pilot planning, and management-path discovery unless stronger authoritative estate-specific evidence explicitly supersedes it.

Evidence semantics remain strict:

- `2.0.15.260522` is the current **operator-selected target**, not proof that a particular PAXSTORE/processor tenant has exposed or authorized the corresponding package.
- Discovery work should seek the exact package/release mapping for `2.0.15.260522`, the owning management plane, and the supported assignment method.
- Do not silently replace the target with another version because a vendor portal, generic guide, coworker device, or agent proposes a different build. Record any conflict explicitly and reconcile it against authoritative estate-specific evidence.
- Firmware mutation remains gated on a supported management/update path and a controlled representative-reader pilot.

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

The next controlled reader window should therefore preserve the existing Netstat/Connectivity-Test phase contract and look only for a concrete endpoint/port that appears during the built-in test. If one is observed, use the existing one-endpoint correlation launcher. If none is observed, retain `NO_CONCRETE_ENDPOINT_OBSERVED` rather than broadening discovery.

The management baseline can be closed only by authoritative estate-specific evidence such as the applicable PAXSTORE/processor/reseller terminal record, an approved support case or owner confirmation, or another supported management plane that directly identifies the reader and the allowed firmware task. Coworker anecdote, generic PAXSTORE capability, or a successful Connectivity Test is not sufficient.

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

Public or generic vendor behavior is not enough to satisfy this baseline for the H&H estate.

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
