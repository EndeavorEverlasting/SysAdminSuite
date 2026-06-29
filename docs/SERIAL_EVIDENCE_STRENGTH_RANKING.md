# Serial Evidence Strength Ranking

## Purpose

This document codifies the next gap in the Cybernet / Neuron survey workflow: before probing, skipping, or reconciling a serial, SysAdminSuite must rank the strength of the available evidence and choose the correct handoff.

The spreadsheet/workbook remains the primary field artifact when it defines the device population. Generated text, JSON, and CSV files are runtime handoffs and reports, not replacements for the workbook.

## Core principle

A serial can move through multiple evidence bridges:

```text
Serial
  -> spreadsheet / tracker population evidence
  -> hostname evidence
  -> IP evidence
  -> subnet/location evidence
  -> MAC evidence
  -> AD/DNS evidence
  -> packet reachability evidence
  -> approved identity evidence
  -> reconciliation artifact
```

Those bridges are not equal. The workflow must never treat reachability as identity, AD candidate evidence as proof, or subnet inference as scan authorization.

## Evidence strength ranking

| Rank | Evidence path | Strength | Confirms serial identity? | Good for |
|---:|---|---|---:|---|
| 1 | Approved identity collection: serial observed from host via approved WMI/CIM/SCCM/MDM/vendor inventory | Strongest | Yes, when serial matches requested population | Marking a serial identity-confirmed |
| 2 | Serial + MAC + current IP from approved inventory/DHCP/ARP/switch/exported evidence | Strong | Usually not alone | Locating a probable device and subnet, prioritizing probe |
| 3 | Spreadsheet/workbook or deployment tracker row | Population authority | No | Defining scope, denominator, intended site/device assignment |
| 4 | Exact AD computer registration plus DNS hostname/IP | Medium-high | No | Registration/routing evidence, target candidate generation |
| 5 | AD computer candidate from naming-convention variant | Medium / review | No | Finding possible typo/naming candidates |
| 6 | DNS A/reverse lookup or prior hostname-to-IP association | Medium | No | IP/subnet bridge, routing clue |
| 7 | Ping/TCP reachable from network preflight | Medium-low | No | Alive/reachable signal only |
| 8 | Packet pipeline open-port evidence | Medium-low | No | Service reachability hint only |
| 9 | Silent/no response/no open profile ports | Weak negative | No | Retry/review/cooldown decision, not absence proof |
| 10 | Offline fixture/test evidence | Test-only | No | CI and parser validation only |

## Decision rules

1. **Identity proof outranks reachability.** If a serial was recently identity-confirmed by an approved source, do not ping it again unless the operator forces reprobe.
2. **Spreadsheet population outranks ad hoc target files.** If generated targets disagree with the workbook-backed manifest, the manifest and delta plan must explain the mismatch.
3. **IP/subnet evidence is a bridge, not proof.** `Serial -> IP -> subnet` is a valid operational path, but it requires an evidence bridge from serial to IP.
4. **Reachability is not identity.** Ping, TCP, Naabu, and similar packet evidence can show that something responded at a network location; they cannot prove which serial responded.
5. **AD candidate evidence is review evidence.** A naming-convention variant can justify exact AD lookup or review, not automatic serial confirmation.
6. **Silence is not absence.** ICMP or TCP silence may be firewall, power, VLAN, routing, or policy. Preserve other evidence paths.
7. **Subnet inference narrows review.** It does not authorize broader scanning by itself.

## Canonical serial-to-artifact handoffs

### 1. Workbook population handoff

```text
approved workbook / tracker tab
  -> ingestion / normalization engine
  -> survey/output/cybernet_*.csv and summary artifacts
  -> survey/input/<lane>/<run_id>/staged targets when needed
```

Use when the spreadsheet defines the serial population.

Required artifacts:

```text
survey/output/cybernet_alejandro_unique_serials.csv
survey/output/cybernet_tracker_unique_serials.csv
survey/output/cybernet_alejandro_untracked.csv
survey/output/cybernet_progress_summary.json
survey/output/cybernet_progress_summary.csv
```

### 2. Serial to IP/subnet handoff

```text
Serial
  -> approved bridge to IP or MAC/IP evidence
  -> subnet/location inference
  -> staged probe target only if probe-worthy
  -> reachability artifact
```

Valid bridge sources include approved identity CSVs, tracker enrichment, AD/DNS exports, DHCP/ARP/switch exports, or prior local evidence. A serial-only row cannot be converted to IP without one of these bridges.

Required outputs:

```text
survey/output/delta_preflight/<run_id>/delta_preflight_plan.csv
survey/input/delta_preflight/<run_id>/to_probe_targets.txt
survey/output/network_preflight/network_preflight_<timestamp>.csv
```

### 3. Serial to hostname/DNS/IP handoff

```text
Serial
  -> exactly one validated hostname
  -> DNS/IP
  -> subnet
  -> reachability check if evidence is stale or missing
```

Use when the workbook/tracker/AD evidence provides a single validated hostname. Multiple hostnames remain review-required.

### 4. Serial to AD candidate handoff

```text
Serial + expected hostname/site
  -> AD computer candidate pool
  -> exact AD lookup only
  -> candidate/review artifact
```

Candidate-pool evidence does not confirm the serial.

Required output:

```text
survey/output/ad_candidate_pool/<run_id>/ad_computer_candidates.csv
```

### 5. Serial to packet-pipeline handoff

```text
Serial-backed reduced target set
  -> survey/input/delta_preflight/<run_id>/to_probe_targets.txt
  -> approved packet profile
  -> survey/output/packet_pipeline/<run_id>/packet artifacts
```

Packet evidence is reachability/service evidence only.

## Delta planner scoring model

The delta planner should compute an evidence strength tier for every requested serial row.

Recommended tiers:

```text
IDENTITY_CONFIRMED
PROBABLE_DEVICE_LOCATION
POPULATION_ONLY
REGISTERED_AD_TARGET
AD_VARIANT_REVIEW
DNS_OR_SUBNET_ONLY
REACHABILITY_ONLY
PACKET_SERVICE_ONLY
NEGATIVE_OR_SILENT
TEST_ONLY
```

Required `delta_preflight_plan.csv` additions:

```text
EvidenceStrengthTier
StrongestEvidencePath
SerialIdentityConfirmed
ProbeWorthiness
PreferredNextHandoff
```

Recommended `ProbeWorthiness` values:

```text
skip_identity_confirmed
skip_recent_reachability
probe_stale_or_missing
review_required
blocked_no_probe_ready_target
operator_forced
```

Recommended `PreferredNextHandoff` values:

```text
identity_reconciliation
delta_network_preflight
ad_candidate_review
subnet_location_review
packet_pipeline_profile
spreadsheet_gap_review
```

## Minimal next-gap implementation contract

The next implementation sprint should not start by adding another network probe.

It should first add evidence ranking to the delta planner:

1. Load workbook-backed manifest rows.
2. Load local evidence artifacts.
3. Attach all evidence paths by serial, hostname, MAC, IP, and AD candidate.
4. Rank the strongest evidence per serial.
5. Decide whether the serial is confirmed, skipped, probe-worthy, or review-required.
6. Emit staged target files only for probe-worthy rows.
7. Preserve reason strings for every skip/review/probe decision.

## Copy-ready handoff snippet

```text
Top focus: implement evidence strength ranking before adding more probing.

The spreadsheet/workbook remains the primary artifact for serial population. Runtime text files are generated handoffs only.

For every serial row, compute:
- EvidenceStrengthTier
- StrongestEvidencePath
- SerialIdentityConfirmed
- ProbeWorthiness
- PreferredNextHandoff

Ranking order:
1. approved identity collection matching serial
2. serial + MAC + current IP from approved exported evidence
3. workbook/tracker population row
4. exact AD registration plus DNS/IP
5. AD candidate-pool naming variant
6. DNS/IP/subnet association
7. ping/TCP reachability
8. packet-pipeline open-port evidence
9. silent/no-response evidence
10. offline fixture/test evidence

Do not treat ping, TCP, Naabu, DNS, AD candidate, or subnet inference as serial proof.
Do not hand-build live target text files from the spreadsheet.
Use ingestion engines to convert the workbook/export into manifests, reports, and staged target files.
Probe only rows whose evidence ranking says probing is still worthwhile.
```
