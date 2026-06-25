# Cybernet XLSX Target Ingestion

Read-only, offline ingester that converts Alejandro-style Cybernet workbooks plus optional enrichment trackers into the normalized survey manifest schema used by SysAdminSuite Bash tooling.

## Field handoff

Use this lane when Alejandro's workbook defines the **field population** and the latest **Active Deployment Tracker** supplies the **unique serial inventory** for cross-check.

| Step | Input | Output (local, gitignored) |
|------|-------|----------------------------|
| 1. Diff | Alejandro workbook + latest tracker workbook | Unique serial inventories, already tracked, untracked manifest under `survey/output/` |
| 2. Ingest | Alejandro workbook + tracker `--enrichment` | Manifest, enrichment report, gaps CSV under `survey/output/` |
| 3. Resolve hosts | Manifest with `HostName` populated | Optional pass through `sas-survey-targets.sh` |
| 4. Identity (host-resolved only) | Ping, then approved WMI; SSH last | `workstation_identity.csv`, optional `cybernet_evidence.csv` |

**Posture**

- Alejandro rows and tracker enrichment define **registered population** — not reachability proof.
- Naabu/Nmap and other network probes are **reachability validation only** after population is fixed. See [`LOW_NOISE_SURVEY_DOCTRINE.md`](LOW_NOISE_SURVEY_DOCTRINE.md).
- Generated operational CSVs stay on the admin box in gitignored paths (`survey/output/`, `targets/local/`). Do not commit live workbooks or generated operational CSVs; sanitized fixture CSVs may still be tracked per repo `.gitignore` policy.
- Assume authorized traffic may be monitored. Do not describe this workflow as stealth, evasion, or log bypass.

**Evidence classification (identity transport)**

| Observation | Classification | Meaning |
|-------------|----------------|---------|
| WMI returns host, serial, or MAC | `IdentityCollected` (adapter: `WmiIdentityCollected`) | Approved identity transport succeeded |
| Ping/DNS OK, no identity transport | `ReachableNeedsApprovedIdentityTransport` | Reachable; enable approved WMI before revisiting |
| SSH disabled or connection refused | Notes: `SSHFailed:*` / policy block | **Environment/policy evidence** — not proof the Cybernet is offline |
| Guest or wrong network segment | `ENVIRONMENT_BLOCKED_GUEST_NETWORK` | Retest from correct network before product triage |

See [`TEST_RESULT_CLASSIFICATION.md`](TEST_RESULT_CLASSIFICATION.md) for full triage rules.

## Targets intake doctrine

| Location | Role |
|----------|------|
| `targets/` | Official tracked intake hub (docs, schemas, sanitized fixtures only) |
| `targets/local/` | Preferred **gitignored** local intake beside the hub |
| `logs/targets/` | Preserved historical local evidence — **do not delete, move, or commit** |
| `survey/input/` | Runtime staging (gitignored) |
| `survey/output/` | Generated manifests and reports (gitignored) |

- The ingester reads **explicit workbook paths** wherever they live locally.
- You do **not** need to migrate existing `logs/targets/` files; point `--workbook` and `--enrichment` at their current paths.
- Outputs are target **manifests**, not network evidence. Do not treat them as proof of reachability.

## Prerequisites

- Python 3 with `openpyxl` (`pip install openpyxl`)
- Git Bash or MSYS2 Bash on Windows (wrapper is Bash-first)

## Primary workbook (Alejandro list)

Expected sheets:

| Sheet pattern | Columns | Notes |
|---|---|---|
| `AKBAR WAVE …` | A = serial | Serial-only wave rows |
| `PO …` | A = hostname, B = serial | Blank rows skipped |

Alejandro serial-only rows are the baseline population. Hostname and MAC fields may be empty until enrichment.

## Enrichment — latest tracker unique serial inventory

Pass the **most recent** Active Deployment Tracker (and any wave/supplement workbooks) with `--enrichment`. The ingester merges enrichment rows by **normalized serial** or **hostname** and emits a before/after comparison in the enrichment report.

Recognized tracker sheets:

| Sheet | Purpose |
|---|---|
| `Deployments` | Cybernet hostname, serial, MAC from deployment tracker |
| `SSUH Configs` | Configured Cybernet / Neuron identity pairs |
| `configured cybernets*` | Hostname-centric configured Cybernet rows |
| `CDW Stock` | Serial numbers from stock tab |
| `SSUH Host` | Hostname list (column A) |
| `Neuron Cybernet` | PC name + Cybernet serial (+ Neuron MAC when present) |

**How to read the comparison**

- **`enrichment_report.csv`** — each Alejandro row with `InputSerial` / `InputHostName` vs `ResolvedHostName` / `ResolvedSerial` / `ResolvedMACAddress` after tracker merge.
- **`ResolutionStatus`** — `FULL` (host + serial + MAC), `PARTIAL` (two of three), `MINIMAL` (one or none).
- **`gaps.csv`** — rows that did not reach `FULL`; use for technician follow-up (stale hostname, serial-only wave row, tracker drift).
- Tracker serials that never appear in the Alejandro workbook are **not** auto-added to the manifest; reconcile gaps manually or extend enrichment sources.

## Alejandro vs deployment tracker diff

When Alejandro's workbook is the authoritative Cybernet serial source, compare its unique serial inventory against the latest deployment tracker before probing anything live:

```bash
bash survey/sas-cybernet-tracker-diff.sh \
  --alejandro "<alejandro-workbook>.xlsx" \
  --tracker "<deployment-tracker-workbook>.xlsx" \
  --output-prefix survey/output/cybernet
```

Point `--alejandro` and `--tracker` at your local workbook paths. Keep live workbooks out of
git and follow [`LOCAL_REFERENCE_POLICY.md`](LOCAL_REFERENCE_POLICY.md) for local file handling.

The diff is read-only against both workbooks and writes local operational CSVs:

- `survey/output/cybernet_alejandro_unique_serials.csv`
- `survey/output/cybernet_tracker_unique_serials.csv`
- `survey/output/cybernet_alejandro_already_tracked.csv`
- `survey/output/cybernet_alejandro_untracked.csv`
- `survey/output/cybernet_tracker_duplicate_exceptions.csv`
- `survey/output/cybernet_progress_summary.json`
- `survey/output/cybernet_progress_summary.csv`

Comparison rules:

- Normalize serials by trimming whitespace and uppercasing.
- Treat Alejandro rows as a unique serial inventory; duplicate Alejandro rows collapse into one serial with a row count.
- Exclude an Alejandro serial from the untracked manifest when that serial already appears in the deployment tracker.
- Emit duplicate exceptions only when the same normalized identifier appears in more than one tracker row marked `Deployed = Yes`. Identifier classes checked are Cybernet hostname, Cybernet serial, Cybernet MAC, Neuron MAC, and Neuron S/N.
- Repeated non-deployed tracker identifiers are planning history, not duplicate exceptions.

`cybernet_alejandro_untracked.csv` uses the same manifest schema as the ingester. Serial-only rows are retained for tracking, but only rows with a resolved `HostName` are ready for live WMI/ping identity checks. When one Alejandro serial maps to more than one hostname, the row stays serial-keyed (not probe-ready) and the candidate hostnames are preserved in `Source` as `review:ambiguous_hostnames=...`; the tool does not arbitrarily pick one hostname.

## Serial-first progress summary

Every diff run also emits a serial-first progress summary so a technician can answer
"how many Cybernets are left?" without reading raw logs. The **denominator is always unique
Alejandro serials**, never hostname rows. A console progress bar prints by default:

```text
[sas-cybernet-tracker-diff] [##########----------] 52.4% 129/246 serials surveyed | 117 remaining | 38 need identity | 12 ambiguous
```

The same numbers are written to machine-readable files (gitignored under `survey/output/`):

- `cybernet_progress_summary.json`
- `cybernet_progress_summary.csv`

Stable fields (documented; safe for a future dashboard to consume):

| Field | Meaning |
|---|---|
| `TotalSerialTargets` | Unique Alejandro serials (the survey population denominator) |
| `SurveyedSerials` | Serials present in the deployment tracker, plus untracked serials confirmed by identity evidence |
| `RemainingSerials` | `TotalSerialTargets - SurveyedSerials` |
| `HostResolvedSerials` | Serials with exactly one validated hostname (probe-ready) |
| `SerialOnlyReviewRequired` | Serials with zero hostnames (stay serial-keyed, review-required) |
| `AmbiguousHostnameSerials` | Serials with two or more hostnames (never auto-picked) |
| `ADCandidateSerials` | Serials with an AD candidate hostname/serial (enrichment only, not proof) |
| `PingReachableCandidates` | Serials whose hostname is ping-reachable (reachability only, not proof) |
| `NeedsPrivilegedIdentity` | Reachable serials still lacking identity confirmation |
| `PercentComplete` | `100 * SurveyedSerials / TotalSerialTargets` (one decimal) |
| `PopulationAuthority` | Always `alejandro_serials` |
| `GeneratedAt` | UTC ISO-8601 timestamp |

Doctrine guardrails baked into these counts:

- A serial with exactly one validated hostname is probe-ready; zero or multiple hostnames stay
  serial-keyed and review-required.
- Only `IdentityCollected` evidence (via `--identity-csv`) can mark an **untracked** serial surveyed.
  Ping reachability (`--preflight-csv`) and AD candidates (`--ad-serial-csv`) raise candidate
  confidence but never confirm a serial.
- Optional evidence inputs are read-only and enrichment-only; the population authority is the
  Alejandro serial inventory.

Flags:

```bash
bash survey/sas-cybernet-tracker-diff.sh \
  --alejandro "<alejandro-workbook>.xlsx" \
  --tracker "<deployment-tracker-workbook>.xlsx" \
  --output-prefix survey/output/cybernet \
  --identity-csv survey/output/cybernet_workstation_identity.csv \
  --preflight-csv survey/output/cybernet_network_preflight.csv \
  --ad-serial-csv survey/output/cybernet_ad_serials.csv
```

Use `--no-progress` to suppress the console bar (summary files are still written). All progress
outputs are operational and remain gitignored under `survey/output/`; a dashboard can consume the
JSON/CSV in a later sprint.

## Cybernet reconciliation HTML report

After tracker diffing and approved identity collection, build a local offline report that reconciles
the Alejandro serial population, the latest deployment tracker, `workstation_identity*.csv`, and
`network_preflight*.csv` evidence:

```bash
bash survey/sas-cybernet-reconcile-report.sh \
  --alejandro "<alejandro-workbook>.xlsx" \
  --tracker "<deployment-tracker-workbook>.xlsx" \
  --identity-glob "survey/output/SysAdminSuite_Artifacts/workstation_identity*.csv" \
  --preflight-csv "survey/output/SysAdminSuite_Artifacts/network_preflight.csv" \
  --output-dir survey/output/cybernet_reconciliation_report
```

The report is read-only against workbook and CSV inputs. It writes a self-contained site under
`survey/output/cybernet_reconciliation_report/`, which is ignored by repo policy:

- `index.html` for overview tiles and coverage context
- `confirmations.html` for `ConfirmedInTracker`
- `duplicates.html` for observed duplicate serials and tracker duplicate exceptions
- `conflicts.html` for serial and MAC conflicts
- `drift.html` for serial match with hostname drift
- `unaccounted.html` for observed serials missing from both Alejandro and tracker
- `coverage.html` for reachable-needs-identity and unreachable gaps
- `remaining.html` for tracker or Alejandro serials not observed in supplied identity evidence
- `anomalies.html` for bounded hostname typo/site-affinity review candidates
- `style.css` and `data.js` for offline rendering with relative links only

The generated HTML and `data.js` may contain live hostnames, serials, MACs, and reachability
evidence. Keep those files local under `survey/output/`; commit only the generator, wrapper, tests,
and docs. The report uses scope control and evidence minimization: no network probes are launched,
no credentials are used, and no target systems are mutated.

## Command

Example using ignored local intake under `targets/local/` (preferred for new work). Replace the
placeholders with your local workbook paths; see [`LOCAL_REFERENCE_POLICY.md`](LOCAL_REFERENCE_POLICY.md)
for local file handling:

```bash
bash survey/sas-cybernet-xlsx-targets.sh \
  --workbook "<alejandro-workbook>.xlsx" \
  --enrichment "<deployment-tracker-workbook>.xlsx" \
  --enrichment "<wave-supplement-workbook>.xlsx" \
  --output survey/output/cybernet_alejandro_targets.csv \
  --report survey/output/cybernet_alejandro_enrichment_report.csv \
  --gaps survey/output/cybernet_alejandro_gaps.csv \
  --device-type Cybernet
```

Historical local evidence under `logs/targets/` remains valid — pass those local paths instead if you have not migrated:

```bash
bash survey/sas-cybernet-xlsx-targets.sh \
  --workbook "<local-alejandro-workbook>.xlsx" \
  --enrichment "<local-deployment-tracker-workbook>.xlsx" \
  --output survey/output/cybernet_alejandro_targets.csv
```

Defaults write to `survey/output/cybernet_alejandro_*.csv` when `--output`, `--report`, or `--gaps` are omitted.

## Outputs

### Manifest CSV

Schema (handoff to `sas-survey-targets.sh` and field survey scripts):

```text
Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source
```

### Enrichment report

Per-target resolution after cross-source merge:

- `ResolutionStatus`: `FULL` (host + serial + MAC), `PARTIAL` (two of three), `MINIMAL` (one or none)
- Input vs resolved hostname, serial, and MAC columns
- `GapNote` when fields remain missing

### Gap CSV

Subset of targets that did not reach `FULL` resolution, with `GapReason` (for example `missing:HostName,MACAddress`).

## Next step — survey manifest resolver

After ingestion or diff, optionally pass the manifest through the Bash resolver:

```bash
bash survey/sas-survey-targets.sh \
  --device-type Cybernet \
  --csv survey/output/cybernet_alejandro_untracked.csv \
  --output survey/output/cybernet_targets_resolved.csv
```

## Host-resolved candidates — ping and WMI before SSH

Run identity collection only for targets with a resolved hostname in `cybernet_alejandro_untracked.csv` or the enriched manifest.

**1. Build a host-only target list**

```bash
python3 - survey/output/cybernet_alejandro_untracked.csv survey/output/cybernet_host_resolved.txt <<'PY'
import csv, sys
manifest, out = sys.argv[1:3]
seen = []
with open(manifest, newline='', encoding='utf-8-sig') as f:
    for row in csv.DictReader(f):
        host = (row.get('HostName') or '').strip()
        if host and host not in seen:
            seen.append(host)
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(seen) + ('\n' if seen else ''))
print(f'Wrote {len(seen)} host-resolved target(s) to {out}')
PY
```

**2. Network preflight (DNS + ping + optional TCP)**

```bash
bash bash/transport/sas-network-preflight.sh \
  --targets-file survey/output/cybernet_host_resolved.txt \
  --ports 135,445 \
  --output survey/output/cybernet_host_preflight.csv
```

**3. Workstation identity — ping first, WMI when approved, SSH only if explicitly enabled**

The identity adapter always resolves DNS and runs ping before any optional transport. With `--allow-wmi`, WMI runs **before** SSH. Do not enable SSH for Cybernet field paths unless policy explicitly allows it.

```bash
export SAS_WMI_USER='approved_user'
export SAS_WMI_PASS='from-secret-store'
export SAS_WMI_DOMAIN='NSLIJHS'

bash bash/transport/sas-workstation-identity.sh \
  --targets-file survey/output/cybernet_host_resolved.txt \
  --allow-wmi \
  --output survey/output/cybernet_workstation_identity.csv
```

When WMI succeeds, expect `TransportUsed=WMI` and `IdentityStatus=IdentityCollected`. SSH failure notes (`SSHFailed:*`) indicate policy or environment blocks — classify per [`TEST_RESULT_CLASSIFICATION.md`](TEST_RESULT_CLASSIFICATION.md), not as device absence.

**4. Optional — correlate identity against manifest expectations**

```bash
bash survey/sas-collect-cybernet-evidence.sh \
  --manifest survey/output/cybernet_alejandro_untracked.csv \
  --output survey/output/cybernet_evidence.csv
```

Note: `sas-collect-cybernet-evidence.sh` delegates to the workstation identity adapter but does not yet expose `--allow-wmi`. Run step 3 directly when WMI is required; use the evidence collector for manifest merge and tracker serial/MAC comparison when ping-only or SSH paths were used.

Further correlation (DNS, AD, DHCP, approved Nmap) is documented in [`CYBERNET_EVIDENCE_CORRELATION.md`](CYBERNET_EVIDENCE_CORRELATION.md).

## Subnet / location enrichment (optional)

After ingestion, DNS resolution, or preflight, optionally map hostname/IP evidence to likely site subnets. This is read-only enrichment — it narrows review scope and does **not** authorize broader scanning by itself. Serial identity remains the device truth; hostnames and IPs are routing/location evidence only.

```bash
bash survey/sas-cybernet-subnet-location-map.sh \
  --tracker-csv survey/output/cybernet_alejandro_targets.csv \
  --preflight-csv survey/output/cybernet_host_preflight.csv \
  --identity-csv survey/output/cybernet_dns_resolution_report.csv \
  --prefix-config Config/cybernet_location_prefixes.example.csv \
  --output-prefix survey/output/cybernet_subnet_location
```

Run this **before** any approved subnet survey or Naabu/Nmap handoff so operators know which subnets need human review (for example mixed WNH/WMH in one `/24`). Full runbook: [`CYBERNET_SUBNET_LOCATION_INFERENCE.md`](CYBERNET_SUBNET_LOCATION_INFERENCE.md).

The subnet/location mapper keeps serial-first posture visible in its host evidence output. Tracker-only or hostname/IP-only evidence emits `FallbackUsed=Yes`; rows become `SurveyAuthority=serial` only when approved identity evidence supplies serial proof.

## Hostname recall errors

When a manifest `HostName` may carry a human recollection or typing error (wrong site prefix,
WNH/WMH confusion, number transposition, O/0 swap), expand it into bounded AD candidates per
[`CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md`](CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md) before AD
enrichment. Variant matches are discovery candidates only and never serial proof.

## Contract test

```bash
bash Tests/bash/test-cybernet-xlsx-targets-contracts.sh
```

Builds tiny fixture workbooks, runs the ingester and tracker diff wrappers, and verifies manifest/report/gap and serial-comparison outputs.

## Safety

- Read-only: does not modify source `.xlsx` files
- Offline: no network calls during ingestion
- Treat generated operational outputs under `survey/output/` (and similar evidence paths) as local-only; they are gitignored. The repo ignores `*.csv` by default, but sanitized fixture CSVs (for example `*.sample.csv` / `*.example.csv` / `*.fixture.csv` under `survey/fixtures/` or `targets/sanitized/`) are intentionally tracked — do not assume every CSV must stay out of git.
- Identity transports are read-only; no target-side writes, staging, or scheduled tasks

## Related docs

- [`targets/README.md`](../targets/README.md) — intake hub and gitignore policy
- [`bash/transport/README.md`](../bash/transport/README.md) — identity adapter transports and status codes
- [`CYBERNET_EVIDENCE_CORRELATION.md`](CYBERNET_EVIDENCE_CORRELATION.md) — multi-source presence merge
- [`LOW_NOISE_SURVEY_DOCTRINE.md`](LOW_NOISE_SURVEY_DOCTRINE.md) — reachability validation discipline
