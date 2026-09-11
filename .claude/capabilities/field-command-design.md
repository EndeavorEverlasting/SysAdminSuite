# Field Command Design Capability

## Contract

Technicians receive short, repeatable, repo-owned entrypoints rather than improvised command composition.

## CMD-first guide invariant

- A request for a technician **guide, runbook, walkthrough, or how-to** for an executable Windows field use case is not satisfied by prose or snippets alone. It must first create or strengthen a tracked repository-owned `.cmd` launcher for that use case.
- Reuse and strengthen an existing canonical CMD when one already owns the workflow. Do not create a second launcher or a second implementation merely to satisfy the invariant.
- The CMD owns the operator journey: canonical runtime/path resolution, freshness or sealed-runtime admission, elevation when required, input generation/loading, mutation/review gates, exit-code propagation, evidence location, and concise final classification appropriate to that use case.
- Field CMDs must be launch-folder independent and Windows-username independent. Resolve machine-neutral runtime/state such as `C:\SASAL`, `%ProgramData%\SysAdminSuite`, or another registered machine-local authority; named-user Desktop, OneDrive, profile, or checkout paths are never execution authority.
- GUI buttons, dashboard actions, menus, QR capsules, shortcuts, and prose tutorials are downstream wrappers. Add or strengthen them only after the CMD/runtime contract exists and has executable validation; they delegate to that contract rather than reimplementing it.
- PowerShell/Bash snippets remain developer diagnostics or implementation detail. They are not the technician handoff when a Windows field use case lacks a proven CMD front door.
- "Functioning CMD" means the tracked launcher contract is validated at the strongest practical level available: syntax/static contracts plus an executable fixture, launcher journey, or CI execution when practical. Repository proof must not be inflated into live target acceptance.

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
