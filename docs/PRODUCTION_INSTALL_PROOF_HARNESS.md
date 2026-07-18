# Production software installation proof harness

## Operational finding

The production software-installation evidence belongs to **PR #222**, `feat: harden Resume Matcher deployment and live acceptance`. That lane defines the non-fixture `Accept` result and the required machine-observed installation, runtime, browser, sanitized-PDF, and application-acceptance fields.

**PR #212 is not the evidence authority.** It is the developer-workstation orchestration lane and its stated proof ceiling is composed fixture proof.

The operator reported that the installation was validated in production on the corporate network on **July 18, 2026**. The raw evidence remains operator-local and untracked. Repository code must not invent its digest or copy its private content.

## Purpose

`software_install.production_proof_ingest` closes the gap between a successful authorized runtime validation and durable repository knowledge. It does not rerun the installer. It validates the existing result, hashes the source file in place, and emits a public-safe receipt through the canonical SysAdminSuite run context and artifact registry.

## Operator command

Run from a clean branch containing this harness:

```powershell
pwsh -NoProfile -File .\scripts\Import-SasProductionInstallProof.ps1 `
  -EvidencePath "<ignored path to the PR #222 Accept result JSON>" `
  -SourcePr 222 `
  -ValidationDate 2026-07-18 `
  -EnvironmentClass production_corporate_network `
  -OperatorConfirmed
```

The source file is read and hashed in place. It is registered as live operator-local evidence but is not copied into the run directory.

## Required source result

The first supported producer is `sas-resume-matcher-workstation-result/v1`. A validated receipt requires all of the following:

- `operation: accept`;
- `outcome: success`;
- `lifecycle_state: accepted`;
- `configuration.fixture_mode: false`;
- install, configuration, launcher, backend, frontend, browser, sanitized-PDF, live-runtime, and acceptance proof flags are true;
- provider configuration is observed;
- the sanitized PDF has a positive size and SHA-256;
- provider health is observed when the source result says it was required;
- the operator explicitly confirms the date and environment.

PR #222 is enforced as the source authority for this schema. PR #212 is rejected.

## Outputs

The canonical run root receives:

- `production_install_proof_receipt.json`;
- `production_install_proof_receipt.txt`;
- `artifact_registry.json`;
- `summary.json`;
- `operator_handoff.txt`.

The receipt contains only schema identity, source PR, source byte count and digest, validation date, bounded environment classification, booleans, privacy declarations, and the proof ceiling. It emits no hostname, username, credential, provider secret, raw log, or machine-local path.

## Fixture boundary

CI uses `--contract-fixture`. That mode can only produce `contract-only`; it cannot produce `validated` or live-production proof. Source evidence whose own `fixture_mode` is true is blocked even when an operator-confirmation flag is supplied.

## Proof interpretation

A `validated` receipt proves the exact source evidence identified by its SHA-256, the machine-observed PR #222 acceptance fields, and the operator-attested date/environment. It does not authorize another installation, another workstation, a fleet rollout, a clinical workflow, AutoLogon, or unrelated corporate-network access.

Until the operator runs the import command against the actual ignored result, the repository proves the ingestion harness and records the operator attestation, but it does not possess the source-evidence digest.
