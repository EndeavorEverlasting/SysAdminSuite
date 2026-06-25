# Targets intake hub

`targets/` is the **official tracked intake hub** for target-list documentation, schemas, and **sanitized fixtures only**.

## What belongs here (tracked in git)

- This README and other `*.md` policy or schema docs
- `targets/schema/*.schema.json` — machine-readable manifest schemas
- `targets/sanitized/**/*.{sample,example,fixture}.{csv,json}` — synthetic demo fixtures for tests and docs
- `.gitkeep` files that preserve directory structure

## What does NOT belong here (local only)

Live operational target material must **never** be committed:

- Workbooks (`.xlsx`, `.xlsm`, `.xls`)
- Raw CSV/TSV target exports with real hostnames, serials, MACs, or sites
- ZIP archives of field evidence
- Alejandro lists, deployment trackers, wave spreadsheets, or site-specific serial/MAC lists

Place live files under **gitignored** local paths, for example:

- `targets/local/` — preferred local intake beside the hub (ignored)
- `logs/targets/` — preserved historical local evidence store (ignored)

## Target manifest vs evidence

| Artifact | Role | Dashboard import |
|----------|------|------------------|
| Target manifest (`Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source`) | Acquisition handoff / survey input | Only when parser support exists (PR #54) |
| Network preflight CSV | Live posture evidence | Yes (recognized) |
| Workstation identity CSV | Live identity evidence | Yes (recognized) |

Target manifests are **not** network evidence. Do not treat them as proof of reachability or identity.

## Enforcement

Run the mechanical guard before committing anything under `targets/`:

```bash
python scripts/validate-targets-folder-policy.py
bash Tests/bash/test-targets-folder-policy-contracts.sh
```

## Related tooling

- `survey/sas-cybernet-xlsx-targets.sh` — offline xlsx → manifest (explicit local workbook paths)
- `survey/sas-survey-targets.sh` — normalize manifests for survey/audit workflows
- `survey/input/` — runtime staging (gitignored)
