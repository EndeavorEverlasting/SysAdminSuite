# Cybernet Professional Low-Noise Survey

## Objective

Find Cybernet candidates without repeating the early broad-scan mistake where access points, printers, and other network devices were treated as useful workstation targets.

The real field question is:

> **Is each explicit candidate a Windows client workstation, and can it return model + serial for comparison with the approved Cybernet hardware reference?**

The professional funnel is deliberately asymmetric:

1. **Population before packets** — prefer an approved computer population from AD, tracker/inventory, prior evidence, DNS/DHCP correlation, or another authorized workstation source.
2. **Reuse authoritative exclusions first** — printers, access points, Cronus/time clocks, servers, and other non-Cybernet devices may be removed before new querying only when `harness/api/cybernet-device-exclusion-registry.json` permits it. Weak clues never accumulate into exclusion authority.
3. **PC-signature network gate** — probe only TCP **135 and 445**, with zero scan retries and a default rate of 50. Both ports must be observed before a host becomes a metadata candidate.
4. **Workstation-class gate** — a candidate gets at most one read-only DCOM/CIM session. `Win32_OperatingSystem.ProductType` must equal `1` (Windows client workstation) before hardware metadata is requested.
5. **Hardware identity** — only a confirmed client workstation is queried for manufacturer/model and BIOS serial.
6. **Cybernet identity** — model + serial are compared with the separately approved Cybernet hardware reference. Network signature alone never means “Cybernet.”

This is **not a stealth feature**. It minimizes unnecessary packets and unnecessary metadata queries; it does not hide activity and does not guarantee that monitoring will not alert.

## Primary technician front door — CMD

Run the probe from **Command Prompt** with up to five explicit candidates:

```cmd
C:\SASAL\Probe-Cybernet.cmd HOST01 HOST02
```

`Probe-Cybernet.cmd` is deliberately currentness-first. Before any target contact it routes through the repository-owned refresh transaction. That transaction performs remote Git synchronization only in the Guest/Internet sync cache, resolves current `origin/main`, derives a clean field-ready runtime, restores the starting network posture, and reseals `C:\SASAL`. The CMD then re-enters the **refreshed** `C:\SASAL\Probe-Cybernet.cmd` and runs exactly one bounded Cybernet canary.

The CMD does **not** perform a generic discovery scan and does not run `git pull` in the caller checkout. If current repository proof or network restoration fails, the probe stops before target contact.

The CMD prints its evidence ladder before running:

- TCP 135 + 445 open → metadata candidate only;
- `ProductType=1` → Windows client workstation only;
- model + BIOS serial → observed hardware identity facts;
- `CONFIRMED_CYBERNET` → only after the observed model + serial satisfy the approved hardware reference.

## Lane A — professional candidate survey

This optional population-reduction lane runs in Git Bash / Bash-on-Windows. It performs network signature collection only; it performs no endpoint metadata query. Start from an approved **computer** host/IP list. Do not feed it printers, access points, arbitrary subnet discoveries, CIDRs, ranges, or wildcards.

```bash
bash survey/sas-run-windows-pc-signature.sh --list targets/local/approved_computers.txt
```

Before any live Naabu invocation, the wrapper delegates protected-network admission to the canonical PowerShell `Confirm-SasNorthwellNetwork.ps1` gate. That authority accepts approved WAB Wi-Fi and the repository-supported **DomainAuthenticated non-Wi-Fi VPN/LAN** posture; the Bash wrapper does not invent a separate VPN detector.

The generated `windows_pc_signature_json` profile is intentionally narrow:

- TCP ports: `135,445` only
- Naabu retries: `0`
- default rate: `50`
- JSON evidence: local only
- automatic follow-up: disabled
- target mutation: none
- metadata queries: none

It writes ignored local artifacts under `logs/nmap/` and `survey/output/windows_pc_signature/`, including a candidate list containing only hosts where **both** ports were observed. A dual-port match is still only candidate evidence.

## Lane B — bounded metadata canary

The CMD front door ultimately runs `survey/sas-cybernet-canary.ps1` from the refreshed sealed runtime. The canary accepts at most five explicit approved hostnames/FQDNs/IPs. CIDRs, IP ranges, wildcard patterns, and subnet-discovery inputs are rejected.

For candidates without reusable completed evidence, the canary performs one canonical preflight pass containing DNS resolution, one ICMP attempt, and TCP 135 + 445. It opens one DCOM/CIM session only when **both** ports are open. Inside that same session it first reads only `Win32_OperatingSystem.Caption` and `ProductType`.

Hardware queries are conditional:

- `ProductType = 1` → Windows client workstation confirmed; manufacturer/model/serial may be queried.
- server/domain-controller ProductType → stop; hardware metadata is skipped.
- ProductType unavailable/denied → stop; hardware metadata is skipped.
- 135 or 445 missing → stop before any CIM session.

When workstation class passes, the same one-shot session may read `Win32_ComputerSystem` for hostname/manufacturer/model and `Win32_BIOS` for BIOS serial. There is no canary-level retry and no command-line credential input.

## Evidence reuse and artifacts

Completed canary evidence may be reused for 24 hours based on the original `ObservationTimestamp`. Reuse never refreshes that observation clock. Older 135-only canary records do not satisfy the dual-port schema.

Expected ignored local artifacts:

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

## If the approved computer population is incomplete

Do **not** fall back immediately to the old broad web/printer-aware key-port scan. Expand population sources before expanding packet scope: AD computer records, tracker/deployment evidence, DNS/DHCP correlation, and approved SCCM/CMDB/endpoint inventory. Only when an approved subnet sweep is genuinely required should subnet-survey authority be used; feed resulting computer candidates back through the narrow identity funnel.

The generic `keyports_cybernet_json` profile remains useful for broader service posture after a target population is already justified. It is **not** the preferred first-pass Cybernet hunt because its broader ports answer different questions and surface unrelated infrastructure.

## Proof ceiling

This workflow can prove current repository selection, bounded reachability, dual-port candidate posture, Windows client-workstation class, and read-only hardware observations. It cannot prove a device is a Cybernet without the approved hardware reference, authorize deployment, or claim reduced monitoring visibility.
