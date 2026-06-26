# Approved Update Flow

SysAdminSuite can check for newer files, but it must never update silently. The
user approves the update first, similar to an app update prompt.

## Delivery Modes

| Local copy | How updates work | Safety rule |
|------------|------------------|-------------|
| Source clone (`.git` present) | Compare local `main` with `origin/main`; update with `git pull --ff-only` after approval | Only clean local `main` can auto-update |
| ZIP / field package (`.git` absent) | Read a trusted update manifest, verify the package SHA256, then replace package content after approval | Only checksum-verified packages can apply |

The launcher may check for updates before opening the dashboard. If an update is
available, it asks the user before applying it. If the check fails, the dashboard
continues with the current local copy.

## Source Clone Rules

For developer and IT git clones:

1. Run `git fetch origin`.
2. Confirm the current branch is `main`.
3. Confirm `git status --short` is clean.
4. Confirm there are no local-only commits.
5. Confirm the update can be applied with `git pull --ff-only origin main`.
6. Ask the user for approval.
7. Apply the fast-forward update only after approval.

The updater must not run `git reset --hard`, delete branches, or update feature
branches automatically.

## Field Repair Lane

The approved launcher update is intentionally conservative. It is not the same
as the explicit field repair updater:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Update-SysAdminSuite.ps1
```

Use the repair updater only when a tech needs the local `SysAdminSuite` folder to
match official `origin/main`. It shows stage-based progress, can back up an
existing non-git folder, and then runs `git fetch origin`, `git checkout main`,
`git reset --hard origin/main`, and `git clean -fd` inside the intended install
path. Local edits inside the repo are discarded by design.

Do not run `git clone` over an existing copy. Use the repair updater instead, or
manually move the old folder aside first.

If the folder is not `%USERPROFILE%\Desktop\SysAdminSuite`, pass the actual path
with `-InstallRoot`. The repair updater asks the tech to type `YES` before
starting destructive repo repair. Routine field release ZIP/package updates
should stay on the launcher and checksum manifest flow; the repair updater
creates a fresh Git clone when it is pointed at a non-git folder.

See [`FIELD_TECH_UPDATE.md`](FIELD_TECH_UPDATE.md) for the tech-facing runbook.

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

`START-HERE-SysAdminSuite-Dashboard.bat` checks with the helper. It only prompts
when the helper reports an available update. If the user says no, or if the
check needs manual review, the dashboard opens from the current local copy.

## Related Docs

- [`REMOTE_WORKFLOW.md`](REMOTE_WORKFLOW.md) — source-clone mainline rules
- [`DEPLOYMENT_ARTIFACTS.md`](DEPLOYMENT_ARTIFACTS.md) — package manifest/update rules
- [`DASHBOARD_FIELD_RELEASE.md`](DASHBOARD_FIELD_RELEASE.md) — no-SDK field package path
- [`FIELD_TECH_UPDATE.md`](FIELD_TECH_UPDATE.md) — explicit field repair/update runbook
