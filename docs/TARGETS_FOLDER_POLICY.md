# Targets folder policy

Mechanical enforcement for tracked files under `targets/`.

## Purpose

`targets/` is the official **intake hub** in git: docs, schemas, and sanitized fixtures only. Live Cybernet workbooks, serial lists, MAC exports, and field evidence stay **local and gitignored**.

`logs/targets/` remains a preserved local evidence store. This policy does **not** delete, move, or modify `logs/targets/`.

## Guard command

```bash
python scripts/validate-targets-folder-policy.py
```

Inspects `git ls-files targets/` only. Untracked local files are out of scope (and should stay ignored).

## Guard boundary

This guard is a **tracked-file policy check**, not full content DLP.

It blocks committed files under `targets/` by path, extension, folder, and evidence-like names. It does not inspect every cell inside an approved `.sample`, `.example`, or `.fixture` file for real serials, MAC addresses, IP addresses, hostnames, or site identifiers. Keep sanitized fixtures synthetic and small. Treat any real target workbook, export, or evidence CSV as local-only data under ignored paths such as `targets/local/`, `logs/targets/`, or `survey/output/`.

## Allowed (tracked)

| Pattern | Example |
|---------|---------|
| `targets/README.md` | Hub readme |
| `targets/**/*.md` | Policy docs |
| `targets/**/*.schema.json` | `targets/schema/cybernet-targets.schema.json` |
| `targets/sanitized/**/*.{sample,example,fixture}.{csv,json}` | Synthetic fixtures |
| `targets/**/.gitkeep` | Structure placeholders |

Sanitized fixture names must **not** imply live data (e.g. `active_deployment_tracker.csv` is rejected even under `sanitized/`).

## Rejected (tracked)

- Office workbooks: `.xlsx`, `.xlsm`, `.xls`
- Archives: `.zip`
- CSV/TSV outside `targets/sanitized/` with approved suffix
- `.txt` unless under approved sanitized naming
- Anything under `targets/live/`, `targets/local/`, `targets/incoming/`, `targets/raw/`
- Filenames suggesting live evidence: Alejandro, Cybernet sources, wave, SSUH, NSUH, serial, mac, nmap, naabu, workstation identity, preflight, active deployment tracker

## Local-only intake (gitignored)

| Path | Role |
|------|------|
| `targets/local/` | Preferred ignored intake beside the hub |
| `logs/targets/` | Preserved historical local evidence |
| `survey/input/` | Runtime staging |
| `survey/output/` | Generated manifests and reports |

## Target manifest vs evidence

- **Target manifest** — acquisition handoff (`Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source`). Not network evidence.
- **Evidence CSVs** — network preflight, workstation identity, printer probe, etc. Dashboard-recognized when parsers exist.

## Contract test

```bash
bash Tests/bash/test-targets-folder-policy-contracts.sh
```

## Related lanes

- PR #46 — dashboard tutorial (does not import manifests until PR #54)
- PR #61 — offline xlsx ingester (explicit local workbook paths)
- PR #54 — dashboard manifest parser (after this guard lands)
