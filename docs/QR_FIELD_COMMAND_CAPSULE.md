# QR Field Command Capsule

## Core Insight

A QR code in SysAdminSuite is a **field command capsule**.

It is not merely a shortcut. It is a compact, scannable trigger for an approved profile-driven field workflow that can survey a local machine, room, cart, subnet slice, or device class such as Neurons.

```text
QR -> profile -> approved survey lane -> evidence package
```

## Correct Product Model

The incomplete model is:

```text
scan QR -> run one local script -> export one local report
```

The intended model is:

```text
scan QR -> launch a field command capsule -> survey an operational target set
```

## Layer Model

| Layer | Role |
|---|---|
| QR | Short scannable trigger, not the full script body. |
| Launcher | Validates the profile and field context. |
| Profile | Declares approved intent, runner, survey lane, safety posture, and output contract. |
| Survey lane | Performs the actual workflow. |
| Evidence package | Stores raw artifacts, parsed summaries, logs, and review reports. |

## Required Doctrine

Every QR field command capsule must preserve:

```text
Recon -> Decide -> Act -> Log -> Export
```

## Correct QR Payload Shape

```bash
bash scripts/sas_qr_run.sh --profile neuron-hostname-survey -- \
  --manifest GetInfo/Config/NeuronTargets.unresolved.csv \
  --nmap-xml survey/artifacts/site_neuron_discovery.xml \
  --output survey/output/neuron_resolved_targets.csv \
  --review-output survey/output/neuron_probe_review.csv
```

The QR is the trigger. The profile is the intent. The repository is the controlled implementation.

## First-Class Use Case: Neuron Hostname Survey

The initial high-value use case is surveying expected Neurons for current IP and hostname using MAC/subnet evidence.

```text
Hostname is a label.
MAC is network evidence.
Serial is hardware evidence.
```

The first profile delegates to the existing saved-evidence Neuron matcher. This lets a technician scan a QR and launch the complete matching/review lane instead of manually assembling commands.

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
