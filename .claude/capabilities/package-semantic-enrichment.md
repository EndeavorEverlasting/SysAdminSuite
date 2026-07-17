# Package Semantic Enrichment Capability

## Contract

Re-verify static source hashes and convert observed structure into bounded semantic classifications and harness requirements without executing package code.

## Operation boundary

- Require a prior `sas-package-static-analysis/v1` result.
- Emit `package_semantic_analysis.json` / `package_semantic_analysis.txt`.
- Keep every behavior claim marked as static inference.
- Preserve hash continuity between static and semantic stages.

## Authority

- `harness/api/package-semantic-analysis-skill.json`
- `tools/package-analysis/enrich_package_semantics.py`
- `schemas/harness/package-semantic-analysis-result.schema.json`
- `docs/PACKAGE_SEMANTIC_ANALYSIS.md`

## Forbidden

Never execute custom actions, recover private strings into tracked files, or treat marker presence as cryptographic or runtime proof.

## Used by

- `.claude/skills/package-static-analysis/SKILL.md`
