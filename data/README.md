# Data Storage Policy

SysAdminSuite can work with deployment tracker workbooks, but workbook data must be organized so raw evidence is never confused with generated output.

## Directory Contract

```text
data/
├── raw/             # Untouched source files exactly as received
├── backups/         # Timestamped byte-for-byte backup copies before any edit
├── experiments/     # Scratch copies used for parser/audit experiments
├── outputs/         # Generated CSV, JSON, logs, reports, and ZIPs
└── updated/         # Candidate workbooks produced by tools
```

## Rule Zero

Never modify files in `data/raw/`.

Raw files are evidence. Treat them like the original x-ray, not the doctor's markup.

## Recommended Naming

Use timestamped names so files survive box-to-box movement without becoming a fog bank.

```text
data/raw/DeploymentTracker_2026-04-20_SOURCE.xlsx
data/backups/DeploymentTracker_2026-04-20_BACKUP_2026-05-02_2015.xlsx
data/experiments/DeploymentTracker_2026-04-20_EXP_duplicate-audit_2026-05-02.xlsx
data/outputs/deployment_audit_2026-05-02_2015.zip
data/updated/DeploymentTracker_2026-04-20_CANDIDATE_duplicate-fix_2026-05-02.xlsx
```

## Public Repository Warning

This repository may be public. Do not commit live deployment trackers, client data, device identifiers, hostnames, MAC addresses, serials, location records, or operational evidence to a public repo unless explicitly approved and sanitized.

For public repo work:

- Commit folder structure, scripts, schemas, and redacted examples.
- Keep live workbooks local, encrypted, or in a private repo.
- Use `data/raw/` only in private working copies unless the file is synthetic or scrubbed.

## Safe Workflow

1. Copy incoming workbook into `data/raw/`.
2. Immediately create a timestamped copy in `data/backups/`.
3. Run audit tools against `data/raw/...` or the backup copy.
4. Write generated reports to `data/outputs/`.
5. Write edited workbook candidates to `data/updated/`.
6. Never overwrite the raw source.

## Bash Audit Example

```bash
./deployment-audit/sas-audit-deployments.sh \
  --workbook data/raw/DeploymentTracker_2026-04-20_SOURCE.xlsx \
  --sheet Deployments \
  --output-dir data/outputs/deployment_audit_2026-05-02_2015
```

## Promotion Rule

A candidate workbook becomes the new source only after human review. When promoted, copy it into `data/raw/` with a new source date/version. Do not overwrite the old source.
