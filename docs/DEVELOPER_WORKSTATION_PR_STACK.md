# Developer Workstation PR Recovery Ledger

Snapshot: 2026-07-15, based on `origin/main` at
`dacfc07f83565f8d4a32f2628ae473136d66206d`.

| PR | Unique reusable work | Decision | Merge posture |
|---|---|---|---|
| #199 | Profile schema, sanitized sample, contract tests, routing | SUPERSEDE after v3 is published | BLOCKED: v2 makes Windows-native PowerShell primary |
| #201 | Read-only Windows/Linux collectors, fixtures, renderers, CI | REPAIR on the v3 lifecycle base | BLOCKED until domains and backend health are modeled |
| #202 | Backup/apply/rollback helpers, Lua rendering, launcher tests | SUPERSEDE with the Windows tmux service | BLOCKED: PowerShell-primary architecture and failing CI |
| #203 | Proof schema, runner, profiles, workflow, merge-readiness report | REPAIR after the one-command orchestrator | BLOCKED: stacked on #202 and fixture proof inherits its model |
| #204 | Tutorial structure, quick starts, routing, convergence report | REPAIR during final convergence | BLOCKED: documents WSL as optional and the old command surface |

No PR in this stack is merge-ready while it depends on the v2
PowerShell-primary model. Unique work must be preserved in its named replacement
before an old PR is closed. No force-push is required.

## Dependency order

```text
v3 profile contract
-> lifecycle evidence spine
-> domain inventory + AgentSwitchboard domain contract
-> Windows and Linux services
-> agent harness
-> one-command orchestrator
-> fixture E2E
-> live platform proof
-> operator tutorial and convergence
```
