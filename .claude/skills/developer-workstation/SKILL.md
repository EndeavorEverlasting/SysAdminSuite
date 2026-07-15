# Developer Workstation Skill

Use this skill when the request concerns WezTerm, tmux workspace persistence, workstation inventory, backend lifecycle, agent readiness, repair, or rollback.

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

## Workflow

1. Identify the terminal context as `Windows PowerShell`, `WezTerm/tmux Bash`, or `file content: Lua`.
2. Inventory before selecting Windows WSL, native Linux, or the Windows PowerShell fallback.
3. Default to Inventory, Status, or Plan. Apply, Repair, and Rollback require explicit operator authorization.
4. Route Windows WSL lifecycle to the PowerShell service and native Linux lifecycle to the Bash service.
5. When already inside tmux, route to Status or current-session use; never start nested tmux.
6. Route agent checks through AgentSwitchboard using the selected execution domain. Preserve native, bridge, missing, and authentication-required truth.
7. Route Lua changes to the managed configuration operation; never paste Lua into PowerShell or Bash.
8. Report fixture, command acknowledgement, observed behavior, persistence, live runtime, and operator acceptance as distinct proof levels.

## Inputs and outputs

- Inputs: requested operation, platform, execution domain, terminal context, mutation authorization, optional fixture path.
- Outputs: lifecycle result, registered artifact roles, concise English classification, and explicit next action.

## Forbidden conditions

- No automatic authentication, secret context, home-file ingestion, silent Apply, Mac support, nested tmux, or prompt-only launcher implementation.
- Do not claim application execution from this skill. Product scripts and the orchestrator own behavior.

## Proof ceiling

Routing and manifest tests prove agent-harness behavior only. They do not prove launcher execution, GUI behavior, agent interaction, or persistence.
