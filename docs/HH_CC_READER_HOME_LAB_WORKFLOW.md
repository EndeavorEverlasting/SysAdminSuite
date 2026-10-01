# H&H CC Reader — Network Switch + Authorized Home-Lab Workflow

## Purpose

Preserve the repeatable workstation-side path for one authorized PAX A80 / CC reader when the technician is moving between local networks or reproducing a home-lab condition.

This lane exists because a consumer/private LAN is not the same authority model as a protected enterprise network. A DNS miss, an empty ARP cache, or a passive-capture miss on the technician laptop does not prove that the reader is offline or unreachable. The gateway/DHCP/local-subnet context may know more than the workstation cache.

The protected H&H field probe remains strict and target-only. This document does **not** weaken that path.

## Environment split

### PROTECTED_ENTERPRISE

Use the existing canonical front door:

```text
Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC]
```

No subnet/range discovery is authorized by that command.

### AUTHORIZED_CONSUMER_LAB

Use the network-switch and bounded local-discovery workflow in this document.

The home-lab lane requires an explicit `CONFIRM_CONSUMER_LAB` token, a prepared sealed runtime, and the repository network classifier to report `GUEST_INTERNET` before any active discovery. When the reader's approved IPv4 is already known from authoritative field evidence, preserve that information and use the canonical one-target probe instead of rediscovering the subnet. Only when the IPv4 is genuinely unknown may the home-lab lane run up to two bounded host-presence passes across the workstation's current **private local subnet**, subject to a hard host-count ceiling, solely to populate local neighbor state and recover an exact approved MAC. It does not perform broad port scanning.

## Canonical command flow

### 1. Before switching networks

Run:

```text
Prepare-HHCCReaderNetworkSwitch.cmd RUN_ID [EXPECTED_MAC]
```

The launcher:

1. refreshes current SysAdminSuite provider/default-branch truth through the existing network-aware refresh transaction;
2. seals the resulting runtime to `C:\SASAL`;
3. captures a read-only `BEFORE_SWITCH` workstation checkpoint;
4. persists machine-local continuation state outside the repository working tree.

It does not change the reader, choose the next network, or configure Windows networking.

### 2. After switching networks

**Known approved IPv4:** do not throw it away and start subnet discovery. Use the canonical `Probe-HHCCReader.cmd TARGET_IPV4 [EXPECTED_MAC]` route so the explicit IPv4 is immediately re-correlated with the expected MAC and the read-only probe.

**IPv4 genuinely unknown:** run the bounded discovery front door:

```text
C:\SASAL\Discover-HHCCReaderHomeLab.cmd RUN_ID CONFIRM_CONSUMER_LAB [EXPECTED_MAC]
```

The discovery workflow first captures `AFTER_SWITCH` automatically, then:

1. selects the active private IPv4 interface owning the default route;
2. records the local IPv4/prefix/default gateway;
3. refuses a subnet larger than the configured bounded host ceiling;
4. checks the existing neighbor table for the exact expected MAC;
5. only when the exact MAC is absent, sends one short ICMP presence attempt to each host address in that one private local subnet;
6. waits a bounded settle interval and re-reads the neighbor table;
7. if the exact MAC is still absent, performs one final bounded reacquisition pass, then re-reads the neighbor table again;
8. stops early as soon as any exact-MAC match appears;
9. promotes an IPv4 only on one exact expected-MAC match;
10. records same-OUI neighbors only as advisory candidates;
11. on one exact match, invokes the existing `Invoke-SasHhCcReaderProbe.ps1` canonical reader probe from the sealed runtime;
12. classifies absence only after the bounded reacquisition window is exhausted.

An OUI-only match is never treated as device identity. `HOME_LAB_EXACT_MAC_NOT_FOUND_AFTER_REACQUISITION` means the two-pass bounded window was exhausted; it still does not prove the reader is powered off or absent from the broader network.

### 3. Manual checkpoint when useful

```text
C:\SASAL\Checkpoint-HHCCReaderNetwork.cmd AFTER_SWITCH RUN_ID [EXPECTED_MAC] [LABEL]
```

Checkpoint captures are local-only observations: interface, profile, IPv4/prefix, gateway, DNS, default routes, WLAN metadata when Windows exposes it, and exact-MAC neighbor state.

## Why this is not a generic subnet scanner

The home-lab discovery command:

- requires a private RFC1918 IPv4 interface;
- follows the interface owning the default route;
- refuses scopes above the host ceiling;
- sends at most two bounded presence attempts per local host, stopping early when the exact MAC is reacquired;
- performs no port enumeration;
- promotes only an exact approved MAC;
- delegates higher-layer interpretation to the existing one-target reader probe.

It does not run Nmap, Naabu, Masscan, ADB, Fastboot, credential guessing, firmware pushes, payment actions, or reader configuration.

## Closed assumptions — do not rediscover

These negative results are routing evidence, not reasons to restart the investigation from zero:

- an application/kiosk label is not automatically a DNS hostname;
- DNS/LLMNR/NBT name failure does not prove the reader is offline;
- an empty workstation ARP/neighbor cache does not prove the gateway/DHCP authority lacks a lease;
- a passive exact-MAC capture with no observed frames does not prove the reader is offline or on another VLAN;
- failure of ALPHA/FUNC behavior inside an AxiaMed-controlled numeric credential field does not prove the separate Android Settings password prompt lacks alphanumeric entry;
- workstation discovery is not exhausted while an authoritative approved IPv4 can be probed directly or the bounded two-pass authorized consumer-lab reacquisition window remains untried.

## PAX A80 alpha-input checkpoint

Public Bank of America and PAX ecosystem documentation shows two relevant Android Settings credential forms in the field ecosystem: a numeric-only default and an alphanumeric default. Treat these as documented candidates for the Settings layer, not as a password-sweep list. One organization-authorized documented candidate may be tried once; rejection is evidence and does not authorize cycling unrelated credentials.

Public references:

- Bank of America Merchant Help — Terminal Configuration:
  https://merchanthelp.bankofamerica.com/Pax-Terminal-Configuration
- PAX A80 Quick Setup Guide:
  https://www.pax.us/support/documents/a80-quick-setup-guide/
- PayFacto A80 setup guidance:
  https://documentation.payfacto.com/Terminals/A80/CA-EN/Terminal_Setup_and_Configuration/Configuring_the_Terminal_Wi-Fi_Connection.htm

The repository intentionally does **not** store a live/default administrative password.

### Deterministic keypad planner

For authorized text entered interactively at runtime (hidden input; the supplied text is not persisted):

```text
Plan-HHCCReaderAlphaInput.cmd
```

The helper codifies documented PAX-family behavior:

- press the number key containing the desired letter;
- press **ALPHA** until the desired character visibly appears;
- do not assume a fixed case-cycle count across applications/firmware;
- the observed A80 keypad uses the standard letter groups on keys 2–9; the planner follows those visible groups rather than older PAX keypad layouts;
- special-character positions remain **UNPROVEN** for this A80 prompt unless the UI exposes a symbol-entry method; some documented PAX-family terminals use a visible on-screen Up-arrow/symbol control followed by ALPHA, which may be tested only when that control is actually present.

The A80 hardware has a physical ALPHA key and letter groups on the number keys. Prior failure of ALPHA/FUNC behavior inside an AxiaMed-controlled numeric credential field does not prove that the separate Android Settings prompt behaves the same way.

### Safe alpha-entry investigation order

1. Use a harmless local text field when available and cancel without executing the action.
2. Confirm whether number-key + ALPHA cycling produces visible letters in that prompt.
3. Tap the Android Settings password field and observe whether an on-screen Android keyboard/symbol layer appears.
4. If letters work but a required special character cannot be produced, record `SPECIAL_CHARACTER_UNPROVEN` rather than inventing a mapping.
5. Do not escalate to ADB/Fastboot, credential brute force, or unsupported reader mutation.

## Evidence

Ignored local artifacts:

- `survey/output/hh-cc-reader/hh-cc-reader-network-checkpoint-<timestamp>-<phase>.json`
- `survey/output/hh-cc-reader/hh-cc-reader-home-lab-discovery-<timestamp>.json`
- `survey/output/hh-cc-reader/hh-cc-reader-alpha-input-plan-<timestamp>.json` (metadata only; supplied text is not persisted)
- existing canonical probe receipts under `survey/output/hh-cc-reader/`

Machine-local continuation state:

```text
%ProgramData%\SysAdminSuite\hh-cc-reader\home-lab-state.json
```

No live H&H IP, MAC, password, screenshot, private cloud ID, or operator-specific path belongs in tracked source.

## Proof ceiling

This workflow can prove:

- workstation network context before and after a switch;
- bounded local-subnet neighbor discovery occurred;
- an exact approved MAC did or did not resolve to one local IPv4;
- the existing canonical probe result for an exact-MAC target.

It cannot by itself prove:

- management-plane ownership;
- firmware-update authority;
- target firmware/package;
- that an OUI-only candidate is the reader;
- that a no-match reader is offline;
- that a public/default Android Settings credential is accepted by this estate;
- that the firmware can be updated from home.

Those remain evidence-driven next gates.
