# Package Static Inspection Capability

## Contract

Inventory an operator-local package without executing it, extracting payloads by default, or contacting discovered endpoints.

## Operation boundary

- Consume an explicit local package path and an ignored output root.
- Emit `package_analysis.json` / `package_analysis.txt` through the static analyzer and wrappers.
- Re-hash and classify files; record PE/OLE/ZIP structure and bounded indicators only.
- Reject reparse-point substitution and root-escaping relative paths.

## Authority

- `harness/api/package-static-analysis-skill.json`
- `tools/package-analysis/analyze_package.py`
- `schemas/harness/package-static-analysis-result.schema.json`
- `docs/PACKAGE_STATIC_ANALYSIS.md`

## Forbidden

Never execute package code, follow shortcuts, or claim Authenticode or runtime proof from static inventory alone.

## Used by

- `.claude/skills/package-static-analysis/SKILL.md`
