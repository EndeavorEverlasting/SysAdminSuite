# Cybernet Subnet Location Inference

Read-only, offline enrichment that maps approved hostname and IP evidence to likely site/location subnets. This lane narrows technician review scope. It does **not** run Naabu, Nmap, ping sweeps, WMI, or any live network probe.

## Posture (required)

- **Subnet/location inference narrows review scope. It does not authorize broader scanning by itself.**
- **Serial identity remains the device truth.**
- **Hostnames and IPs provide routing/location evidence, not serial proof.**

Treat inferred subnets as confidence evidence for reconciliation and handoff. Approved scan scope still requires explicit operator authorization, approved subnet lists, and the low-noise survey doctrine — not inference output alone.

## Serial-First Fallback Audit

If the tool falls back from serial to hostname, IP, or subnet evidence, the output says so. This is how operators separate “we surveyed the device” from “we found a route-shaped clue.”

This mapper does **not** run WMI, privileged identity transport, live AD queries, ping sweeps, Naabu, or Nmap. It consumes serial and identity-proof columns when they are already present in approved CSV evidence.

Serial handling is conservative:

1. A usable serial plus identity-proof status (`IdentityCollected`, `WmiIdentityCollected`, `serial_confirmed`, `match`, `confirm`, or similar) emits `SurveyAuthority=serial`, `FallbackUsed=No`, and `SerialEvidenceStatus=serial_confirmed`.
2. A serial without identity proof remains `serial_candidate`; hostname/IP output still uses fallback fields and `Blocker=needs_privileged_identity`.
3. Rows without usable serials emit `FallbackUsed=Yes` and `SerialEvidenceStatus=not_serial_proof`.
4. Hostname/IP/subnet inference can guide review scope, but it never becomes serial confirmation.

Fallback output fields in `{prefix}_hosts.csv`:

| Field | Purpose |
|-------|---------|
| `SurveyAuthority` | `serial`, `hostname_fallback`, `subnet_inference_only`, or `blocked` |
| `PrimaryKey` / `PrimaryKeyType` | Best available key: serial first, then hostname, then IP |
| `FallbackUsed` | `Yes` when the row is not serial-confirmed authority |
| `FallbackType` | Machine-readable fallback class such as `serial_missing`, `serial_unresolved`, `hostname_only_evidence`, or `ip_only_evidence` |
| `FallbackReason` | Why fallback happened, for example `serial_missing_hostname_ip_used` |
| `SerialEvidenceStatus` | `serial_confirmed`, `serial_candidate`, `serial_missing`, or `not_serial_proof` |
| `HostnameEvidenceStatus` | `hostname_validated`, `hostname_candidate`, `hostname_missing`, or `hostname_unresolved` |
| `Blocker` | Blocking condition such as `missing_serial`, `missing_dns_ip`, `invalid_ip`, `unknown_prefix`, `mixed_subnet_prefixes`, or `needs_privileged_identity` |
| `NextAction` | Operator-facing next step |

Common blocker actions:

| Blocker | Typical next action |
|---------|---------------------|
| `missing_serial` | Collect approved privileged identity evidence when serial proof is needed |
| `needs_privileged_identity` | Run approved identity transport; do not treat hostname/IP evidence as serial proof |
| `missing_dns_ip` | Supply DNS resolution or preflight CSV evidence |
| `invalid_ip` | Fix placeholder or malformed IP evidence in the source CSV |
| `unknown_prefix` | Review hostname source or local prefix config |
| `mixed_subnet_prefixes` | Review site context and prefix pairing before survey handoff |

## Purpose

Field and inventory teams often hold hostname and IP evidence from AD exports, DNS resolution, preflight checks, and tracker manifests — but not a single subnet-to-site map. This tool ingests those **approved, local** CSV inputs and produces:

- per-host evidence rows with normalized hostname, IP, mechanical `/24` (or configured prefix), parsed location prefix, and provenance
- aggregated subnet → location mappings with transparent confidence scoring
- optional offline HTML for operator review

It is **enrichment/reconciliation**, not population discovery and not reachability proof.

## What this tool is not

| Concern | This lane | Use instead |
|---------|-----------|-------------|
| Subnet host discovery / port confirmation | No | [`survey/sas-cybernet-subnet-survey.sh`](../survey/sas-cybernet-subnet-survey.sh) |
| Naabu/Nmap reachability validation | No | [`LOW_NOISE_SURVEY_DOCTRINE.md`](LOW_NOISE_SURVEY_DOCTRINE.md) |
| Serial-confirmed device identity | No | Approved WMI / privileged identity transport |
| Hostname typo / variant AD search | No | [`CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md`](CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md) |
| Live workbook or AD mutation | No | Read-only exports only |

## Evidence sources

The engine merges flexible CSV inputs. Column names are tolerant (case-insensitive aliases).

### 1. Identity / AD export CSV

Authorized AD or identity exports with hostname and IP fields. See [`AD_CYBERNET_EXPORT_CONTRACT.md`](AD_CYBERNET_EXPORT_CONTRACT.md).

Accepted columns include: `HostName`, `DNSHostName`, `Name`, `IPv4Address`, `IPAddress`, `Serial`, `SerialNumber`, `ObservedSerial`, `IdentityStatus`, `EvidenceStatus`, `SerialProbeStatus`, and `MACAddress`.

**Precedence:** when the same hostname appears in identity and preflight sources, a valid identity/AD export IP wins. If identity has a placeholder or malformed IP and preflight has a valid IP, the valid preflight IP is used and the fallback is visible in the host row.

### 2. Preflight CSV

Output from [`bash/transport/sas-network-preflight.sh`](../bash/transport/sas-network-preflight.sh) or equivalent read-only reachability checks.

Accepted columns include: `Target`, `HostName`, `ResolvedIP`, `ResolvedAddress`, `IPAddress`, `Address`, `PingStatus`, `PortStatus`, and `EvidenceStatus`.

Preflight is supplementary evidence. It does not prove serial identity.

### 3. Tracker / manifest / diff CSV

Manifest or tracker-derived rows from ingestion or diff lanes.

Accepted columns include: `HostName`, `ExpectedHostname`, `CandidateHostname`, `Identifier`, `IdentifierType`, `Site`, `Practice`, `Source`, `Serial`, `ExpectedSerial`, and `ObservedSerial`.

Tracker hostname fields carry **expected** naming, not proof of current network placement.

### 4. Prefix configuration (example schema)

Committed example only: [`Config/cybernet_location_prefixes.example.csv`](../Config/cybernet_location_prefixes.example.csv).

Operators copy and customize a local prefix map. The example file uses synthetic WTS/WNH/WMH/MEDTEST-style entries — not live site secrets.

Typical columns: `LocationCode`, `LocationLabel`, `Region`, `SiteAffinity`, `AllowMixedWith`, `Notes`.

## Merge and normalization rules

Per hostname:

1. Normalize FQDN → short host (strip domain suffix, uppercase, bounded token cleanup).
2. Parse location prefix from hostname via bounded `PREFIX_RE` and the prefix config.
3. Resolve IP from the first valid field across sources; check identity/AD, then preflight, then tracker. Invalid placeholders are skipped so lower-precedence valid IPs can still map a subnet.
4. Derive mechanical subnet with `ipaddress` and `--prefix-len` (default `24`).
5. Never invent IP or subnet for hosts without address evidence.
6. Deduplicate by `NormalizedHostName`; join provenance into `EvidenceSources` (semicolon-separated).
7. Emit fallback audit fields for every host row so serial, hostname, IP, and subnet authority are never confused.

## Confidence scoring

Scoring is transparent and explainable. Points are capped into tiers.

| Signal | Points |
|--------|--------|
| Prefix maps via config | +40 |
| 2+ hosts same location code in subnet | +25 |
| 5+ hosts same location code in subnet | +25 |
| AD/DNS export source | +20 |
| Also in preflight | +15 |
| Only one host supports mapping | −30 |
| Conflicting location codes in subnet | −40 |
| Missing/invalid IP | −30 |

### Tier mapping

| Tier | Typical status | Meaning |
|------|----------------|---------|
| High | `subnet_location_strong` | Multiple consistent hosts; strong prefix + subnet cohesion |
| Medium | `subnet_location_candidate`, `subnet_location_allowed_mixed` | Plausible mapping; operator should confirm |
| Low | `subnet_location_candidate` (`Confidence=low`) | Weak support; do not treat as site truth |
| Review | `subnet_location_mixed`, `needs_manual_review`, `needs_network_team_confirmation` | Conflicts or policy holds |

### Status taxonomy

| Status | Meaning |
|--------|---------|
| `subnet_location_strong` | High-confidence subnet → location association |
| `subnet_location_candidate` | Medium/low candidate; confirm before scope decisions |
| `subnet_location_allowed_mixed` | Configured mixed-prefix pairing, visible as medium confidence with review notes |
| `subnet_location_mixed` | Conflicting location codes share a subnet (see mixed-subnet handling) |
| `location_spans_multiple_subnets` | One location code appears across multiple subnets |
| `hostname_unresolved` | Hostname could not be normalized or matched |
| `ip_missing` | Hostname present but no usable IP |
| `ip_invalid` | IP field present but not parseable |
| `prefix_unknown` | Hostname prefix not in config |
| `needs_network_team_confirmation` | Mapping needs network/infra review |
| `needs_manual_review` | Operator review required before any scan handoff |

## Mixed-subnet handling

When **WNH** and **WMH** (or other configured location codes) appear in the **same** mechanical subnet:

- If `AllowMixedWith` explicitly allows the pair in the local prefix config, classify as `subnet_location_allowed_mixed`, set `Confidence=medium`, and include a `ReviewReason` naming the allowed pairing.
- Without an allowed pairing, classify as `subnet_location_mixed` and cap confidence at **review**.
- Do **not** auto-resolve to a single site or facility.
- Do **not** treat mixed evidence as serial proof or variant auto-resolution.

This is enrichment for human review, aligned with [`CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md`](CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md). Prefix substitution doctrine and subnet mixing are separate concerns; both require operator judgment.

`AllowMixedWith` is not silent approval. It exists so configured mixed-prefix evidence remains visible and distinguishable from unapproved conflicts.

When one location code spans multiple `/24` subnets, emit `location_spans_multiple_subnets` so technicians do not assume a single VLAN.

## Relationship to `Config/cybernet-subnet-rules.json`

[`Config/cybernet-subnet-rules.json`](../Config/cybernet-subnet-rules.json) defines **scan correlation rules** for approved-subnet gating when mapping resolved IPs to scanner scope (for example `requireApprovedSubnet`, `confidenceRules` for `SubnetApproved` / `SubnetInferred`).

| Artifact | Role |
|----------|------|
| `cybernet-subnet-rules.json` | Adjacent scan-correlation policy — when an IP may be included in approved Naabu/Nmap handoff |
| Subnet location inference | Evidence aggregation from hostnames/IPs — where devices **appear** to live |

These are related but **not the same thing**. Inference output does not replace approved subnet lists (`input/site-subnets.example.csv`, `Config/approved-subnets.example.json`) or authorize scanning. Use inference to narrow **review**; use subnet rules and approved lists to gate **execution**.

## Command

Primary entry point:

```bash
bash survey/sas-cybernet-subnet-location-map.sh \
  --identity-csv survey/output/ad_computers_normalized.csv \
  --preflight-csv survey/output/cybernet_host_preflight.csv \
  --tracker-csv survey/output/cybernet_alejandro_targets.csv \
  --prefix-config Config/cybernet_location_prefixes.example.csv \
  --prefix-len 24 \
  --output-prefix survey/output/cybernet_subnet_location \
  --format csv,json \
  --html
```

### CLI flags

| Flag | Purpose |
|------|---------|
| `--identity-csv PATH` | Identity/AD export CSV (repeatable; optional if other evidence inputs are supplied) |
| `--identity-glob PATTERN` | Glob for multiple identity CSVs (Git Bash; prefer explicit paths in automation) |
| `--preflight-csv PATH` | Preflight reachability CSV |
| `--tracker-csv PATH` | Tracker/manifest/diff CSV |
| `--prefix-config PATH` | Local prefix mapping CSV (start from example schema) |
| `--prefix-len N` | Mechanical subnet prefix length (default `24`) |
| `--output-prefix PATH` | Base path for generated artifacts (default under `survey/output/`) |
| `--format csv,json` | Output formats: `csv`, `json`, `csv,json`, or `all` |
| `--html` | Emit offline HTML report under `survey/output/cybernet_subnet_location_report/` |

Identity-only example after DNS resolution:

```bash
bash survey/sas-cybernet-subnet-location-map.sh \
  --identity-csv survey/output/cybernet_dns_resolution_report.csv \
  --prefix-config Config/cybernet_location_prefixes.example.csv \
  --output-prefix survey/output/cybernet_subnet_location
```

## Generated outputs (gitignored)

All paths stay local under `survey/output/` (or your `--output-prefix`). **Do not commit** live hostnames, IPs, serials, or site evidence.

| Output | Purpose |
|--------|---------|
| `{prefix}_map.csv` | Aggregated subnet → location rows with confidence and status |
| `{prefix}_hosts.csv` | Per-host evidence, provenance, parsed prefix, and serial-first fallback audit fields |
| `{prefix}_map.json` | Machine-readable map for dashboards or downstream merge |
| `cybernet_subnet_location_report/index.html` | Optional offline review site (`--html`) |

Verify ignore policy:

```bash
git check-ignore -v survey/output/cybernet_subnet_location_map.csv
git check-ignore -v survey/output/cybernet_subnet_location_map.json
```

## Safe technician workflow

1. **Fix population** — ingest or diff manifests per [`CYBERNET_XLSX_TARGET_INGESTION.md`](CYBERNET_XLSX_TARGET_INGESTION.md).
2. **Collect approved evidence** — normalized AD export, DNS resolution report, optional preflight (read-only).
3. **Run subnet location inference** — local CSV in, local CSV/JSON/HTML out.
4. **Review fallback rows** — filter `FallbackUsed=Yes` before treating output as population truth.
5. **Review mixed and low-confidence rows** — distinguish `subnet_location_allowed_mixed` from `subnet_location_mixed`, and check `location_spans_multiple_subnets`.
6. **Confirm serial identity separately** — WMI or approved privileged transport when hostname/IP placement is insufficient.
7. **Only then** — if policy allows, hand approved subnets and target IPs to the subnet survey runner or targeted Naabu/Nmap profiles.

Console summary example:

```text
[sas-cybernet-subnet-location-map] 8 subnets mapped | 5 strong | 2 review | 1 unresolved
[sas-cybernet-subnet-location-map] serial-first: 184 serial-authority | 37 hostname fallback | 12 ip/subnet fallback | 9 blockers
[sas-cybernet-subnet-location-map] Top mappings:
  10.41.22.0/24 -> WNH / LIJ-like | 37 hosts | high
  10.52.18.0/24 -> WMH / NSUH-like | 24 hosts | high
  10.41.29.0/24 -> MIXED WNH,WMH | 9 hosts | review
```

## Contract test

```bash
bash Tests/bash/test-cybernet-subnet-location-contracts.sh
```

Synthetic fixtures only (`WTS*`, `WNH*`, `WMH*`, `MEDTEST*`, `10.10.x.x`). Cases cover subnet scoring, IP fallback, `ResolvedAddress`, serial-first fallback fields, and allowed mixed-prefix handling. No live identifiers.

## Related docs

- [`CYBERNET_XLSX_TARGET_INGESTION.md`](CYBERNET_XLSX_TARGET_INGESTION.md) — manifest population and tracker enrichment
- [`CYBERNET_EVIDENCE_CORRELATION.md`](CYBERNET_EVIDENCE_CORRELATION.md) — multi-source presence merge
- [`CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md`](CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md) — bounded hostname variant discovery (not subnet inference)
- [`LOW_NOISE_SURVEY_DOCTRINE.md`](LOW_NOISE_SURVEY_DOCTRINE.md) — reachability validation discipline
- [`survey/README.md`](../survey/README.md) — survey tool index (subnet location map vs subnet survey runner)

## Safety

- Read-only: no endpoint mutation, no credentials, no live probes invoked by this tool
- Low-noise survey discipline: transparent scope control, not stealth or evasion
- Authorized traffic may be monitored; that is expected
- Example prefix config is synthetic; operators maintain real mappings locally
