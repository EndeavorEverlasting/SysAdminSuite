# Targets Folder Policy

`targets/` is the intake hub for SysAdminSuite target-source documentation, local placement guidance, schemas, and sanitized examples.

This policy keeps target-source intake from being scattered across runtime folders such as `survey/input/`, dashboard folders, scratch paths, or feature-specific directories.

## Rule

Workflows that begin from an approved list of devices or deployment rows should document `targets/` as the first intake location.

Use `targets/` for:

- target intake notes
- approved source descriptions
- schema references
- sanitized examples, when explicitly safe to track
- local operator instructions for where to place real target exports
- handoff notes explaining which downstream workflow consumes the target set

Do not commit real field target data to `targets/`.

## Data boundary

Real target files are local operator material unless explicitly sanitized.

Do not commit real exports, site-specific lists, raw inventory extracts, generated survey output, or generated evidence packages.

The repo already ignores common local-data formats such as CSV, TSV, XLS/XLSX, and ZIP. Keep that safety posture intact.

## Folder contract

| Folder | Role |
|---|---|
| `targets/` | Human-facing intake hub for target-source doctrine, local placement instructions, schemas, and sanitized examples |
| `survey/input/` | Runtime staging area for survey scripts |
| `survey/output/` | Generated local survey output |
| `survey/artifacts/` | Generated local evidence packages |
| `logs/nmap/` | Generated local discovery evidence |
| `evidence/` | Generated or collected field evidence |

New workflows should reference `targets/` first, then copy, derive, or point to runtime files as needed.

## Approved pattern

1. Operator receives or prepares an approved target source.
2. Operator places the local real source in a local ignored subfolder beneath `targets/` or another local-only path.
3. Operator runs a normalizer or workflow that reads from that target source.
4. Runtime artifacts are written to the workflow-specific runtime/output folders.
5. Only documentation, schemas, and sanitized fixtures are committed.

## Agent requirements

Agents working in this repo must:

- keep `targets/` as the first documented destination for target-source intake
- avoid introducing new ad hoc target-source folders
- avoid telling technicians to start in `survey/input/` unless the command specifically requires runtime staging there
- distinguish target manifests from evidence files
- keep normalized target manifests separate from discovery, preflight, or identity evidence
- state clearly when a dashboard can or cannot import a given target-manifest schema

## Dashboard and tutorial wording

Dashboard tutorials should use this distinction:

- **Target source / manifest:** what the operator intends to survey or reconcile.
- **Evidence:** what the workflow actually observed.
- **Review artifact:** a human-readable or dashboard-readable output used to make a decision.

Do not imply that every target manifest is dashboard-importable. Parser support must exist before the dashboard is documented as accepting that file.

## Migration note

Older documentation may still mention placing approved target CSVs directly in `survey/input/`. Treat that as runtime staging language, not intake doctrine.

Going forward, document target intake through `targets/`, then document how each workflow stages or consumes those targets.
