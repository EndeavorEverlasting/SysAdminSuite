# Mutation and Evidence Boundaries Capability

## Contract

Keep observation, authorized mutation, and evidence handling in explicit lanes.

## Lane boundaries

- Survey and dashboard probe lanes are read-only toward target machines and write evidence locally only.
- Deployment, repair, mapping, staging, and shortcut lanes may mutate targets only with explicit authorization and their documented gate.
- Legacy enablement does not expand target scope, grant credentials, or remove approval requirements.
- Transient payloads, tasks, launchers, staging folders, and markers require teardown unless documented as intentionally retained.

## Evidence boundaries

Never commit secrets, credentials, live target lists, serials, MAC exports, workbooks, scan output, registry exports, screenshots, raw logs, user-profile paths, or machine-local evidence.

Use tracked synthetic fixtures and approved examples. Keep operational evidence under ignored roots such as `survey/output/`, `survey/artifacts/`, `logs/nmap/`, `logs/targets/`, or a workflow-specific ignored run directory.

## Language and intent

Use authorized, read-only, low-noise, scoped, bounded, local evidence, dry-run, validation-first, and operator-approved language. Cleanup means reducing residual operational clutter while preserving normal audit and monitoring visibility.

## Used by

- `.claude/skills/repository-sprint/SKILL.md`
- `.claude/skills/live-data-guard/SKILL.md`
- `.claude/skills/survey-low-noise/SKILL.md`
- `.claude/skills/field-workflow/SKILL.md`
