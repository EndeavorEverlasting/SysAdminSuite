# Developer Workstation Convergence Report

Snapshot: 2026-07-15. This report replaces the v2 PowerShell-primary report preserved from PR #204.

## Released architecture

The canonical experience is WezTerm → tmux `dev` → coding agents. Windows hosts the GUI and uses Ubuntu WSL2 for tmux. Native Linux uses local tmux. PowerShell 7 remains a fallback/admin surface. AgentSwitchboard resolves OpenCode, AGY, and Goose per execution domain, preferring native commands and requiring explicit permission for Windows bridges.

macOS is unsupported. WSL evidence never satisfies native-Linux proof.

## SysAdminSuite PR ledger

| PR | Scope | State at snapshot | Convergence decision |
|---|---|---|---|
| #199 | v2 profile contract | Draft, conflicting | Superseded by merged v3 #205. Close; preserve branch. |
| #201 | v2 inventory | Draft, conflicting | Superseded by merged domain inventory #207. Close; preserve branch. |
| #202 | PowerShell-primary Windows profile | Draft, conflicting | Superseded by merged Windows WSL/tmux service #208. Close; preserve branch. |
| #203 | 12-case v2 fixture E2E | Draft | Superseded by 22-case v3 E2E #214. Close; preserve branch. |
| #204 | v2 tutorial and report | Draft | Useful structure salvaged and rewritten on the convergence branch. Close after the new docs PR opens. |
| #205 | v3 profile contract | Merged | Foundation retained. |
| #206 | lifecycle evidence spine | Merged | Foundation retained. |
| #207 | execution-domain inventory | Merged | Foundation retained. |
| #208 | Windows WSL/tmux service | Merged | Foundation retained. |
| #209 | native-Linux service | Open, conflicting | Unique implementation is already present in merged #210. Close as superseded; preserve branch. |
| #210 | agent harness plus converged Windows/Linux services | Merged | Foundation retained. |
| #212 | one-command orchestrator | Open | Merge next after repaired `windows-integration` turns green. |
| #214 | 22-journey fixture E2E | Open | Merge after #212. |
| #215 | Windows live-runtime fixes and proof harness | Open | Merge after #214. |
| #216 | native-host blocker preparation fix | Open | Merge after #215. |
| convergence PR | tutorial, routing, release ledger | This branch | Merge last. |

## AgentSwitchboard PR ledger

| PR | Scope | Decision |
|---|---|---|
| #4 | Windows CLI bootstrap | Close as superseded after #10; unique command/bootstrap intent is preserved. |
| #6 | WSL bootstrap | Close as superseded after #10; useful bootstrap and dotfile safety work is preserved. |
| #9 | versioned invocation API | Close as superseded after #10; v2 request/result contracts are preserved. |
| #10 | multi-domain wrapper and runtime convergence | Merge before relying on live SysAdminSuite agent routing. |

No branch is deleted and no old PR is closed until its unique work has a named replacement.

## Required merge order

1. AgentSwitchboard #10.
2. SysAdminSuite #212.
3. SysAdminSuite #214.
4. SysAdminSuite #215.
5. SysAdminSuite #216.
6. The SysAdminSuite convergence PR.

PRs #205, #206, #207, #208, and #210 are already merged. PR #209 is not a missing dependency because its native-Linux implementation was preserved in #210 before merge.

## CI repair

The shared `windows-integration` failure on #212, #214, and #215 was traced to Bash path conversion. The orchestrator emitted WSL `/mnt/<drive>` paths even when GitHub’s Windows runner selected Git Bash, which requires `/<drive>`. Commit `3535755` classifies the active Bash launcher and has deterministic tests for both WSL and Git Bash paths. The fix is propagated through every downstream branch without rebasing or force-pushing.

Local validation for that repair: 7 orchestrator contract groups pass, including the full required-failure matrix.

## Proof ledger

| Layer | Result | Evidence and ceiling |
|---|---|---|
| Profile, lifecycle, inventory, services, adapter, orchestration | PASS | Static contracts and disposable fixture lifecycles. |
| Persistent workstation fixture E2E | 22 passed / 0 skipped / 0 failed | Public entrypoint, fixture/loopback only. |
| Windows live runtime | PASS | `dev` survived detach and exact GUI closure; the generated shortcut reopened the same four windows. |
| Agent command interaction | PASS, bounded | `opencode`, `agy`, and `goose` canonical wrappers each acknowledged keyboard-driven `--help`; selected backend was bridge for all three. |
| Authentication and provider response | Not proven | No authentication, token, chat content, provider response, or response quality was captured. |
| Native Linux live runtime | Blocked | Available kernel is `microsoft-standard-WSL2`; native Linux WezTerm GUI is missing. Inventory only; no native Plan or Apply. |
| Operator acceptance | Not recorded | Automation cannot accept the workstation experience for the operator. |

Ignored runtime artifacts remain local:

- `survey/output/workstation-live/windows-20260715-sprint10/15-live-proof-pass/windows-live-proof.json`
- `survey/output/workstation-live/windows-20260715-sprint10/15-live-proof-pass/tmux-before.json`
- `survey/output/workstation-live/windows-20260715-sprint10/15-live-proof-pass/tmux-after-detach.json`
- `survey/output/workstation-live/windows-20260715-sprint10/15-live-proof-pass/tmux-after-reopen.json`
- `survey/output/workstation-live/linux-20260715-sprint11/02-inventory-fixed.json`

The Windows proof records `operator_accepted=false`, `authentication_observed=false`, and `provider_response_observed=false`. Its interaction scope is `canonical-wrapper-help-command-only`.

## Live safety decisions

The recovery sprint left the proven Windows workspace running after reattach. Stop and live Rollback were not executed because tmux `dev` existed before the sprint and contained an operator-owned window; destroying it without fresh post-proof confirmation would terminate persistent shells and agents. Fixture Stop/Rollback remain covered, and the original live backup manifest was preserved across idempotent Apply.

## Canonical entrypoints

- Windows operator: `scripts/Invoke-SasDeveloperWorkstation.ps1`.
- Native Linux operator: `scripts/invoke-sas-developer-workstation.sh`.
- Windows daily GUI: generated `WezTerm tmux` desktop shortcut.
- Fixture E2E: `scripts/Invoke-SasWorkstationE2E.py` or its PowerShell/Bash front doors.
- Windows live proof: `scripts/Invoke-SasWindowsWorkstationLiveProof.ps1`.
- Full tutorial: `docs/tutorials/DEVELOPER_WORKSTATION.md`.

## Remaining owners

- Repository maintainer: merge AgentSwitchboard #10, then the ordered SysAdminSuite stack after required checks pass.
- Native-Linux host owner: run the live sprint on a real graphical Linux machine and attach ignored artifacts; WSL is not acceptable.
- Workstation operator: record acceptance or rejection after daily keyboard use; automation must leave this field false.
