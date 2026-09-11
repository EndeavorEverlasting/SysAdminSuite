# Developer Workstation Skill

Use this skill when the request concerns WezTerm, tmux workspace persistence, workstation inventory, backend lifecycle, agent readiness, repair, rollback, or a governed local developer-application diagnosis such as Cursor installation/recovery.

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
- Cursor read-only lifecycle: [`docs/CURSOR_WORKSTATION_LIFECYCLE.md`](../../../docs/CURSOR_WORKSTATION_LIFECYCLE.md)

## Workflow

1. When a request names Cursor install/uninstall, `Cursor (User)`, duplicate registrations, `unins000.dat`, or Error 32, route through `Manage-Cursor.cmd Audit` first. Load the Cursor lifecycle document and canonical profile; do not invent a purge snippet.
2. The current Cursor floor is read-only. `Audit` and `Verify` are allowed; install, uninstall, recovery purge, PATH edits, process termination, and user-state deletion remain unavailable until the hardened mutation lane is separately proven.
3. For a Cursor-local failure, inventory registrations/install roots/process paths/CLI resolution before expanding the hypothesis to vendor-service or network failure. A clean local install does not prove remote service health.
4. For terminal/workspace work, identify the terminal context as `Windows PowerShell`, `WezTerm/tmux Bash`, or `file content: Lua`.
5. Inventory before selecting Windows WSL, native Linux, or the Windows PowerShell fallback.
6. Default to Inventory, Status, Plan, or Cursor Audit/Verify. Apply, Repair, and Rollback require explicit operator authorization.
7. Route Windows WSL lifecycle to the PowerShell service and native Linux lifecycle to the Bash service.
8. When already inside tmux, route to Status or current-session use; never start nested tmux.
9. Route agent checks through AgentSwitchboard using the selected execution domain. Preserve native, bridge, missing, and authentication-required truth.
10. Route Lua changes to the managed configuration operation; never paste Lua into PowerShell or Bash.
11. Report fixture, command acknowledgement, observed behavior, persistence, live runtime, and operator acceptance as distinct proof levels.

## Inputs and outputs

- Inputs: requested operation, platform, execution domain, terminal context, mutation authorization, optional fixture path.
- Outputs: lifecycle result, registered artifact roles, concise English classification, and explicit next action.

## Forbidden conditions

- No automatic authentication, secret context, home-file ingestion, silent Apply, Mac support, nested tmux, or prompt-only launcher implementation.
- For Cursor, do not perform install/uninstall/purge on this safety floor and do not manually emulate those disabled actions.
- Do not claim application execution from this skill. Product scripts and the orchestrator own behavior.

## Proof ceiling

Routing and manifest tests prove agent-harness behavior only. They do not prove launcher execution, GUI behavior, agent interaction, persistence, another Windows user's profile state, or a live Cursor repair.
