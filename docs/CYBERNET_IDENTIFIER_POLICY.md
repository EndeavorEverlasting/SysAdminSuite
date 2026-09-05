# Cybernet Identifier Policy

## Purpose

Cybernet discovery is **population-first, signature-gated, and hardware-confirmed**.

The older WAB-era rule that described Cybernet identity discovery as “Nmap-first” is superseded. Nmap and Naabu remain first-class read-only network evidence tools, but a broad service scan is not Cybernet identity and is not the preferred first move when an approved computer population is available.

Current operator procedure: [`CYBERNET_LOW_NOISE_CANARY.md`](CYBERNET_LOW_NOISE_CANARY.md). Current hardware-identity authority: [`../harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md`](../harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md).

## Professional discovery policy

1. **Population before packets.** Prefer approved computer records from Active Directory, tracker/inventory, prior evidence, DNS/DHCP correlation, CMDB, SCCM/ConfigMgr, endpoint inventory, or another authorized workstation source.
2. **Minimal PC-signature probe.** Against that approved computer host list, use the `windows_pc_signature_json` profile through `survey/sas-run-windows-pc-signature.sh`: TCP 135 and 445 only, zero retries, default rate 50, no automatic follow-up, no metadata.
3. **Dual-port promotion only.** A host becomes a metadata candidate only when both TCP 135 and 445 are observed. A web-only access point, printer exposing HTTP/HTTPS or 9100, RPC-only responder, or SMB-only responder does not graduate.
4. **Workstation class before hardware.** `sas cybernet canary HOST...` may open one read-only DCOM/CIM session only after both ports are open. It reads `Win32_OperatingSystem.ProductType` first. Only `ProductType=1` may advance to manufacturer/model/BIOS serial queries.
5. **Hardware identity before profile.** Model + serial must be compared with the approved Cybernet hardware reference. Hostname, AD membership, IP/subnet, MAC/OUI, reachability, service posture, and software footprint remain supporting/candidate evidence only.
6. **Read-only discovery.** Discovery and identity collection never authorize deployment or mutation.

## Network authority

The professional signature scan delegates network admission to the canonical PowerShell `Confirm-SasNorthwellNetwork.ps1` / `SasNetworkGuard` authority. That includes approved WAB Wi-Fi and repository-supported DomainAuthenticated non-Wi-Fi VPN/LAN evidence. Do not invent a second VPN detector or weaken the canonical gate.

PowerShell, WMI, or CIM failure is not proof that a machine is offline or non-Cybernet. It is an identity-transport failure or unresolved state. Network reachability and identity collection remain separate proof layers.

## Where Nmap and Naabu still belong

Nmap/Naabu are useful for:

- bounded reachability and port evidence against an already justified host population;
- the dedicated 135+445 professional PC-signature lane;
- approved subnet discovery only when population sources are genuinely incomplete and explicit subnet scope has been authorized;
- broader service posture after a target population is already justified;
- durable local scanner artifacts for offline parsing/correlation.

They are **not** proof of Cybernet hardware identity. The generic seven-port Cybernet key-port profile and subnet survey runner remain available for their existing use cases, but they are not the preferred first-pass hunt for missing Cybernets.

## Expected evidence layers

| Layer | Examples | What it can prove |
|---|---|---|
| Population | AD computer record, tracker row, CMDB/SCCM/endpoint inventory | Candidate should exist; no live reachability claim |
| Infrastructure correlation | DNS, DHCP, prior IP/MAC evidence | Routing/location/current-infrastructure clues |
| PC signature | TCP 135 + 445 observed | Candidate supports a Windows-PC-like service posture; not workstation class or Cybernet identity |
| Workstation class | `Win32_OperatingSystem.ProductType=1` | Windows client workstation |
| Hardware metadata | Manufacturer, model, BIOS serial | Observed hardware facts |
| Cybernet reference comparison | Approved model + serial authority | `CONFIRMED_CYBERNET`, `CONFIRMED_NON_CYBERNET`, incomplete, or conflicting identity |

## Classification

| Condition | Classification / disposition |
|---|---|
| Protected network not proven | Stop before target contact; network/environment blocked |
| Approved computer candidate lacks both 135 and 445 | `WINDOWS_PC_SIGNATURE_NOT_MATCHED`; no metadata query |
| Both 135 and 445 observed | `WINDOWS_PC_SIGNATURE_MATCH`; candidate only |
| ProductType is not 1 | `NON_WORKSTATION_OS_METADATA_SKIPPED` |
| Workstation class cannot be proved | `WORKSTATION_CLASS_UNRESOLVED_METADATA_SKIPPED` |
| Client workstation returns model + serial | Hardware identity collected; compare with approved reference |
| Model/serial/reference incomplete | `IDENTITY_INCOMPLETE` |
| Hardware evidence conflicts | `CONFLICTING_IDENTITY`; stop automation |
| Approved reference proves non-Cybernet hardware | `CONFIRMED_NON_CYBERNET`; keep as known device and exclude from prime Cybernet targets |
| Approved reference proves Cybernet hardware | `CONFIRMED_CYBERNET`; profile selection may proceed through its separate gate |

## Agent rule

Future agents must not resurrect broad Nmap/Naabu service discovery as the default Cybernet-identification strategy merely because the tooling exists. Use passive/approved computer population evidence first, spend the smallest justified packet budget, and collect hardware metadata only after the PC-signature and Windows-client gates pass.

Low-noise means fewer unnecessary packets and fewer unnecessary metadata queries. It does **not** mean stealth, evasion, spoofing, decoys, or an expectation that enterprise monitoring will not observe the work.
