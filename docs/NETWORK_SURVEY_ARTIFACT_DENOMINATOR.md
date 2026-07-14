# Network Survey Artifact Denominator

## Purpose

Network survey users may provide different artifact formats and organizational column names. Format diversity is handled by modular adapters. Planning logic does not consume those source-specific shapes directly.

The enforced pipeline is:

```text
approved source artifact
  -> one registered adapter
  -> canonical denominator package
  -> denominator validation
  -> artifact intake manifest
  -> delta planning
```

No source artifact reaches `survey/sas-delta-preflight-plan.ps1` row logic until every row satisfies the canonical denominator contract.

## Authorities

| Concern | Authority |
|---|---|
| Canonical package and row shape | `schemas/survey/network-survey-artifact-denominator.schema.json` |
| Registered formats, detection rules, and aliases | `survey/network_survey_artifact_adapters.json` |
| Runtime normalization and fail-closed validation | `scripts/SasSurveyArtifactNormalizer.psm1` |
| Standalone validation entrypoint | `scripts/Test-SasSurveyArtifactDenominator.ps1` |
| End-to-end consumer | `survey/sas-delta-preflight-plan.ps1` |
| Static and Windows fixture harness | `Tests/survey/test_network_survey_denominator_contracts.py` and `.github/workflows/network-survey-delta-contracts.yml` |

The JSON schema and adapter registry are operational inputs. They are not explanatory copies of logic.

## Supported modular inputs

The initial registry supports:

- requested populations: CSV, TXT, JSON, and JSONL;
- evidence snapshots: CSV, JSON, and JSONL;
- an already normalized canonical JSON package.

XLSX is not parsed directly by this lane. A workbook must first use an approved workbook ingestion engine that emits a supported artifact. Adding a new format requires a bounded adapter and fixtures; it must not add source aliases to the planner.

## Common denominator row

Every normalized row carries all canonical fields, including empty values where a field is not applicable:

```text
row_id
record_role
serial
normalized_serial
target
normalized_target
candidate_targets
device_type
site
expected_prefix
observed_at
evidence_type
evidence_strength_tier
serial_identity_confirmed
reachability_status
open_ports
resolved_address
mac_address
port
port_status
ad_candidate_status
tracker_status
source_file
source_adapter
source_values
```

Every row must contain at least one usable anchor:

```text
normalized serial
or normalized target
or one or more candidate targets
```

Role-specific requirements are stricter:

- identity evidence requires a normalized serial, `serial_identity_confirmed = true`, and a timestamp;
- device-location, reachability, packet-service, and negative/silent evidence require timestamps so freshness and deltas are meaningful;
- requested serial-only rows are denominator-valid but remain review-required and are never staged as network targets;
- evidence with no classifiable evidence type is rejected.

## Failure behavior

Normalization is artifact-atomic by default. One rejected row invalidates the artifact for planning.

The normalizer writes a validation report and, when applicable, a rejection CSV before throwing. Typical reason codes include:

```text
DENOMINATOR_KEY_MISSING
EVIDENCE_TYPE_MISSING
IDENTITY_REQUIREMENTS_MISSING
TIMESTAMP_REQUIRED_FOR_FRESHNESS
ARTIFACT_ROWS_REJECTED
```

The operator fixes or replaces the source artifact. The planner does not guess fields, silently drop rows, or widen aliases in downstream code.

## Runtime evidence

A successful delta run writes:

```text
survey/output/delta_preflight/<run_id>/artifact_intake_manifest.json
survey/output/delta_preflight/<run_id>/normalized_artifacts/*.normalized.json
survey/output/delta_preflight/<run_id>/normalized_artifacts/*.validation.json
```

The intake manifest records the selected adapter, normalized package, validation report, source format, role, and row count for every artifact.

All runtime packages and validation reports remain under ignored output roots because `source_values` may preserve operational source fields.

## Adding or maintaining an adapter

1. Add or update one entry in `survey/network_survey_artifact_adapters.json`.
2. Map only fields declared in `canonical_fields`.
3. Keep detection bounded by role, format, and required header groups.
4. Use priority only to select a more specific adapter over a generic adapter.
5. Add sanitized fixtures for the new shape.
6. Add a passing end-to-end fixture and a failing denominator fixture where relevant.
7. Run the static denominator contract and Windows workflow.

Do not add organization-specific aliases to `SasDeltaEvidenceCache.psm1`, the planner core, launcher, or report writer. The adapter boundary is the only source-shape translation layer.

## Proof boundary

Static contracts prove schema/registry consistency and that aliases do not leak downstream. The Windows fixture workflow proves registered artifacts normalize, validate, and flow through the actual delta planner. Neither proves live network behavior.
