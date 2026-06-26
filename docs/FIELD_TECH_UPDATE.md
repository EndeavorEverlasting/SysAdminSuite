# Field Tech Update / Repair

Use this when a tech needs the local SysAdminSuite folder refreshed to official
`origin/main` and the normal dashboard launcher is not enough.

If the dashboard launcher says the update check needs manual review, keep using
the current copy unless IT/project lead explicitly decides to discard local repo
state. In that case, use this repair updater.

## What To Run

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Update-SysAdminSuite.ps1
```

Or double-click:

```text
Update-SysAdminSuite.bat
```

Default install path:

```text
%USERPROFILE%\Desktop\SysAdminSuite
```

If your working copy lives somewhere else, pass it explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Update-SysAdminSuite.ps1 -InstallRoot "%USERPROFILE%\Desktop\dev\SysAdminSuite"
```

Before any destructive repo repair, the updater prints the target path and asks:

```text
Continue? Type YES to update
```

## What The Updater Shows

Progress is stage-based. It tells the tech which step is running and the percent
for that stage list:

```text
[1/7] Locate existing SysAdminSuite install - 14%
[2/7] Existing Git repo found - 29%
[3/7] Fetch latest official version - 43%
[4/7] Switch to main - 57%
[5/7] Reset local files to origin/main - 71%
[6/7] Clean stale local files - 86%
[7/7] Launch dashboard - 100%
```

Git clone and fetch operations can take time. Git may print its own network
progress while those stages are running. The wrapper does not fake byte-level
progress.

## What It Does

| Existing local state | Updater behavior |
|----------------------|------------------|
| No `SysAdminSuite` folder | Clones the official repo into the default install path |
| `SysAdminSuite` folder with `.git` | Fetches origin, checks out `main`, resets to `origin/main`, cleans stale files |
| `SysAdminSuite` folder without `.git` | Renames the folder to `SysAdminSuite.old.yyyyMMdd-HHmmss`, then clones fresh |

Do not run git clone over an existing copy. That can create nested folders such
as `SysAdminSuite\SysAdminSuite` and hide the dashboard launcher.

## Important Safety Notes

This is the explicit field repair lane. It is intentionally stronger than the
dashboard launcher's normal approved update check.

- `git reset --hard origin/main` makes tracked files match official `main`.
- `git clean -fd` removes untracked files inside the repo.
- Local edits inside the repo are discarded.
- Existing non-git folders are backed up by rename, not overwritten.
- The updater launches `START-HERE-SysAdminSuite-Dashboard.bat` when it finishes.

Do not store credentials, live evidence, or local operator output inside the repo
before running the repair updater.

## How This Differs From The Dashboard Launcher

`START-HERE-SysAdminSuite-Dashboard.bat` uses the approved update helper:

```powershell
tools\update\Invoke-SysAdminSuiteUpdate.ps1
```

That helper is conservative: it checks for a clean local `main` and applies only
a fast-forward `git pull --ff-only` after approval.

`Update-SysAdminSuite.ps1` is for explicit repair: make the folder match official
`origin/main`, clean stale files, then launch the dashboard.

Routine field release ZIP/package updates should continue to use the launcher
and checksum manifest flow. Running this repair updater against a non-git folder
backs that folder up and creates a fresh Git clone; it is not the package-update
mechanism.

## Failure Triage

If the updater fails, leave the window open and send the screen to Richard /
project lead for review. The message should say which stage failed, such as:

```text
Git fetch failed.
Git reset --hard origin/main failed.
Dashboard launcher not found: ...
```

Common causes:

- Git is not installed or not on `PATH`.
- Network access to GitHub is blocked.
- The install path is unsafe or not the expected SysAdminSuite folder.
- Endpoint policy blocks script execution.

## Follow-Up Progress Work

The shared helper lives at:

```text
tools\update\Show-SysAdminSuiteProgress.ps1
```

Future field-facing command lanes should reuse that helper or mirror its
stage-based contract:

- AD registered roster import
- toolbox status/probing
- dashboard dependency bootstrap
