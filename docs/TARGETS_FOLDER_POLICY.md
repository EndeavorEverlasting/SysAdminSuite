# Targets Folder Policy

`targets/` is the one-stop shop for target intake across SysAdminSuite.

This policy exists so agents and developers do not scatter target sources across `survey/input/`, dashboard folders, ad hoc scratch paths, or feature-specific directories.

## Rule

All workflows that start from a known list of devices, hostnames, serials, MAC addresses, subnets, or deployment-tracker rows should treat `targets/` as the intake root.

Use `targets/` for:

- target intake notes
- approved source descriptions
- schema references
- sanitized examples, when explicitly safe to track
- local operator instructions for where to place real target exports
- handoff notes explaining which downstream workflow consumes the target set

Do not use `targets/` for committed live field data.

## Live data boundary

Live target files may contain hostnames, serials, MAC addresses, IPs, subnet hints, site names, or deployment context. Those files are local operator material unless explicitly sanitized.

Do not commit:

- live CSV, TSV, XLSX, ZIP, or dashboard exports
- site-specific target lists
- serial-number inventories
- MAC-address inventories
- raw AD, CMDB, SCCM, deployment tracker, or Nmap evidence
- generated survey output

The repo already ignores common live-data formats such as CSV, TSV, XLS/XLSX, and ZIP. Keep that safety posture intact.

## Folder contract

`targets/` is the intake hub. Tool-specific folders are runtime or processing destinations.

| Folder | Role |
|---|---|
| `targets/` | Human-facing intake hub for target-source doctrine, local placement instructions, schemas, and sanitized examples |
| `survey/input/` | Runtime staging area for survey scripts |
| `survey/output/` | Generated local survey output |
| `survey/artifacts/` | Generated local evidence packages |
| `logs/nmap/` | Generated local Nmap or Naabu evidence |
| `evidence/` | Generated or collected field evidence |

New workflows should reference `targets/` first, then copy, derive, or point to runtime files as needed.

## Approved pattern

1. Operator receives or prepares an approved target source.
2. Operator places the local live source under `targets/` or a local ignored subfolder under `targets/`.
3. Operator runs a normalizer or workflow that reads from that target source.
4. Runtime artifacts are written to `survey/input/`, `survey/output/`, `logs/`, or `survey/artifacts/`.
5. Only documentation, schemas, and sanitized fixtures are committed.

## Agent requirements

Agents working in this repo must:

- keep `targets/` as the first documented destination for target-source intake
- avoid introducing new ad hoc target-source folders
- avoid telling technicians to start in `survey/input/` unless the command specifically requires runtime staging there
- distinguish target manifests from evidence files
- keep normalized target manifests separate from Nmap, Naabu, preflight, or identity evidence
- state clearly when a dashboard can or cannot import a given target-manifest schema

## Dashboard and tutorial wording

Dashboard tutorials should use this distinction:

- **Target source / manifest:** what the operator intends to survey or reconcile.
- **Evidence:** what the network, identity, or inventory workflow actually observed.
- **Review artifact:** a human-readable or dashboard-readable output used to make a decision.

Do not imply that every target manifest is dashboard-importable. Parser support must exist before the dashboard is documented as accepting that file.

## Migration note

Older documentation may still mention placing approved target CSVs directly in `survey/input/`. Treat that as runtime staging language, not intake doctrine.

Going forward, document target intake through `targets/`, then document how each workflow stages or consumes those targets.
