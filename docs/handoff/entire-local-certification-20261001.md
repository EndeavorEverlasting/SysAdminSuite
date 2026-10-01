# Entire local certification — SysAdminSuite (2026-10-01)

| Field | Value |
|---|---|
| Lane | Local AI continuity stack (independent of H&H firmware) |
| Architecture owner | AgentSwitchboard `docs/architecture/entire-cli-provider-continuity-boundary.md` |
| Architecture floor | AgentSwitchboard `main` @ `07eca00b` (PR #358) |
| This repository role | Execute and record local Entire enablement for SysAdminSuite continuity |
| H&H firmware coupling | **None.** Firmware remains quiescent at the estate-authority packet gate. |

## Decision reused (do not rediscover)

Entire CLI is provider-neutral Git / provenance / checkpoint / agent-session transport.

```text
AgentSwitchboard  -> routing / authority / evidence policy
FirstMate         -> live crew runtime where applicable
Entire CLI        -> Git/provenance/session transport and recovery
Coding agent      -> execution (OpenCode / Cursor / other)
model/provider    -> inference
```

GitHub / GitHub Actions are optional adapters. No silent paid-model fallback.

Canonical discovery and enable commands (from the AgentSwitchboard contract):

```text
entire agent-help --json
entire status --json
entire enable --agent opencode --telemetry=false
entire session resume <branch>
```

Do not invent syntax beyond what the installed CLI reports.

## Certification scope

Prove only that this workstation can:

1. discover Entire capability;
2. observe repository Entire status;
3. enable Entire for OpenCode with telemetry off using the contract command;
4. optionally install Cursor hooks so the current executor is also covered;
5. re-read `entire status --json` and record the post-enable floor.

Out of scope for this sprint:

- H&H firmware mutation or reader diagnostics;
- FirstMate crew relaunch proof;
- remote checkpoint push proof;
- Entire as an inference provider;
- redesign of the AgentSwitchboard architecture contract.

## Observed preflight (before enable)

```text
CLI: entire 0.10.6 (windows/amd64) at %USERPROFILE%\.local\bin\entire.exe
auth status: logged in (identity present; token stored in OS credential manager)
agent-help --json: capability surface returned
status --json: {"enabled":false,"agents":null,"active_sessions":null,"error":"not set up"}
agent list: available agents include opencode and cursor; none installed
```

## Required certification sequence

Run from an isolated current-`main` SysAdminSuite worktree (never from a stale feature worktree):

```powershell
Set-Location "<current-main SysAdminSuite worktree>"
entire agent-help --json
entire status --json
entire auth status
entire enable --agent opencode --telemetry=false
entire status --json
entire agent add cursor
entire status --json
```

Pass criteria:

- `entire status --json` reports `enabled: true` (or equivalent installed/enabled state without `error: not set up`);
- OpenCode is listed among installed agents;
- telemetry remains disabled per the enable invocation;
- no H&H firmware files are mutated as part of this lane except intentional continuity docs/handoffs;
- repository validators for any tracked doc changes remain green.

Fail / stop conditions:

- enable requires an interactive login the operator cannot complete → record `BLOCKED_AUTH` and stop;
- enable wants to bootstrap a new GitHub remote or rewrite remotes unexpectedly → refuse and record the exact prompt;
- any step attempts firmware/reader work → abort; wrong lane.

## Post-enable floor (live readback 2026-10-01)

```text
CERT_UTC=2026-10-01T21:31:02Z
WORKTREE=C:\Dev\SysAdminSuite-hh-cc-mgmt-plane-20261001
REPO_HEAD=024a12b52a52f06714bc9e8dad10d796bd70a5a2
ENTIRE_VERSION=0.10.6
ENABLE_COMMAND=entire enable --agent opencode --telemetry=false
ENABLE_EXIT=0
STATUS_JSON={"enabled":true,"agents":["Cursor","OpenCode"],"active_sessions":[],"agent_help":"entire agent-help","checkpoint_sync_remote":"origin","checkpoint_sync_remote_source":"default"}
INSTALLED_AGENTS=OpenCode (contract), Cursor (workstation executor add)
TELEMETRY=false
SESSION_RESUME_SURFACE=entire session resume <branch>
TRACKED_ENABLEMENT=.entire/settings.json ; .entire/.gitignore ; .opencode/plugins/entire.ts ; .cursor/hooks.json
PROOF_CEILING=local enable + status readback only (no remote checkpoint push proof; no FirstMate relaunch proof)
CERT_RESULT=PASS
```

## Separation from H&H firmware

This certification **PASS** improves local agent continuity. It does **not**:

- close the estate-authority evidence packet;
- prove PAXSTORE/reseller/processor access;
- authorize firmware assignment or pilot.

Firmware next evidence remains the packet in `docs/HH_CC_READER_NETSTAT_BASELINE.md` section **Estate-authority evidence packet**.
