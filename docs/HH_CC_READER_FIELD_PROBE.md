# Health & Hospitals CC Reader Read-Only Field Probe

## Status

**Repository lane:** merged implementation with field acceptance tracked by issue #436.
**Current field authority:** operator-managed external technician instructions remain authoritative until the merged repository workflow is separately field-accepted.

SysAdminSuite does not know or require the provider, account, folder hierarchy, file ID, or URL behind that external field material. This document intentionally contains no live H&H target IP, MAC, credential, screenshot, private external-workspace identifier, or raw probe output.

## Technician front door

The tracked Windows front door is:

```text
Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC]
```

Use one explicit authorized CC-reader IPv4 address. When the device's expected MAC is known from approved field evidence, supply it so the probe can fail closed before higher-layer interpretation if the IP resolves to the wrong device.

Documentation-only example:

```text
Probe-HHCCReader.cmd 192.0.2.10 AA-BB-CC-DD-EE-FF
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

## 2026-09-28 Netstat continuation

The field investigation now has a reusable Netstat phase contract rather than a one-screenshot observation.

The full contract is in [HH_CC_READER_NETSTAT_BASELINE.md](HH_CC_READER_NETSTAT_BASELINE.md). It preserves:

- complete Netstat `BASELINE` before `START_TEST`;
- immediate `START_TEST` capture;
- optional `DURING_TEST` evidence only during an approved controlled diagnostic;
- complete `POST_TEST` capture;
- overlapping ordered frames for scrolling output;
- paired workstation evidence from this existing launcher;
- a four-part identity/software/network/management baseline before firmware configuration;
- an explicit rule that network/control-plane evidence does not itself authorize firmware.

Current field evidence has also surfaced device-labeled Connectivity Test checks including **PAX Store Push Service Primary (443)**. That label is a correlation candidate only; it does not prove that a corresponding Netstat session is visible or that PAX Store owns the firmware path for this estate.

The next one-endpoint workstation correlation helper is specified in the Netstat baseline contract but is not yet a repository-owned technician launcher. Do not replace that missing launcher with a hand-built technician PowerShell sequence.

## Interpretation

- Same-subnet proof is network-placement evidence, not device identity.
- A matching expected MAC is stronger same-L2 device evidence.
- Ping failure alone does not prove a reader is offline.
- TCP/443 success proves only TCP/443 reachability.
- No result from this workflow identifies AxiaMed, Bank of America, PAXSTORE, Payment Fusion, or a firmware-management service by itself.
- A Netstat or Connectivity Test observation is not a firmware-update procedure.

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

Repository tests can prove command shape, fail-closed input/network/device gates, absence of live H&H values, read-only implementation posture, and the documented Netstat/baseline decision contract. They cannot prove the technician's scanner behavior, H&H network placement, target reachability, device identity, service ownership, current/target firmware, or firmware update success. Those remain field evidence.
