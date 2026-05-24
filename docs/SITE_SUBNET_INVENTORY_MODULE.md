# SysAdminSuite Site Subnet Inventory Module

## Purpose

The Site Subnet Inventory Module tracks known, observed, and validated subnets by supported site so authorized SysAdminSuite workflows can operate with explicit network terrain instead of guessing.

This module extends the existing Nmap baseline work without weakening its guardrails.

```text
Recon -> Decide -> Act -> Log -> Export
```

## Files

```text
config/sites/sites.csv
config/sites/site_subnets.csv
examples/site_subnets.example.csv
scripts/sas_discover_local_subnets.sh
```

## Inventory Schema

`config/sites/site_subnets.csv` uses:

```csv
site_code,subnet_cidr,gateway,source,confidence,last_seen,enabled,notes
```

Field guidance:

| Field | Meaning |
|---|---|
| `site_code` | Stable site identifier such as `NSUH`, `LIJMC`, or `CCMC`. |
| `subnet_cidr` | Candidate or approved subnet in CIDR notation. |
| `gateway` | Observed or expected gateway where known. |
| `source` | Evidence source: `manual`, `ipconfig`, `route-print`, `arp`, `nmap-ping`, etc. |
| `confidence` | `high`, `medium`, or `low`. |
| `last_seen` | Date the subnet was last observed or validated. |
| `enabled` | `true` only when approved for use in downstream tooling. |
| `notes` | Plain-language context. Prefer semicolons over commas for CSV portability. |

## Confidence Rules

| Confidence | Standard |
|---|---|
| `high` | Directly observed from local interface, route evidence, or approved site network source. |
| `medium` | Inferred from gateway, ARP, DNS suffix, hostname pattern, or repeated local evidence. |
| `low` | Seeded manually, example-only, stale, or not yet validated. |

Low-confidence rows must not drive broad tooling by default.

## Local Discovery

Run local discovery from a machine at the site:

```bash
bash scripts/sas_discover_local_subnets.sh --site-code NSUH
```

Dry run:

```bash
bash scripts/sas_discover_local_subnets.sh --site-code NSUH --dry-run
```

The discovery script collects local evidence only. It does not run Nmap and does not mutate the workstation.

Key outputs:

```text
exports/local_subnet_candidates.csv
exports/local_gateways.csv
exports/local_routes.csv
exports/site_subnet_candidates.json
exports/site_subnet_discovery_report.md
logs/events.jsonl
logs/trace.log
raw/local/
```

## Safe Nmap Relationship

The existing Nmap baseline module remains the active scanner. Site subnet inventory should feed it only with approved, enabled targets.

Existing conservative example:

```bash
bash scripts/sas_nmap_baseline.sh --target 192.0.2.0/29 --scan-mode ping-only --allow-subnet --max-targets 1 --dry-run
```

Production usage requires authorization and accurate target scope. Do not use documentation ranges or placeholder rows as real targets.

## Guardrails

- No stealth scanning.
- No vulnerability scripts.
- No brute-force scripts.
- No spoofing, decoys, or IDS/firewall evasion flags.
- No broad default subnet scans.
- Disabled inventory rows are documentation only.
- Low-confidence rows require review before downstream usage.
- The module records evidence; it does not prove site ownership or complete VLAN coverage.

## Supported Site Seeds

Initial site codes are seeded in `config/sites/sites.csv`:

```text
NSUH
LIJMC
CCMC
CFAM
GLENCOVE
ZUCKER
VALLEYSTREAM
MATHER
BAYSHORE
HUNTINGTON
```

## Operating Model

1. Run local discovery from an authorized site workstation.
2. Review generated evidence.
3. Add or update rows in `config/sites/site_subnets.csv`.
4. Mark rows `enabled=true` only after scope is approved.
5. Use the existing Nmap baseline module for limited validation.
6. Preserve logs and exports with the run artifacts.

## Next Layer

Future work can add a dedicated export helper that creates bash target files from `enabled=true` rows. That helper should stay read-only, default-safe, and avoid broad probing by default.
