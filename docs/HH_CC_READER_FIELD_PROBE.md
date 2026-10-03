# Health & Hospitals CC Reader Read-Only Field Probe

## Status

**Repository lane:** merged implementation with field acceptance tracked by issue #436.
**Current field authority:** operator-managed external technician instructions remain authoritative until the merged repository workflow is separately field-accepted.

SysAdminSuite does not know or require the provider, account, folder hierarchy, file ID, or URL behind that external field material. This document intentionally contains no live H&H target IP, MAC, credential, screenshot, private external-workspace identifier, or raw probe output.

## Technician front door

The tracked Windows front door is:

```text
Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC] [NETWORK-ENVIRONMENT]
```

Use one explicit authorized CC-reader IPv4 address. When the device's expected MAC is known from approved field evidence, supply it together with an explicit network environment class so the probe can fail closed before higher-layer interpretation if the IP resolves to the wrong device. Accepted identity-bearing classes are `HOSPITAL_GUEST_SHARED`, `CONSUMER_LAB`, `PROTECTED_ENTERPRISE`, and `OTHER_SHARED`; `UNCLASSIFIED` cannot satisfy expected-MAC identity interpretation.

Documentation-only example:

```text
Probe-HHCCReader.cmd 192.0.2.10 AA-BB-CC-DD-EE-FF HOSPITAL_GUEST_SHARED

# classified network-only observation when MAC is not yet known
Probe-HHCCReader.cmd 192.0.2.10 "" HOSPITAL_GUEST_SHARED
```

The example uses TEST-NET data and is not an operational target.

## What the launcher owns

1. Refuses missing target input.
2. Runs the repository-owned freshness transaction before any target contact.
3. Re-enters the refreshed sealed `C:\SASAL` launcher.
4. Calls `scripts/Invoke-SasHhCcReaderProbe.ps1`.
5. Propagates the probe exit code and stops on any failed gate.

The launcher does not know how to switch into an H&H protected network. The technician must already be on the approved H&H network posture. The refresh transaction restores the starting network before the probe continues.

## Read-only probe sequence

The PowerShell implementation:

1. accepts one IPv4 literal only; no CIDR/range/wildcard/host discovery;
2. prints each active IPv4 network/profile/interface;
3. identifies whether exactly one active interface shares a subnet with the target;
4. stops on no-match or ambiguous network placement;
5. performs one harmless echo attempt to populate neighbor state;
6. reads `Get-NetNeighbor`;
7. optionally compares an operator-supplied expected MAC and fails closed on mismatch/unresolved identity;
8. performs a bounded ICMP test;
9. records a compact `Test-NetConnection -InformationLevel Detailed` view;
10. tests one explicit TCP port (default 443);
11. writes a JSON receipt only under the ignored local `survey/output/hh-cc-reader/` evidence root.

## Hospital guest/shared LAN posture

Hospital guest Wi-Fi is treated as a **shared non-domain network environment**, not as a smaller enterprise LAN and not as permission to inherit home-lab discovery behavior. It may resemble a home router from the workstation's point of view while still having a much larger client population, DHCP churn, client isolation, proxying, or L2-neighbor suppression.

The field rules are therefore:

- preserve the canonical one-explicit-IPv4 target contract;
- require an explicit network environment class before an expected MAC can become identity assurance; Windows network profile/category alone is observational and must not silently choose the class;
- never widen a missing-identity problem into subnet/range discovery on a hospital guest/shared network;
- record `identity_assurance` separately from reachability;
- treat `MAC_MATCHED` as stronger same-L2 identity evidence, not firmware authority;
- treat `MAC_UNRESOLVED` as an identity-transport limitation that can occur on shared/guest networks; it is not permission to guess, scan, or substitute a nearby device;
- when no expected MAC is supplied, the environment class may still be recorded, but `NETWORK_ONLY_MAC_NOT_SUPPLIED` remains reachability evidence only and cannot satisfy the round-trip identity lock;
- if the target IPv4 is unknown on a hospital guest/shared network, recover it from approved physical reader UI, private tracker/evidence, or an authorized management surface. The consumer-lab active discovery bridge below is not portable to this environment.

### Inventory identity tranches

The firmware round-trip/batch seam classifies every reader into one of four operational tranches before mutation:

| Tranche | Inventory evidence | Field implication |
| --- | --- | --- |
| `SERIAL_AND_MAC` | serial + valid MAC | Easy tranche. Eligible to proceed to the exact one-target MAC-gated probe; live correlation is still required. |
| `SERIAL_ONLY` | serial only | Recovery tranche. Recover MAC from approved physical or authorized management evidence; do not scan the guest LAN to manufacture the missing binding. |
| `MAC_ONLY` | MAC only | Recovery tranche. Recover serial from the tracker, physical label/UI, or authorized management evidence before baseline lock. |
| `IDENTITY_INSUFFICIENT` | neither | Reconciliation tranche. Stop before network probing until a reader identity anchor is recovered. |

Malformed supplied MAC values are classified `IDENTITY_INVALID` and must be corrected rather than downgraded into another tranche.

The batch planner exposes tranche counts plus a separate identity-admission summary so site work can be staged deliberately: automate only the **admissible** dual-identifier population first, then work serial-only, MAC-only, missing-identity, malformed, duplicate, forbidden, or otherwise conflicted rows through their explicit recovery gates. A row does not become easy merely because both cells are populated. **None of these tranche labels authorizes broad discovery or firmware mutation.**

## 2026-10-01 Netstat / Connectivity Test continuation

The field investigation now uses a reusable multi-phase Netstat contract rather than treating one screenshot as a complete network observation.

See [HH_CC_READER_NETSTAT_BASELINE.md](HH_CC_READER_NETSTAT_BASELINE.md). The contract preserves:

- complete Netstat `BASELINE` before `START TEST`;
- immediate `START_TEST` capture;
- optional `DURING_TEST` evidence only during an approved controlled diagnostic;
- complete `POST_TEST` capture;
- overlapping ordered frames for scrolling output;
- paired workstation evidence from this existing launcher;
- a four-part identity/software/network/management baseline before firmware configuration;
- an explicit rule that network/control-plane evidence does not authorize firmware.

Current field evidence has surfaced device-labeled Connectivity Test checks including **PAX Store Push Service Primary (443)**. That label is a correlation candidate only; it does not prove endpoint ownership or a firmware-management path.

The bounded endpoint continuation is tracked separately as `Probe-HHCCReaderEndpoint.cmd`. Use it only when that launcher exists in the technician's refreshed `main` and one specific remote endpoint/port has been observed and approved. Otherwise stop rather than reconstructing an ad-hoc PowerShell chain.

## Interpretation

- Same-subnet proof is network-placement evidence, not device identity.
- A matching expected MAC is stronger same-L2 device evidence.
- Ping failure alone does not prove a reader is offline.
- TCP/443 success proves only TCP/443 reachability.
- No result from this workflow identifies AxiaMed, Bank of America, PAXSTORE, Payment Fusion, or a firmware-management service by itself.
- A Netstat or Connectivity Test observation is not a firmware-update procedure.

## Authorized consumer-lab bridge

The canonical `Probe-HHCCReader.cmd` remains one-target and does not discover an IP. The separate consumer-lab discovery bridge invokes the canonical probe with `NetworkEnvironment=CONSUMER_LAB`; it does not make consumer discovery portable to a hospital guest/shared network.

When the technician is deliberately reproducing the reader on an authorized private/home lab LAN and the reader IPv4 is not yet known, use the separate tracked workflow:

```text
Prepare-HHCCReaderNetworkSwitch.cmd RUN_ID [EXPECTED_MAC]
C:\SASAL\Discover-HHCCReaderHomeLab.cmd RUN_ID CONFIRM_CONSUMER_LAB [EXPECTED_MAC]
```

When an authoritative approved reader IPv4 is already known, keep it and use the canonical one-target probe instead of rediscovering the subnet. When the IPv4 is genuinely unknown, the home-lab lane captures before/after workstation network context, performs at most two bounded private-subnet host-presence passes under a hard host-count ceiling, stops early on an exact expected-MAC match, and then delegates to the existing canonical probe. It is not portable to H&H protected-enterprise networks.

See [HH_CC_READER_HOME_LAB_WORKFLOW.md](HH_CC_READER_HOME_LAB_WORKFLOW.md).

## Forbidden scope

This lane must not:

- store or guess admin credentials;
- run a payment/test transaction;
- reset the terminal;
- change environment;
- alter Ethernet, VLAN, DNS, IP, Wi-Fi, or other reader configuration;
- enable ADB/fastboot;
- sideload or push firmware;
- scan a subnet, range, or broad port set;
- inherit Northwell network/authentication behavior.

## External field evidence boundary

Human reviewers may use operator-managed external tutorials, screenshots, meeting notes, or other cloud-hosted evidence alongside issue #436 or a related PR. Those materials are optional human evidence, not runtime dependencies.

The provider-neutral contract is documented in [EXTERNAL_FIELD_EVIDENCE.md](EXTERNAL_FIELD_EVIDENCE.md). SysAdminSuite must not discover, authenticate to, crawl, mount, synchronize, or require a personal cloud account or provider-specific document.

## Barcode boundary

The current H&H technician may use operator-managed external **1D Code 128** scan cards for the immediate four-command field tranche. A reusable barcode generator is explicitly deferred; this repository path does not implement one.

## Proof ceiling

Repository tests can prove command shape, fail-closed input/network/device gates, absence of live H&H values, read-only implementation posture, and the documented Netstat/baseline decision contract. They cannot prove the technician's scanner behavior, H&H network placement, target reachability, device identity, service ownership, or firmware update success. Those remain field evidence.
