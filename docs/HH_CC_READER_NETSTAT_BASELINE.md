# Health & Hospitals CC Reader Netstat Baseline and Firmware Decision Gate

## Status

**Discovery state:** active.
**Firmware procedure:** not yet proven.
**Field evidence authority:** operator-managed external evidence workspace.
**Repository role:** reusable parameterized procedure, safety boundaries, and acceptance semantics only.

This document intentionally contains no live H&H target IP, MAC, credential, screenshot, private external-workspace identifier, or raw field output.

## What changed on 2026-09-28

The built-in A80 Netstat surface is now known to require a multi-frame capture rather than a single screenshot.

Current field evidence establishes:

- Netstat begins with an `Active Internet connections (w/o servers)` heading and continues beyond one screen.
- The captured output includes Android/Linux socket rows such as `DGRAM`, `SEQPACKET CONNECTED`, and `/dev/socket/...` paths.
- The current discovery frames do **not** expose a remote management IP/port clearly enough to classify one as proved.
- The device-side Connectivity Test separately exposes service checks that include terminal-management/transaction/polling functions, Payment gateway, Diagnostic service, PAX Store, and **PAX Store Push Service Primary (443)** plus another truncated PAX push entry.
- A Connectivity Test label is a correlation candidate, not proof that the same endpoint is visible in Netstat or that the service owns firmware for this estate.

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
