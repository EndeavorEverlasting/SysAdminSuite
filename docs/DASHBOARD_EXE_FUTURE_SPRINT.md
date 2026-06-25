# Future Sprint: SysAdminSuite Dashboard EXE

**Status:** planned — not implemented in the current repo ship path.

**Current field entry (use now):** double-click [`START-HERE-SysAdminSuite-Dashboard.bat`](../START-HERE-SysAdminSuite-Dashboard.bat).

## Problem

Lay users are comfortable with `.exe` shortcuts on the desktop. The repo today ships the **`START-HERE-SysAdminSuite-Dashboard.bat` launcher** (with `.cmd` compatibility aliases) plus a **local publish script** that builds `SysAdminSuite Dashboard.exe` into gitignored `dist/`. That is sufficient for time-boxed delivery but not as familiar as a single committed or installer-bundled executable.

## Goal

Give field users an `.exe` they can pin, shortcut, or receive in a portable zip **without** requiring them to understand git, dotnet, or batch files.

## Non-goals (this sprint)

- Replacing the Bash survey CLI path
- Merging unrelated Cybernet PR lanes
- Committing large self-contained runtimes without an explicit size/signing decision

## Proposed deliverables

1. **Published artifact**
   - `SysAdminSuite Dashboard.exe` with friendly name and Harold tray icon
   - Framework-dependent (.NET 8 runtime) or self-contained (explicit size tradeoff)
   - Optional: copy into portable zip `app/bin/` via `New-PortableArtifact.ps1`

2. **Root shortcut**
   - Either commit a small bootstrap `.exe` that shells the host, or document that portable zip includes the exe at a fixed path
   - Keep the `.bat` launcher (and `.cmd` aliases) as fallback for git clones

3. **Signing / trust**
   - Align with `docs/GUI_HOST_MIGRATION.md` follow-up: Authenticode signing like native mapping binaries

4. **Agent docs update**
   - Update [`DASHBOARD_ENTRYPOINT.md`](DASHBOARD_ENTRYPOINT.md) launcher matrix
   - Update [`START-HERE-SysAdminSuite.md`](../START-HERE-SysAdminSuite.md) when EXE becomes primary

## Existing building blocks

| Asset | Location |
|-------|----------|
| Tray host project | `src/SysAdminSuite.DashboardHost/` |
| Publish script | `tools/publish-dashboard-entrypoint.ps1` |
| Host launcher | `Launch-SysAdminSuiteDashboard.Host.bat` |
| Field launcher | `START-HERE-SysAdminSuite-Dashboard.bat` (`.cmd` aliases) |
| Harold favicon | `dashboard/assets/harold.jpg` |

## Acceptance criteria

- [ ] Field tech double-clicks one obvious `.exe` (or portable zip entry) with no dotnet/SDK on machine (if self-contained) or documented runtime prerequisite (if framework-dependent)
- [ ] Browser opens `http://127.0.0.1:5000/dashboard/` with Harold favicon
- [ ] Tray icon works (Open / Copy URL / Stop)
- [ ] `START-HERE-SysAdminSuite-Dashboard.bat` (and `.cmd` aliases) still work for git-clone workflows
- [ ] `dist/` remains gitignored unless release policy explicitly commits release artifacts elsewhere
- [ ] Contract tests cover launcher matrix and forbid committed `dist/` binaries

## Suggested implementation order

1. Extend `tools/publish-dashboard-entrypoint.ps1` with optional `-SelfContained` and icon metadata
2. Wire `tools/build/New-PortableArtifact.ps1` to require publish output
3. Add CI job that builds exe into artifact upload (not git commit) for portable packages
4. Evaluate committed vs CI-only exe with repo size policy
5. Update field docs to list EXE as primary when available

## Agent prompt (copy-paste for next sprint)

```text
Implement the Dashboard EXE sprint per docs/DASHBOARD_EXE_FUTURE_SPRINT.md.

Start from main. Preserve START-HERE-SysAdminSuite-Dashboard.bat (canonical) and its .cmd aliases as fallback.
Do not touch survey logic or PR lanes #80/#83/#84/#86 without authorization.
Publish SysAdminSuite Dashboard.exe via tools/publish-dashboard-entrypoint.ps1,
wire portable artifact build if appropriate, update DASHBOARD_ENTRYPOINT.md and
START-HERE-SysAdminSuite.md, add contract tests, do not commit dist/ output.
```
