# Registry Diff Safety Rules

## Safety Baseline

Registry diff operations in this sprint are **observation-first** and **evidence-first**.

- Read-only registry observation is the default behavior.
- No blind registry edits are allowed.
- No production mutation is allowed by default.
- No automatic registry writes are introduced in baseline pipeline modes.

## Data Handling and Privacy Rules

The following must never be committed as repository content:

- Live registry dumps.
- Real hostnames.
- Real serial numbers.
- Real MAC addresses.
- Credentials or secrets.
- Production-specific filesystem or network paths.
- Generated evidence bundles from real environments.

Any operational artifacts must be exported outside tracked source as runtime evidence, not committed as static repository data.

## Allowed Registry Diff Classifications

The pipeline classification vocabulary for this sprint is:

- `CreatedKey`
- `DeletedKey`
- `CreatedValue`
- `DeletedValue`
- `ModifiedValue`
- `ExpectedChange`
- `Noise`
- `SuspiciousChange`
- `RemediationCandidate`

These classifications support review workflows and do not grant permission for automatic remediation.

## Noise Filtering Philosophy

Noise filtering must prioritize analyst trust and traceability:

- Prefer explicit, explainable classification rules over opaque scoring.
- Do not discard raw evidence; mark low-value churn as `Noise` while preserving it in artifacts.
- Support repeatable reclassification as installer baselines mature.
- Preserve distinction between expected installer changes and suspicious drift.

## Installer Failure Logging Requirements

When installer execution fails (hard failure, timeout, partial completion, or abnormal exit), logs must include:

- Target identity token used for the run.
- Software identifier and resolved installer metadata source.
- Selected run mode and dry-run/execution flags.
- Readiness status at time of action.
- Exit code, error text, and failure phase.
- Whether before snapshot exists.
- Whether after snapshot exists or was skipped.
- Whether diff/classification was completed, partially completed, or skipped.
- Export location and artifact completeness state.

## Partial Failure Evidence Requirement

Evidence must survive partial failure.

- A failed install does not invalidate snapshot and readiness evidence.
- Export must proceed with all available artifacts whenever possible.
- Missing artifacts must be explicitly logged rather than silently omitted.
- Summary outputs must clearly mark run status as full success, partial failure, or failed-with-evidence.
