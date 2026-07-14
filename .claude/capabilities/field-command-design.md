# Field Command Design Capability

## Contract

Technicians receive short, repeatable, repo-owned entrypoints rather than improvised command composition.

## Design rules

- Prefer a double-click launcher, named profile, menu, or one bounded script command for field users.
- Keep developer-only commands behind the documented IT/developer entrypoint.
- Hide multi-step composition inside scripts while keeping scope, target, mutation gate, progress, and evidence paths visible.
- Bound waits and retries; print clear stop conditions and final classifications.
- Require explicit target selection and fail closed on ambiguity.
- Generate machine-readable summaries in addition to concise operator output when the workflow produces evidence.
- Call Bash items commands/functions/scripts and PowerShell items cmdlets/functions/scripts accurately.
- For software installation, present `Inspect-LatestSoftwareInstall.cmd` as the technician result entrypoint and invoke `scripts/Show-SasSoftwareInstallResult.ps1` after the install command, after interrupted-run recovery, and before expansion or closeout.
- Never reduce software-install presentation to “exit code 0”; show classification, target rows, cleanup state, and the remaining post-install verification gate.

## Dashboard front door

Field users start with `START-HERE-SysAdminSuite-Dashboard.bat`. IT/developers use `Launch-SysAdminSuiteDashboard.Host.bat`. Do not make raw servers, `dotnet` commands, or survey scripts the default dashboard instruction.

## Used by

- `.claude/skills/field-workflow/SKILL.md`
