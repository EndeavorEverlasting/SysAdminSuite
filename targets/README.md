# Targets

This folder is the intake hub for target-source handling in SysAdminSuite.

Use this folder as the first place to document, stage locally, or reason about approved target sources before a workflow normalizes them, surveys them, or packages evidence.

## What belongs here

Tracked content should be documentation-first:

- README and policy notes
- schema explanations
- sanitized examples only when explicitly safe
- instructions for local operators
- notes that map target-source types to downstream workflows

Local-only content may include approved live sources while an operator is actively working, but those files must not be committed.

## What does not belong in git

Do not commit live target files, including:

- production target CSVs or tracker exports
- serial-number lists
- MAC-address lists
- IP or subnet lists tied to a real site
- raw AD, CMDB, SCCM, deployment tracker, Nmap, Naabu, preflight, or workstation identity evidence
- dashboard exports or packaged survey ZIPs

## Intake versus runtime staging

`targets/` is the intake hub. Runtime folders are still used by tools.

Typical flow:

1. Put or describe the approved source under `targets/` locally.
2. Normalize the source into a target manifest when needed.
3. Stage tool-specific runtime inputs under `survey/input/` only when a workflow requires it.
4. Keep generated outputs under `survey/output/`, `survey/artifacts/`, `logs/`, or `evidence/`.
5. Commit only documentation, safe schemas, and sanitized examples.

## Target manifest versus evidence

A target manifest says what the operator intends to check.

Evidence says what a tool actually observed.

Keep them separate. A dashboard should not be documented as importing a target manifest unless parser support for that exact schema exists.

## Related policy

See [`../docs/TARGETS_FOLDER_POLICY.md`](../docs/TARGETS_FOLDER_POLICY.md).
