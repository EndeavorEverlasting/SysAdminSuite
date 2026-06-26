# Approved Update Flow

SysAdminSuite can check for newer files, but it must never update silently. The
user approves the update first, similar to an app update prompt.

## Delivery Modes

| Local copy | How updates work | Safety rule |
|------------|------------------|-------------|
| Source clone (`.git` present) | Compare local `main` with `origin/main`; update with `git pull --ff-only` after approval | Only clean local `main` can auto-update |
| ZIP / field package (`.git` absent) | Read a trusted update manifest, verify the package SHA256, then replace package content after approval | Only checksum-verified packages can apply |

The launcher may check for updates before opening the dashboard. If local `main`
is behind `origin/main`, it warns the user and explains the update path. If the
clean-main fast-forward gates pass, it asks before applying the update. If the
user skips, the check fails, or the repo needs manual review, the dashboard
continues with the current local copy and shows a local freshness banner.

## Source Clone Rules

For developer and IT git clones:

1. Run `git fetch origin`.
2. Compare local `main` with `origin/main` and record the behind/ahead counts.
3. Confirm the current branch is `main`.
4. Confirm `git status --short` is clean.
5. Confirm there are no local-only commits.
6. Confirm the update can be applied with `git pull --ff-only origin main`.
7. Ask the user for approval.
8. Apply the fast-forward update only after approval.

The updater must not run `git reset --hard`, delete branches, or update feature
branches automatically.

## ZIP / Field Package Rules

For users who downloaded a ZIP or received a field release package:

1. Read `manifest/update-manifest.json` or a configured manifest path/URL.
2. Compare the manifest with the current package.
3. Ask the user for approval.
4. Download or copy the package to a temporary folder.
5. Verify `checksumSha256`.
6. Back up the current app/root content.
7. Apply the package.

The updater must not use credentials, broaden scans, mutate endpoints, or commit
runtime evidence.

## Helper

The shared helper is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\update\Invoke-SysAdminSuiteUpdate.ps1 -CheckOnly
```

Machine-readable state for launchers and the dashboard:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\update\Invoke-SysAdminSuiteUpdate.ps1 -CheckOnly -Json
```

Launchers write the same state to `dashboard/repo-freshness.json`. That file is
runtime-only and ignored by git.

Apply only after user approval:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\update\Invoke-SysAdminSuiteUpdate.ps1 -Apply -Approved
```

Exit codes:

| Code | Meaning |
|------|---------|
| `0` | No update available, or update applied successfully |
| `1` | Error |
| `10` | Update available; approval required |
| `20` | Manual review required |

## Launcher Behavior

`START-HERE-SysAdminSuite-Dashboard.bat` checks with the helper. It warns when
the local source clone is behind `origin/main`, and only prompts to apply when a
clean `main` fast-forward is safe. If the user says no, or if the check needs
manual review, the dashboard opens from the current local copy and reads
`dashboard/repo-freshness.json` to show a persistent behind-main banner.

## Related Docs

- [`REMOTE_WORKFLOW.md`](REMOTE_WORKFLOW.md) — source-clone mainline rules
- [`DEPLOYMENT_ARTIFACTS.md`](DEPLOYMENT_ARTIFACTS.md) — package manifest/update rules
- [`DASHBOARD_FIELD_RELEASE.md`](DASHBOARD_FIELD_RELEASE.md) — no-SDK field package path
