# QR Field Command Capsule

## Core Insight

A QR code in SysAdminSuite is a **field command capsule**.

It is not merely a shortcut.

It is a compact, scannable trigger for an approved profile-driven field workflow that can survey a local machine, room, cart, subnet slice, or device class such as Neurons.

```text
QR -> profile -> approved survey lane -> evidence package
```

## Why This Matters

The small version of the idea is:

```text
scan QR -> run one local baseline script -> export one local report
```

That is useful, but incomplete.

The correct product model is:

```text
scan QR -> launch a field command capsule -> survey an operational target set
```

## Layer Model

| Layer | Role |
|---|---|
| QR | Short scannable trigger, not the full script body. |
| Launcher | Validates the profile and field context. |
| Profile | Declares approved intent, script, safety posture, and export behavior. |
| Survey lane | Performs the actual workflow. |
| Evidence package | Stores raw artifacts, parsed summaries, logs, and review reports. |

## Required Doctrine

Every QR field command capsule must preserve:

```text
Recon -> Decide -> Act -> Log -> Export
```

## Correct QR Payload Shape

Good:

```bash
bash scripts/sas_qr_run.sh --profile neuron-hostname-survey
```

Bad:

```text
QR contains a full script body or giant one-liner.
```

The QR is the trigger. The profile is the intent. The repository is the controlled implementation.

## First-Class Use Case: Neuron Hostname Survey

The initial high-value use case is surveying expected Neurons for current IP and hostname using MAC/subnet evidence.

Identity posture:

```text
Hostname is a label.
MAC is network evidence.
Serial is hardware evidence.
```

Target workflow:

```text
QR scan
  -> sas_qr_run.sh
  -> profile: neuron-hostname-survey
  -> load expected Neuron manifest
  -> consume saved discovery evidence
  -> match expected MACs to observed addresses
  -> resolve or report hostnames
  -> export review package
```

## Safety Model

Default posture is read-only and advisory:

- collect evidence
- resolve identities
- classify confidence
- export reports
- recommend next step

Mutation belongs in a separate approved workflow with explicit dry-run behavior and guardrails.

## Design Principle

Short QR. Clear profile. Bounded survey. Durable evidence.
