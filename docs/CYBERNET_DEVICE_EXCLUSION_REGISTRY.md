# Cybernet Device Exclusion Registry

## Purpose

The Cybernet device-exclusion registry exists to **avoid unnecessary Cybernet survey and metadata work** when existing approved evidence already proves that a candidate is another device class.

It is intentionally conservative:

- exclusion is a one-way decision to stop Cybernet follow-up;
- exclusion is **not** a shortcut for confirming Cybernet identity;
- weak hints never become safe merely because several of them agree;
- the default is `DO_NOT_EXCLUDE`;
- conflicts fail open to review/read-only identity rather than silently dropping a candidate.

Canonical policy: `harness/api/cybernet-device-exclusion-registry.json`.

Schema: `schemas/harness/cybernet-device-exclusion-registry.schema.json`.

Tracked policy contains **no live device entries**. Live exclusions belong in ignored local output or another explicitly approved external authority.

## Decision stages

The registry distinguishes three places where work can safely stop:

| Stage | Meaning | Required evidence |
|---|---|---|
| `BEFORE_NETWORK_SIGNATURE` | Skip even the bounded 135+445 signature spend | Existing `AUTHORITATIVE` evidence explicitly proves another device class |
| `BEFORE_ENDPOINT_METADATA` | A host may exist in the candidate population, but no endpoint metadata session is justified | Existing `AUTHORITATIVE` evidence explicitly proves another device class |
| `BEFORE_HARDWARE_METADATA` | The existing workstation-class gate has already run; skip manufacturer/model/serial | Authoritative non-Cybernet evidence or current Windows `ProductType != 1` from the already-required canary gate |

The registry does **not** authorize a new active query merely to obtain exclusion evidence.

For example, do not open SNMP, HTTP, printer, RDP, or other ports just to prove that a host should have been excluded. Existing evidence may be reused, but new exclusion-specific endpoint interrogation defeats the low-noise goal.

## Evidence strength

### `AUTHORITATIVE`

May auto-exclude at the stages explicitly allowed by its evidence type.

Examples:

- prior SysAdminSuite `CONFIRMED_NON_CYBERNET` bound to the same stable device;
- an approved hardware reference proving the already-observed hardware is non-Cybernet;
- approved CMDB or asset inventory explicitly classifying the same stable asset as a printer, access point, time clock, server, or other non-Cybernet class;
- approved printer inventory tied to the same printer asset;
- approved network-controller inventory tied to the same access point;
- approved time-clock inventory tied to the same Cronus/time-clock asset;
- approved endpoint inventory establishing server/non-client OS class;
- current canary `Win32_OperatingSystem.ProductType != 1`, but only at `BEFORE_HARDWARE_METADATA`.

### `STRONG`

High-quality evidence that deserves review but does **not** auto-exclude.

Examples:

- AD says `Windows Server`;
- an already-existing SNMP description appears to identify another class.

Strong evidence does not become authoritative by counting two or more strong observations.

### `CORROBORATING`

Useful context only.

Examples:

- DHCP vendor class;
- DNS/PTR role label;
- MAC OUI/vendor;
- an already-existing HTTP device banner.

Corroborating evidence never auto-excludes and never accumulates into an exclusion decision.

### `WEAK`

Never safe for exclusion.

Examples:

- hostname patterns;
- software presence;
- software absence;
- open TCP ports, including printer/web/RPC/SMB ports;
- the 135+445 Windows-PC candidate signature;
- subnet/site-role inference.

These remain context only.

### `CONFLICTING`

Any credible conflict stops automatic exclusion.

If positive Cybernet hardware evidence exists, the exclusion path is blocked and the candidate returns to hardware-identity review.

## Class-specific rules

### Printers

Safe pre-query rejection requires authoritative device-class evidence such as an approved printer inventory, explicit CMDB/asset classification, prior confirmed non-Cybernet identity, or an approved hardware-reference result.

Never reject merely because:

- TCP 9100 is open;
- a hostname looks printer-like;
- a web page/banner resembles a printer;
- the MAC OUI looks like a printer vendor.

### Access points

Safe pre-query rejection requires authoritative controller/NMS inventory, explicit CMDB/asset classification, prior confirmed non-Cybernet identity, or approved hardware-reference evidence.

Never reject merely from:

- AP-looking hostname;
- web ports;
- MAC vendor;
- site/subnet placement.

### Cronus clocks / time clocks

Safe pre-query rejection requires an approved time-clock inventory record, explicit CMDB/asset classification, prior confirmed non-Cybernet identity, or approved hardware-reference evidence.

A hostname containing `clock`, an OUI, or an existing web banner is not enough.

### Servers

An approved CMDB/endpoint inventory server classification may reject before an endpoint metadata session.

If that evidence is absent, a 135+445 responder still reaches only the existing workstation-class gate. The canary may read `Win32_OperatingSystem.ProductType`; a value other than `1` stops the target **before manufacturer/model/serial**.

AD `OperatingSystem=Windows Server` by itself remains strong-but-non-authoritative because directory attributes may be stale.

### Other computers

This is deliberately the strictest class.

A generic `computer`, `desktop`, or `workstation` label is **not** enough to reject: Cybernets are themselves Windows workstations.

Safe pre-query rejection requires one of:

- a prior SysAdminSuite confirmed-non-Cybernet decision bound to the same stable device; or
- an approved hardware-reference result proving the already-observed hardware is outside the Cybernet class.

This preserves the important case where a Cybernet-style hostname belongs to ordinary non-Cybernet hardware without letting broad “computer” labels cause false negatives.

### Other network / non-Cybernet devices

Explicit authoritative CMDB/asset classification may exclude switches, routers, controllers, appliances, and other non-Cybernet device classes before Cybernet probing.

Weak network signatures remain insufficient.

## Precedence

Apply decisions in this order:

1. **Positive Cybernet hardware evidence present** → `BLOCK_EXCLUSION_AND_ROUTE_TO_HARDWARE_IDENTITY`.
2. **Credible evidence conflict** → `REVIEW_REQUIRED_NO_AUTO_EXCLUSION`.
3. **Allowed authoritative exclusion evidence** → exclude at the earliest stage permitted by that evidence type.
4. **Anything weaker** → `DO_NOT_EXCLUDE`.

Do not reinterpret software, hostname, subnet, OUI, or ports as authority.

## Live entry contract

A live exclusion entry must bind the decision to a stable device key such as an approved serial, asset ID, MAC, controller ID, or CMDB CI. Hostname/IP alone are intentionally not stable-key types in the schema.

Each live entry records:

- device class;
- stable device key;
- evidence type;
- source reference;
- observation timestamp;
- decision status;
- reason codes;
- evaluation timestamp.

Tracked `harness/api/cybernet-device-exclusion-registry.json` must keep `entries: []`.

## Relationship to the professional Cybernet funnel

The targeted low-noise order is:

1. deployment/topology evidence determines **where to look**;
2. reuse the exclusion registry against existing approved evidence;
3. excluded devices stop without new packets or metadata;
4. unresolved computer candidates receive only the bounded 135+445 signature;
5. dual-port candidates receive the existing minimal workstation-class gate;
6. only `ProductType=1` may reach manufacturer/model/serial;
7. Cybernet identity still requires observed serial + model + approved hardware reference.

Topology narrows scope. Exclusion removes already-proven non-Cybernet devices. Neither substitutes for Cybernet identity.

## Validation

```text
python harness/validators/validate-cybernet-hardware-identity.py
python harness/validators/validate-cybernet-device-exclusion-registry.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
git diff --check
```

## Proof ceiling

The registry can prove that SysAdminSuite will not *authorize* automatic exclusion from weak/corroborating signals and that class-specific pre-query rules require approved authoritative evidence.

It does not populate live inventories, prove the accuracy of an external CMDB/controller/inventory source, or classify a live device by itself.
