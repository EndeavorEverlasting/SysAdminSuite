# Developer Workstation Skill

Use this skill when the request concerns WezTerm, tmux workspace persistence, workstation inventory, backend lifecycle, agent readiness, repair, rollback, or a governed local developer-application lifecycle such as Cursor installation/recovery.

## Capability dependencies

- [Workstation Inventory](../../capabilities/workstation-inventory.md)
- [Workstation Planning](../../capabilities/workstation-planning.md)
- [Workstation Managed Configuration](../../capabilities/workstation-managed-configuration.md)
- [Workstation Backend Lifecycle](../../capabilities/workstation-backend-lifecycle.md)
- [Workstation Session Lifecycle](../../capabilities/workstation-session-lifecycle.md)
- [Workstation Agent Domain Resolution](../../capabilities/workstation-agent-domain-resolution.md)
- [AgentSwitchboard Invocation](../../capabilities/agentswitchboard-invocation.md)
- [Workstation Rollback](../../capabilities/workstation-rollback.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)

## Canonical references

- Profile and domain contract: [`docs/DEVELOPER_WORKSTATION_PROVISIONING.md`](../../../docs/DEVELOPER_WORKSTATION_PROVISIONING.md)
- Windows service: [`scripts/Invoke-SasWindowsTmuxWorkspace.ps1`](../../../scripts/Invoke-SasWindowsTmuxWorkspace.ps1)
- Native Linux service: [`scripts/invoke-sas-linux-tmux-workspace.sh`](../../../scripts/invoke-sas-linux-tmux-workspace.sh)
- Inventory: [`docs/DEVELOPER_WORKSTATION_INVENTORY.md`](../../../docs/DEVELOPER_WORKSTATION_INVENTORY.md)
- Trigger record: [`harness/api/developer-workstation-agent-routing.json`](../../../harness/api/developer-workstation-agent-routing.json)
- Cursor local application lifecycle: [`docs/CURSOR_WORKSTATION_LIFECYCLE.md`](../../../docs/CURSOR_WORKSTATION_LIFECYCLE.md)

## Workflow

1. When the task specifically names Cursor installation, uninstall, duplicate/stale registrations, `Cursor (User)`, `unins000.dat`, Error 32, system-wide installation, or clean reinstall, load only `docs/CURSOR_WORKSTATION_LIFECYCLE.md`, `Config/cursor-workstation-profile.json`, and `scripts/Invoke-SasCursorWorkstation.ps1` in addition to this skill. Route application behavior through `Manage-Cursor.cmd`; do not reinvent a one-off purge snippet.
2. For a Cursor-local failure, inventory local registrations/install roots/processes/CLI state before expanding the hypothesis to vendor-service or network failure. Local anomalies are evidence; a clean local install does not itself prove remote service health.
3. For terminal/workspace work, identify the terminal context as `Windows PowerShell`, `WezTerm/tmux Bash`, or `file content: Lua`.
4. Inventory before selecting Windows WSL, native Linux, or the Windows PowerShell fallback.
5. Default to Inventory, Status, Plan, or the Cursor `Audit`/`Verify` read-only operations. Apply, Repair, Rollback, Cursor install/uninstall, and Cursor recovery purge require explicit operator authorization.
6. Route Windows WSL lifecycle to the PowerShell service and native Linux lifecycle to the Bash service.
7. When already inside tmux, route to Status or current-session use; never start nested tmux.
8. Route agent checks through AgentSwitchboard using the selected execution domain. Preserve native, bridge, missing, and authentication-required truth.
9. Route Lua changes to the managed configuration operation; never paste Lua into PowerShell or Bash.
10. Report fixture, command acknowledgement, observed behavior, persistence, live runtime, and operator acceptance as distinct proof levels.

## Inputs and outputs

- Inputs: requested operation, platform, execution domain, terminal context, mutation authorization, optional fixture path, and for Cursor system installation an operator-downloaded installer path.
- Outputs: lifecycle result, registered artifact roles where applicable, concise English classification, and explicit next action.

## Forbidden conditions

- No automatic authentication, secret context, home-file ingestion, silent Apply, Mac support, nested tmux, or prompt-only launcher implementation.
- For Cursor, do not silently install the user-scoped build, use `winget`/Chocolatey as an unreviewed substitute, delete user state without the explicit purge switch, reinstall over unresolved residue, or assume a vendor outage before auditing local evidence when local installation anomalies are present.
- Do not claim application execution from skill/routing proof. Product scripts and the orchestrator own behavior; live GUI smoke tests remain separate observed runtime evidence.

## Proof ceiling

Routing and manifest tests prove agent-harness behavior only. They do not prove launcher execution, GUI behavior, agent interaction, persistence, a live Cursor purge/install, or vendor-service health. Cursor repository/CI proof is further bounded by `docs/CURSOR_WORKSTATION_LIFECYCLE.md`.
