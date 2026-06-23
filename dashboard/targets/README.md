# SysAdminSuite QR Target Directory

Technicians should place QR target lists in this directory:

```text
SysAdminSuite/dashboard/targets
```

The web dashboard cannot silently read local folders. Browser security requires a technician to select the folder manually.

## Workflow

1. Put target lists here as `.txt` or `.csv`.
2. Open `dashboard/index.html`.
3. Go to `QR Builder`.
4. Click `Choose Target Directory`.
5. Select this folder.
6. Pick the target file from the dropdown.
7. Choose the QR payload use case.
8. Preview the exact payload.
9. Click `Show Large QR`.

## Accepted target file formats

Plain text:

```text
hostname1
hostname2
hostname3
```

CSV with a header:

```csv
Hostname
hostname1
hostname2
hostname3
```

CSV with extra columns:

```csv
hostname1,site,notes
hostname2,site,notes
```

Only the first CSV column is used as the target.

## Notes

- Blank lines are ignored.
- Lines beginning with `#` are ignored.
- Duplicate targets are removed.
- Hostnames and IPs are accepted.
