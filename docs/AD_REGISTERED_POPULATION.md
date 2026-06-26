# AD Registered Population Doctrine

Active Directory registered population is the **population authority** for Cybernet and Neuron target reconciliation in Northwell-forward field workflows.

## Principle

When an authorized AD computer export is available, treat AD as the authoritative registered population. Deployment trackers, subnet scans, and port probes are **evidence layers** that confirm or challenge AD records — they do not replace AD as the population source.

Bounded hostname variant expansion (see [`CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md`](CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md)) is **candidate discovery** for locating an AD record despite a recall/typing error. A variant match is not population membership and not serial proof.

Clean mental model:

| Layer | Answers |
|---|---|
| AD | What registered computer accounts exist, whether they are enabled, and where they live in OU structure |
| DNS | What names resolve right now |
| Naabu / Nmap | What approved targets are reachable right now |
| WMI / endpoint inventory | What serial/identity evidence the device reports |
| Deployment Tracker / tickets | What was planned or operationally attributed |
| Dashboard | Reconciliation and human review |

## Approved input store

Place authorized, scoped AD-derived exports in:

```text
logs/targets/
```

This directory is for **approved local AD-derived target input** only. Do not commit live exports. Synthetic fixtures under `survey/fixtures/` exist for smoke tests and dashboard parser validation.

## Workflow boundary

| Layer | Role | Mutates targets? |
|---|---|---|
| AD export CSV | Registered-device roster / population authority | No |
| `sas-export-ad-registered-population.sh` | Field-friendly wrapper for dashboard-ready roster output | No |
| `sas-ad-reconcile.sh` | Normalize, bucket, reconcile | No |
| Naabu / Nmap | Reachability validation only | No |
| Live serial / identity CSV | Correlation evidence | No |

`sas-export-ad-registered-population.sh` and `sas-ad-reconcile.sh` consume AD CSV and optional offline evidence. They do **not** query AD live, run Naabu, or run Nmap.

## Required outputs

Each reconcile run writes a self-contained output directory:

| File | Purpose |
|---|---|
| `ad_registered_normalized.csv` | Normalized AD population |
| `ad_targets_hostnames.txt` | Approved hostname targets (enabled, non-duplicate) |
| `ad_targets_dns.txt` | Approved DNS names where present |
| `ad_evidence_matches.csv` | AD rows matched to supplemental evidence |
| `ad_only.csv` | Registered in AD, absent from evidence |
| `evidence_only.csv` | Present in evidence, absent from AD |
| `ad_disabled.csv` | Disabled AD computer accounts |
| `ad_stale.csv` | Stale last-logon records (configurable threshold) |
| `ad_missing_dns.csv` | Enabled hosts missing `DNSHostName` |
| `ad_duplicates.csv` | Duplicate normalized hostname keys |
| `network_reachable.csv` | Optional reachability evidence: reachable |
| `network_silent.csv` | Optional reachability evidence: silent / unreachable |
| `live_serial_matched.csv` | Optional serial evidence: matched |
| `live_serial_unavailable.csv` | Optional serial evidence: unavailable |
| `ad_summary.json` | Bucket counts and run metadata |
| `README.txt` | Human-readable output guide |

## Field command

```bash
bash survey/sas-export-ad-registered-population.sh \
  --ad-csv logs/targets/ad_computers_export.csv \
  --evidence-csv survey/input/cybernet_manifest.csv \
  --network-csv survey/output/network_reachability.csv \
  --serial-csv survey/output/live_serial_probe_results.csv \
  --output-dir survey/output/ad_registered_population/run_001 \
  --prefix CYB \
  --stale-days 90
```

Use `--prefix` to scope hostname filters (`CYB`, `WNH`, etc.). Omit when the export is already scoped.

`survey/sas-ad-reconcile.sh` remains the underlying contract script. Use it directly for lower-level automation; use the wrapper above for field-facing dashboard roster generation.

## Evidence classification

- **AD registered population** answers: *what should exist according to directory registration?*
- **Reachability evidence** answers: *did an approved validation tool see the host?*
- **Serial evidence** answers: *does an approved identity source align with the registered hostname?*

Do not invert this order. Build manifests from AD reconciliation first, then attach reachability and serial evidence as secondary layers.

## Safety

- Authorized, scoped exports only.
- Local import, reconcile, and report — no target mutation.
- No live AD queries from Bash reconcile tooling.
- No network scans from this script.

## Related documents

- [AD_PROBE_RESILIENCE.md](AD_PROBE_RESILIENCE.md) — resilient AD probe fallback ladder and ambiguity classifications
- [AD_CYBERNET_EXPORT_CONTRACT.md](AD_CYBERNET_EXPORT_CONTRACT.md) — CSV export contract for AD computer inventory
- [CYBERNET_EVIDENCE_CORRELATION.md](CYBERNET_EVIDENCE_CORRELATION.md) — multi-source evidence merge (downstream)
- [START-HERE-CYBERNET-NEURON-SURVEY.md](../START-HERE-CYBERNET-NEURON-SURVEY.md) — field workflow entry point
