# Cybernet Professional Low-Noise Survey

## Objective

Find Cybernet candidates without repeating the early broad-scan mistake where access points, printers, and other network devices were treated as useful workstation targets.

The professional funnel is deliberately asymmetric:

1. **Population before packets** — prefer an approved computer population from AD, tracker/inventory, prior evidence, DNS/DHCP correlation, or another authorized workstation source.
2. **PC-signature network gate** — probe only TCP **135 and 445**, with zero scan retries and a default rate of 50. Both ports must be observed before a host becomes a metadata candidate.
3. **Workstation-class gate** — a candidate gets at most one read-only DCOM/CIM session. `Win32_OperatingSystem.ProductType` must equal `1` (Windows client workstation) before hardware metadata is requested.
4. **Hardware identity** — only a confirmed client workstation is queried for manufacturer/model and BIOS serial.
5. **Cybernet identity** — model + serial are compared with the separately approved Cybernet hardware reference. Network signature alone never means “Cybernet.”

This is **not a stealth feature**. It minimizes unnecessary packets and unnecessary metadata queries; it does not hide activity and does not guarantee that monitoring will not alert.

## Lane A — professional candidate survey

Operator terminal: Git Bash / Bash-on-Windows.

This lane performs network signature collection only; it performs no endpoint metadata query. Start from an approved **computer** host/IP list. Do not feed it printers, access points, arbitrary subnet discoveries, CIDRs, ranges, or wildcards.

```bash
bash survey/sas-run-windows-pc-signature.sh --list targets/local/approved_computers.txt
```

The wrapper is pinned to the generated `windows_pc_signature_json` profile:

- TCP ports: `135,445` only
- Naabu retries: `0`
- default rate: `50`
- JSON evidence: local only
- automatic follow-up: disabled
- target mutation: none
- metadata queries: none

It writes ignored local artifacts under `logs/nmap/` and `survey/output/windows_pc_signature/`, including a candidate list containing only hosts where **both** ports were observed.

Why this removes the earlier noise problem:

- web-only access points do not qualify;
- ordinary printers exposing HTTP/HTTPS or TCP 9100 do not qualify;
- RPC-only or SMB-only devices do not qualify;
- no service/version/vulnerability scan is performed;
- no metadata call is made by this lane.

A device can still expose both 135 and 445 without being a user workstation. That is why the next lane proves Windows client `ProductType=1` before reading hardware metadata.

## Lane B — bounded metadata canary

Operator terminal: **Windows PowerShell**.

Use the installed `sas` command from any directory:

```powershell
sas cybernet canary HOST01 HOST02
```

Up to five explicit approved hostnames/FQDNs/IPs may be supplied. CIDRs, IP ranges, wildcard patterns, and subnet-discovery inputs are rejected before the network-aware wrapper changes network posture.

For candidates without reusable completed evidence, the canary performs one canonical preflight pass containing DNS resolution, one ICMP attempt, and TCP 135 + 445. It opens one DCOM/CIM session only when **both** ports are open. Inside that same session it first reads only `Win32_OperatingSystem.Caption` and `ProductType`.

Hardware queries are conditional:

- `ProductType = 1` → Windows client workstation confirmed; manufacturer/model/serial may be queried.
- server/domain-controller ProductType → stop; hardware metadata is skipped.
- ProductType unavailable/denied → stop; hardware metadata is skipped.
- 135 or 445 missing → stop before any CIM session.

When workstation class passes, the same one-shot session may read:

- `Win32_ComputerSystem`: hostname, manufacturer, model
- `Win32_BIOS`: BIOS serial

There is no canary-level retry and no command-line credential input.

## Evidence reuse

Completed canary evidence may be reused for 24 hours based on the original `ObservationTimestamp`. Reuse never refreshes that observation clock. Older 135-only canary records do not satisfy the new dual-port schema and therefore cannot bypass the professional signature gate.

Expected local artifacts:

```text
survey/output/cybernet_canary/<run>/cybernet_canary_identity.csv
survey/output/cybernet_canary/<run>/cybernet_canary_summary.json
survey/output/cybernet_canary/<run>/cybernet_canary_complete.json
```

Useful fields include `Port135`, `Port445`, `PcSignatureStatus`, `WorkstationStatus`, `ObservedOperatingSystem`, `ObservedManufacturer`, `ObservedModel`, `ObservedSerial`, `IdentityStatus`, `EvidenceSource`, and `NetworkActivityPerformed`.

## Classifications

| Classification | Meaning |
|---|---|
| `WINDOWS_PC_SIGNATURE_MATCH` | Both TCP 135 and 445 were observed. Candidate evidence only. |
| `WINDOWS_PC_SIGNATURE_NOT_MATCHED` | The host did not satisfy both-port gating; no metadata session. |
| `WINDOWS_CLIENT_WORKSTATION_CONFIRMED` | `ProductType=1` inside the one read-only CIM session. |
| `NON_WORKSTATION_OS_METADATA_SKIPPED` | Windows server/DC class; hardware metadata skipped. |
| `WORKSTATION_CLASS_UNRESOLVED_METADATA_SKIPPED` | Client-workstation class could not be proved; hardware metadata skipped. |
| `IDENTITY_COLLECTED` | Confirmed client workstation returned model + BIOS serial. |
| `IDENTITY_PARTIAL` | Confirmed client workstation returned only part of the requested hardware identity. |
| `IDENTITY_QUERY_FAILED` | Workstation class passed but no hardware identity was returned. |
| `FreshLocalReuse` | Current completed evidence was reused with no new live probe for that target. |

None of these classifications alone equals `CONFIRMED_CYBERNET`. Cybernet classification still requires observed model + observed serial + the approved hardware reference.

## Known-good calibration

A physically controlled, already-known Cybernet is valuable as a calibration target because it lets the operator confirm that the VPN/network path exposes the expected dual-port signature and read-only workstation metadata before scaling. Keep its hostname, serial, model, IP, and run evidence machine-local; tracked documentation uses synthetic placeholders only.

## If the approved computer population is incomplete

Do **not** fall back immediately to the old broad web/printer-aware key-port scan. Expand population sources before expanding packet scope:

1. Active Directory computer export / registered computer population.
2. Existing tracker, serial manifest, deployment sheet, or prior local evidence.
3. DNS and DHCP correlation against those computer records.
4. SCCM/ConfigMgr, CMDB, endpoint-management, or other authorized workstation inventory when available.
5. Only when an approved subnet sweep is genuinely required, use the subnet-survey authority with explicit CIDR approval; keep that discovery evidence separate and feed resulting computer candidates back through the 135+445 signature gate before metadata.

The existing generic `keyports_cybernet_json` profile remains useful for broader service posture after a target population is already justified. It is **not** the preferred first-pass Cybernet hunting profile because its 80/443/3389/5985/5986 observations answer different questions and can surface unrelated infrastructure.

## Proof ceiling

This workflow can prove bounded reachability, dual-port candidate posture, Windows client-workstation class, and read-only hardware observations. It cannot prove a device is a Cybernet without the approved hardware reference, authorize deployment, or claim reduced monitoring visibility.
