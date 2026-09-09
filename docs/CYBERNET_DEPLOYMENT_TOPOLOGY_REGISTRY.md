# Cybernet Deployment Topology Registry

## One question only

This registry answers:

> **Which network locations are sufficiently supported by deployment evidence to deserve a low-noise targeted Cybernet survey?**

It does **not** decide whether a host is a Cybernet. Subnet/topology evidence controls **where we look**; hardware identity controls **what the device is**.

## Schema

| Artifact | Role |
|---|---|
| [`Config/Cybernet/sas-cybernet-deployment-topology-registry.v1.schema.json`](../Config/Cybernet/sas-cybernet-deployment-topology-registry.v1.schema.json) | Contract / vocab for `sas-cybernet-deployment-topology-registry/v1` |
| [`Config/Cybernet/sample.topology.registry.json`](../Config/Cybernet/sample.topology.registry.json) | Ratified sample with SITE+SUBNET eligible row and SITE-only reject row |
| [`DeploymentTracker/CybernetTopology.Eligibility.psm1`](../DeploymentTracker/CybernetTopology.Eligibility.psm1) | Pure offline eligibility evaluator |
| [`Tests/Fixtures/CybernetTopology/golden.registry.json`](../Tests/Fixtures/CybernetTopology/golden.registry.json) | Terminal-state matrix for regression |

## Four-registry split

| Registry | Owns |
|---|---|
| **Topology** (this document) | Where a bounded survey may run |
| **Hardware identity** | What qualifies as Cybernet hardware |
| **Device evidence** | What was actually observed |
| **Exclusion** | What already fails Cybernet effort and should not be resurveyed |

## Authority vs source type

`source_type` names where evidence came from. `authority` names how strongly it may drive targeting:

- `AUTHORITATIVE` / `CORROBORATING` can support subnet linkage when tied to a confirmed deployed device.
- `INFERENTIAL` and `DISCOVERY_ONLY` cannot alone authorize a targeted pass.
- A DHCP lease can corroborate where a known deployed machine was seen; a random DHCP lease cannot establish that Cybernets were deployed there.

## Independent corroboration

For `MEDIUM` confidence to become `ELIGIBLE`, the evaluator requires:

1. at least two `deployment_evidence` records that both `supports` include `SUBNET`
2. each of those records has a `device_anchor` with `deployment_status = CONFIRMED_DEPLOYED`
3. distinct `source_type` values among those records
4. at least one of those records has authority that is neither `DISCOVERY_ONLY` nor `INFERENTIAL`

`ELIGIBLE` also requires at least one **subnet-linked deployment proof**: authoritative deployment evidence whose `supports` includes `SUBNET` and whose `device_anchor` is confirmed deployed. Site-only tracker rows are deployment proof for the facility, not authorization to survey a CIDR.

`Update-CybernetTopologyRegistryEligibility` fails closed when `organization_id` is missing or `site_status` is not `ACTIVE`.

Classification is authoritative for workflow decisions. Numeric `score` is for sorting/reporting only and is ignored by eligibility.

## Targeted-pass budget

Eligible subnets may carry `targeted_pass_budget` (for example `windows_pc_signature_json`, ports 135/445, zero retries, no broad service enumeration). Budget authorizes **that exact bounded survey class** only. It is never an eligibility input and never escalates into a generic network scan.

## Deferred: tracker extractor

The Active Deployment Tracker workbook can supply **SITE** deployment proof (building/room + Cybernet host/serial/MAC). It does **not** currently provide Cybernet IP/CIDR columns. A future read-only extractor may emit `supports: ["SITE"]` evidence stubs, but must not invent CIDRs from hostname convention or from Neuron IP fields. Subnet proof waits for subnet-capable corroboration (DHCP/DNS/prior SAS network evidence tied to a `device_anchor`).

## Evaluator usage

```powershell
Import-Module .\DeploymentTracker\CybernetTopology.Eligibility.psm1 -Force
$registry = Get-Content .\Config\Cybernet\sample.topology.registry.json -Raw | ConvertFrom-Json
Update-CybernetTopologyRegistryEligibility -Registry $registry -AsOf ([datetime]'2026-09-08Z')
$registry.sites[0].subnets | ForEach-Object {
  [pscustomobject]@{
    subnet_id = $_.subnet_id
    status    = $_.targeted_pass_eligibility.status
  }
}
```

Eligibility is always recomputed. A manually declared `ELIGIBLE` status is never trusted.

## Technician iteration loop

The registry is not meant to be hand-edited by a field technician. The repeat-safe front door is
`Run-CybernetTopologySurvey.cmd`, documented in `START-HERE-CYBERNET-TOPOLOGY-SURVEY.md`.

Each click of that launcher runs one bounded iteration through
`scripts/Invoke-SasCybernetTopologySession.ps1`:

1. bootstrap the local session under gitignored `evidence/CybernetTopology/` if it is missing
2. merge every file staged in `ingest/` (your own probe results) and `inbox/` (bundles from other technicians)
3. recompute eligibility with `Update-CybernetTopologyRegistryEligibility`
4. diff the resulting statuses against the previous run
5. publish `next_probe_targets.csv`, `review_required.csv`, `iteration_summary.json`, and `operator_handoff.txt`
6. export a shareable bundle to `outbox/`

The first run and the fiftieth run take the same code path, so a technician never has to know whether
a session already exists.

### Merge semantics

`scripts/SasCybernetTopologySession.psm1` owns accumulation and deliberately owns no eligibility logic:

- sites merge by `site_id`, subnets by `subnet_id`, evidence by `evidence_id`
- a repeated `evidence_id` only replaces the stored copy when its `observed_at` is strictly newer
- `last_observed` is recomputed from the newest merged evidence, so genuine new observations renew
  freshness rather than silently aging into `STALE`
- a declared `subnet_confidence` only replaces the current one when its `calculated_at` is newer;
  the session never derives or invents a classification
- computed eligibility is stripped on export and always recomputed on import, so a bundle can never
  hand a receiving technician a pre-approved `ELIGIBLE`
- timestamps are normalised to canonical UTC on every merge so repeated passes do not drift the format

Because eligibility still demands subnet-linked deployment proof, a discovery-only observation can
refresh a date without ever authorizing a targeted pass.

### Sharing evidence between technicians

`Config/Cybernet/sas-cybernet-topology-evidence-bundle.v1.schema.json` defines the exchange format.
A bundle wraps a registry payload and pins `contains_operator_local_data: true`.

Machine-local absolute paths in `source_reference` are replaced with `operator-local-reference` before
export. Site names, CIDRs, and device keys remain, so a bundle is always operator-local data: keep it
in ignored local paths or approved internal channels, and never commit it.

Import accepts a bundle or a raw registry and refuses any other `schema_version` rather than merging
unknown content.

### Budget is separate from eligibility

An eligible subnet with no declared `targeted_pass_budget` is emitted as `BUDGET_NOT_DECLARED` in the
probe plan. Eligibility says the location deserves a look; only a declared budget says how much
looking is allowed. A blank budget is never treated as an unlimited one.
