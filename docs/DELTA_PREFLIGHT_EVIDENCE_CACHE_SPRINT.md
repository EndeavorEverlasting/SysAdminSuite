# Delta Preflight Evidence Cache Sprint Contract

## Purpose

This document defines the implementation-ready sprint for a **delta preflight / local evidence cache** lane in SysAdminSuite.

The goal is to prevent unnecessary network packets and technician rework by comparing a requested serial/target population against local, already ascertained artifacts before any ping or TCP preflight runs.

The field question is not:

```text
Can we ping everything again?
```

The field question is:

```text
What do we already know locally, what is stale, what conflicts, and what still deserves packets?
```

## Replit harvest insights carried forward

The Replit harvest history is useful, but it is not a direct merge source. Treat it as a product-insight archive and promote only reviewed logic into clean product branches.

Standing insights to preserve:

1. **Quarantine is reference, not product.** Do not merge `replit-harvest/` wholesale. Promote deliberately in small reviewed slices.
2. **Offline/test mode comes first.** Live probing is trusted only after fixtures, contracts, and local artifact processing are stable.
3. **PowerShell remains active Windows tooling.** Current Northwell field preflight is PowerShell-first. Do not collapse field guidance back into Replit/Linux defaults.
4. **Runtime mismatch is not product failure.** Missing Windows tools in Replit/Linux are expected environment mismatch, not a reason to rewrite the field lane for Linux.
5. **Survey before mutation. Report before action.** Delta planning performs no network activity and mutates no targets.
6. **Generated operational artifacts stay local.** CSV/HTML/JSON/log outputs with live hostnames, serials, MACs, users, rooms, departments, or locations must never be committed.
7. **Ping failure is not evidence failure.** A host can have DNS, AD, serial, MAC, or identity evidence even when ICMP fails. Preserve the path by which evidence was obtained.
8. **Do not flatten evidence.** Keep separate evidence lanes for ping reachable, DNS only/no ping, identity observed/no ping, offline fixture, unreachable/off, conflicting evidence, and manual review.
9. **Small chunks beat terminal-paste heroics.** Future implementation should be decomposed into small commits: fixtures, contracts, planner, dashboard/readme integration.

## Product principle

Network preflight should be the last-mile action, not the first pass.

```text
requested serial population
  -> local evidence comparison
  -> delta decision plan
  -> reduced probe target file
  -> network preflight only for the delta
  -> reconciliation/report artifacts
```

## Non-goals

This sprint must not create a new scanner.

It must not:

- ping the requested population itself
- run Nmap / Naabu / Test-NetConnection
- query live AD
- collect credentials
- mutate target machines
- install software
- create remote tasks
- suppress telemetry
- hide network activity
- broaden scope beyond the approved source population

It only plans what should be probed later.

## Source/input roots

The delta planner may read requested target/serial material from:

```text
targets/local/
logs/targets/
survey/input/   # normalized staging only
```

The planner must reject live input from arbitrary paths unless an explicit, clearly labeled nonstandard override exists.

## Evidence roots

The planner may read prior local evidence from codified ignored output roots:

```text
survey/output/network_preflight/
survey/output/ad_registered_population/
survey/output/ad_candidate_pool/
survey/output/SysAdminSuite_Artifacts/
survey/output/cybernet_progress_summary.csv
survey/output/cybernet_progress_summary.json
logs/nmap/
survey/artifacts/
```

It should support explicit evidence file arguments as well as directory discovery.

## Required output root

The planner writes a self-contained local ignored run directory:

```text
survey/output/delta_preflight/<run_id>/
```

Required files:

```text
delta_preflight_plan.csv
to_probe_targets.txt
skipped_recent_evidence.csv
review_required.csv
delta_summary.json
README.txt
```

No generated delta output is committed.

## Evidence model

The delta planner is a reconciliation layer over evidence, not a truth oracle.

| Evidence | Meaning | Can skip ping? | Can confirm serial? |
|---|---|---:|---:|
| Recent network preflight reachable | Target recently responded to ping/TCP evidence | Yes, within TTL | No |
| Recent network preflight silent | Target was recently silent/unreachable | Maybe, if retry not useful | No |
| AD registered row | Directory registration / population evidence | Maybe, if paired with recent reachability | No |
| AD candidate-pool row | Naming-convention candidate | No by itself | No |
| Live identity row | Host reported serial/MAC/identity evidence | Usually yes | Yes, if serial matches |
| Tracker row | Planned/deployed operational attribution | Maybe | No by itself |
| Offline fixture | Test evidence only | No for live | No |

## Freshness defaults

Recommended defaults:

```text
ReachabilityTtlHours = 24
IdentityTtlDays = 7
```

Interpretation:

- Reachability older than the TTL becomes stale and can be probed again.
- Identity evidence older than the TTL should warn, but should not be casually discarded.
- Operator override can force reprobe, but the reason must appear in the plan.

## Requested input schema

The requested population can be serial-first, hostname-first, or already normalized.

Recognized input columns:

```text
Serial
ExpectedSerial
Cybernet Serial
Cybernet S/N
Neuron Serial
Neuron S/N
HostName
Hostname
ComputerName
ExpectedHostname
Target
Identifier
DeviceType
Site
Source
```

Rules:

1. Prefer explicit serial columns for population counting.
2. Prefer explicit hostname columns for probe target selection.
3. Treat ambiguous `Identifier` as probe-ready only if explicitly typed as hostname/IP by an existing normalized source.
4. Serial-only rows are not pingable.
5. A serial with exactly one validated hostname can become probe-ready.
6. A serial with zero hostnames is review-required.
7. A serial with multiple hostnames is review-required unless one is identity-confirmed.

## Prior evidence parsing

The planner should normalize prior evidence into an internal evidence table keyed by:

```text
NormalizedSerial
NormalizedHostname
NormalizedTarget
NormalizedMac
EvidenceSourceFile
EvidenceTimestamp
```

Where possible, parse evidence timestamps from source columns such as:

```text
Timestamp
GeneratedAt
probed_at
ProbedAt
ObservedAt
```

If no timestamp exists, classify freshness as unknown and require either review or reprobe depending on the evidence class.

## Decision statuses

Every requested row must receive exactly one primary decision.

```text
PROBE_REQUIRED_NO_EVIDENCE
PROBE_REQUIRED_STALE_EVIDENCE
PROBE_REQUIRED_CONFLICTING_EVIDENCE
PROBE_REQUIRED_OPERATOR_FORCED
SKIP_RECENT_REACHABLE
SKIP_RECENT_IDENTITY_CONFIRMED
SKIP_ALREADY_TRACKED
SKIP_RECENTLY_SILENT_WITHIN_COOLDOWN
REVIEW_REQUIRED_SERIAL_ONLY
REVIEW_REQUIRED_MULTIPLE_HOSTNAMES
REVIEW_REQUIRED_AD_VARIANT_ONLY
REVIEW_REQUIRED_PREFIX_SITE_MISMATCH
REVIEW_REQUIRED_EVIDENCE_TIMESTAMP_UNKNOWN
BLOCKED_NO_PROBE_READY_HOST
```

## Required plan schema

`delta_preflight_plan.csv` must include:

```text
InputRowId
InputSource
Serial
RequestedHostname
ResolvedHostname
CandidateHostnames
ProbeTarget
LastReachabilityStatus
LastReachabilityTimestamp
LastReachabilitySource
LastIdentityStatus
LastIdentityTimestamp
LastIdentitySource
ADCandidateStatus
ADCandidateSource
TrackerStatus
Decision
DecisionReason
ReviewRequired
EvidenceSourceFiles
```

## Probe target file contract

`to_probe_targets.txt` must contain only probe-ready hostnames/IPs selected by the delta plan.

Rules:

- one target per line
- no serial-only values
- no duplicate targets
- no AD variant-only targets unless operator-approved or explicitly classified as probe-eligible by the plan
- no targets from review-required rows
- comments may be included with `#`, but network preflight must ignore them

## Summary contract

`delta_summary.json` must include:

```text
run_id
generated_at
input_source
input_rows
total_serials
probe_required_count
skipped_recent_reachable_count
skipped_identity_confirmed_count
review_required_count
blocked_count
stale_evidence_count
conflicting_evidence_count
to_probe_targets_path
plan_path
review_required_path
skipped_recent_evidence_path
evidence_files_loaded
reachability_ttl_hours
identity_ttl_days
network_activity_performed
```

`network_activity_performed` must always be `false` for the delta planner.

## Replit-derived evidence-path guardrail

Historical Replit/live-serial work exposed an important bug class:

```text
A device may provide identity evidence even when cmd ping cannot reach it.
```

The delta planner must never collapse that into `unreachable` or `reachable` alone. It must preserve how evidence was obtained:

```text
ping_reachable
DNS_only_no_ping
identity_observed_no_ping
offline_fixture
unreachable_or_silent
manual_review_conflict
```

If identity evidence exists but reachability is silent, the row should be classified with a reason like:

```text
SKIP_RECENT_IDENTITY_CONFIRMED
identity observed despite no recent ping; do not reprobe unless forced
```

or, if identity evidence is old:

```text
PROBE_REQUIRED_STALE_EVIDENCE
identity evidence exists but freshness window expired; reprobe target if hostname is probe-ready
```

## Planner algorithm

1. Load requested rows from an approved source.
2. Normalize serials, hostnames, MACs, and target identifiers.
3. Load prior evidence files from configured local evidence roots.
4. Build an evidence index by serial, hostname, target, and MAC.
5. For each requested row:
   - resolve known hostnames
   - attach prior reachability evidence
   - attach prior identity evidence
   - attach AD registered / candidate evidence
   - attach tracker/progress evidence
   - classify freshness
   - choose one decision
6. Write the full plan.
7. Write `to_probe_targets.txt` from probe-required, probe-ready rows only.
8. Write skipped/review sidecar CSVs.
9. Write summary JSON.
10. Print counts and next command.

## PowerShell-first field flow

Run in Windows PowerShell:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-delta-preflight-plan.ps1 `
  -InputFile .\targets\local\approved_serials_or_targets.csv `
  -ReachabilityTtlHours 24 `
  -IdentityTtlDays 7
```

Then run network preflight only on the reduced target file:

```powershell
.\survey\sas-network-preflight.ps1 `
  -TargetFile .\survey\output\delta_preflight\<run_id>\to_probe_targets.txt `
  -Ports 135,445,3389,9100
```

The dashboard should show this as:

```text
1. Load approved source.
2. Compare local evidence.
3. Review skipped / probe / review counts.
4. Probe only the generated delta target file.
5. Feed new evidence back into reconciliation.
```

## Runtime doctrine

Current field path is PowerShell-first.

Replit/Linux is not the runtime target for this lane. If future tests run in Replit/Linux and Windows tools are missing, classify that as environment mismatch, not product failure.

Do not reintroduce Git Bash / MINGW64 as the field path for this PowerShell lane.

## Implementation surfaces

Preferred files for the implementation sprint:

```text
survey/sas-delta-preflight-plan.ps1
scripts/SasDeltaEvidenceCache.psm1
Tests/Pester/DeltaPreflight.Tests.ps1
Tests/bash/test_delta_preflight_contracts.sh
docs/FIELD_NETWORK_PREFLIGHT.md
survey/fixtures/delta_preflight_requested.sample.csv
survey/fixtures/delta_preflight_evidence.sample.csv
```

Keep fixtures synthetic only.

## Required tests

Tests must prove:

1. Recent reachable evidence skips a target.
2. Stale reachable evidence requires reprobe.
3. Identity-confirmed serial skips ping unless forced.
4. Serial-only row is review-required.
5. Multiple-hostname serial is review-required.
6. AD variant-only row is review-required, not probe-confirmed.
7. Prefix/site mismatch is review-required.
8. Conflicting identity/reachability evidence requires review or reprobe.
9. `to_probe_targets.txt` contains only probe-ready hostnames/IPs.
10. Duplicate probe targets are deduplicated.
11. Planner performs no network commands.
12. Planner writes all outputs under `survey/output/delta_preflight/`.
13. No live target/evidence files are committed.
14. Replit/Linux runtime mismatch is not treated as product failure.
15. PowerShell remains the field lane for this workflow.

## Static forbidden patterns

The delta planner and field docs must not introduce:

```text
Name -like '*'
nslookup as default live field command for this lane
ping as planner behavior
Test-NetConnection as planner behavior
nmap as planner behavior
naabu as planner behavior
/tmp live paths
C:\Temp live workflow
Git Bash / MINGW64 as field default
```

Network commands belong in network preflight, not in the delta planner.

## Acceptance criteria

The implementation sprint is complete when:

- Requested serial/target files can be compared to local evidence without sending packets.
- The planner emits a reduced `to_probe_targets.txt` for network preflight.
- Recent, useful evidence skips rework.
- Stale or conflicting evidence is surfaced clearly.
- Serial-only and ambiguous-hostname rows are review-required.
- Ping failure does not erase identity/AD/DNS evidence.
- Dashboard or runbook flow makes delta planning the step before network preflight.
- Tests prove no network activity occurs in the planner.

## Copy-ready next-agent prompt

```text
You are continuing SysAdminSuite.

Current doctrine to implement:
- docs/DELTA_PREFLIGHT_EVIDENCE_CACHE_SPRINT.md
- docs/FIELD_NETWORK_PREFLIGHT.md
- docs/CYBERNET_XLSX_TARGET_INGESTION.md
- docs/AD_REGISTERED_POPULATION.md
- docs/AD_COMPUTER_CANDIDATE_POOL_SPRINT.md

Mission:
Implement a PowerShell-first delta preflight planner that compares requested serials/targets against local evidence before any ping/TCP packets are sent.

Do not create a new scanner.
Do not run network commands in the planner.
Do not use generic fuzzy logic.
Do not commit live evidence.
Do not treat Replit/Linux runtime mismatch as product failure.
Do not collapse PowerShell field tooling into Bash/Linux defaults.

Required entrypoint:
- survey/sas-delta-preflight-plan.ps1

Required outputs:
- survey/output/delta_preflight/<run_id>/delta_preflight_plan.csv
- survey/output/delta_preflight/<run_id>/to_probe_targets.txt
- survey/output/delta_preflight/<run_id>/skipped_recent_evidence.csv
- survey/output/delta_preflight/<run_id>/review_required.csv
- survey/output/delta_preflight/<run_id>/delta_summary.json

Default TTLs:
- ReachabilityTtlHours = 24
- IdentityTtlDays = 7

Decision statuses:
- PROBE_REQUIRED_NO_EVIDENCE
- PROBE_REQUIRED_STALE_EVIDENCE
- PROBE_REQUIRED_CONFLICTING_EVIDENCE
- PROBE_REQUIRED_OPERATOR_FORCED
- SKIP_RECENT_REACHABLE
- SKIP_RECENT_IDENTITY_CONFIRMED
- SKIP_ALREADY_TRACKED
- SKIP_RECENTLY_SILENT_WITHIN_COOLDOWN
- REVIEW_REQUIRED_SERIAL_ONLY
- REVIEW_REQUIRED_MULTIPLE_HOSTNAMES
- REVIEW_REQUIRED_AD_VARIANT_ONLY
- REVIEW_REQUIRED_PREFIX_SITE_MISMATCH
- REVIEW_REQUIRED_EVIDENCE_TIMESTAMP_UNKNOWN
- BLOCKED_NO_PROBE_READY_HOST

Validation:
- Pester suite
- offline survey tests
- bash/static contracts
- dashboard smoke if dashboard copy changes

Merge policy:
merge_when_green.
```
