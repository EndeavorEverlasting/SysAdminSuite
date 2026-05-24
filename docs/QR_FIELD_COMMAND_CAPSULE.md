# QR Field Command Capsule

## Core Insight

A QR code in SysAdminSuite is not merely a shortcut.

A QR code is a **field command capsule**.

It is a compact, scannable trigger for an approved field workflow that can survey a local machine, a room, a cart, a subnet slice, or a device class such as Neurons.

The QR should launch a governed profile. The profile should define intent. The scripts should execute the approved workflow and export evidence.

```text
QR -> profile -> approved survey lane -> evidence package
```

## Why This Matters

The earlier mistake was treating QR as:

```text
scan QR -> run one local script -> export one local report
```

That is useful, but too small.

The intended model is:

```text
scan QR -> launch a field command capsule -> survey a whole operational target set
```

Examples:

- survey a set of Neurons for current IP and hostname
- collect workstation OU/GPO posture
- run a printer evidence lane
- capture Cybernet/Neuron field readiness artifacts
- preserve raw scan evidence for later matching
- export a review package that can support tickets, reports, or deployment reconciliation

## Layer Model

| Layer | Role |
|---|---|
| QR | Short scannable trigger, not the full script body. |
| Launcher | Validates the profile and field context. |
| Profile | Declares approved intent, script, arguments, safety posture, and export behavior. |
| Survey lane | Performs the actual Recon -> Decide -> Act -> Log -> Export workflow. |
| Evidence package | Stores raw artifacts, parsed summaries, review CSVs, and Markdown reports. |

## Required Operating Shape

Every QR field command capsule must preserve the suite doctrine:

```text
Recon -> Decide -> Act -> Log -> Export
```

### Recon

Collect local machine, user, network, DNS, route, manifest, and tool availability evidence.

### Decide

Validate that the requested profile is approved, local environment fits the expected posture, target scope is bounded, and mutation is not attempted unless explicitly supported by a separate approved workflow.

### Act

Run only the workflow declared by the profile.

### Log

Record launcher, profile, host, user, timestamp, commands, target scope, and result paths.

### Export

Write human and machine-readable outputs.

## Non-Negotiable Rule

The QR must not contain a giant script.

Bad:

```text
QR contains a full Bash script or giant one-liner.
```

Good:

```bash
bash scripts/sas_qr_run.sh --profile neuron-hostname-survey
```

The QR is a trigger. The profile is the intent. The repo is the controlled implementation.

## First-Class Use Case: Neuron Hostname Survey

The highest-value initial use case is surveying a set of Neurons for current IP and hostname using MAC/subnet evidence.

Why:

- Neuron hostnames may be renamed after configuration.
- Hostname is a weak identifier.
- MAC address is network evidence.
- Serial number is hardware evidence.
- Saved Nmap XML is reusable evidence.

Target workflow:

```text
QR scan
  -> sas_qr_run.sh
  -> profile: neuron-hostname-survey
  -> load expected Neuron manifest
  -> validate subnet and scope
  -> run approved Nmap host discovery or consume saved XML
  -> match expected MACs to observed addresses
  -> resolve hostnames through safe local methods
  -> export review package
```

## Expected Neuron Survey Outputs

```text
exports/neuron_hostname_survey.csv
exports/neuron_hostname_survey_review.md
raw/nmap_neuron_discovery.xml
raw/nmap_neuron_discovery.nmap
logs/qr_capsule_events.jsonl
```

Suggested statuses:

| Status | Meaning |
|---|---|
| `MAC_MATCH_HOSTNAME_RESOLVED` | Expected MAC matched discovery evidence and hostname was resolved. |
| `MAC_MATCH_NO_HOSTNAME` | Expected MAC matched an IP but hostname could not be resolved. |
| `MAC_MATCH_REVERSE_DNS_ONLY` | Hostname came from reverse DNS only. |
| `MAC_MATCH_NETBIOS_ONLY` | Hostname came from NetBIOS/NBT evidence only. |
| `MAC_NOT_FOUND_IN_DISCOVERY` | Expected MAC was not observed in supplied discovery evidence. |
| `MAC_CONFLICT_MULTIPLE_IPS` | Same MAC appeared on multiple IPs and needs manual review. |
| `NO_USABLE_IDENTIFIER` | Manifest row lacks a usable MAC or serial. |
| `WRONG_NETWORK_POSTURE` | Local evidence suggests the tech is on the wrong segment. |

## Profile Contract

Profiles should be simple key/value files under:

```text
profiles/
```

Example:

```text
profile_id=neuron-hostname-survey
description=Survey expected Neurons by MAC/subnet evidence and resolve current hostnames.
script=scripts/sas_neuron_hostname_survey.sh
mutation_allowed=false
requires_manifest=true
requires_nmap=true
max_hosts=32
scan_mode=host-discovery
```

## Safety Model

Field command capsules are not mutation workflows.

Default posture:

- collect evidence
- resolve identities
- classify confidence
- export reports
- recommend next step

They should not:

- change AD
- rename devices
- write registry settings
- modify Group Policy
- install software
- remap printers
- run unrestricted subnet sweeps

Mutation belongs in a later workflow with explicit approvals, dry-run mode, and separate guardrails.

## Design Principle

Short QR. Clear profile. Bounded survey. Durable evidence.

That is the field command capsule model.
