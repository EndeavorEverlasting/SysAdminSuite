# Developer Workstation Skill

Use this skill when the request concerns WezTerm, tmux workspace persistence, workstation inventory, backend lifecycle, agent readiness, workstation-hosted application deployment, repair, or rollback.

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
- Resume Matcher application service: [`docs/RESUME_MATCHER_WORKSTATION.md`](../../../docs/RESUME_MATCHER_WORKSTATION.md), [`scripts/invoke-sas-resume-matcher-workstation.sh`](../../../scripts/invoke-sas-resume-matcher-workstation.sh), and [`scripts/Invoke-SasResumeMatcherWorkstation.ps1`](../../../scripts/Invoke-SasResumeMatcherWorkstation.ps1)

## Workflow

1. Identify the terminal context as `Windows PowerShell`, `WezTerm/tmux Bash`, or `file content: Lua`.
2. Inventory before selecting Windows WSL, native Linux, or the Windows PowerShell fallback.
3. Default to Inventory, Status, or Plan. Apply, Repair, Rollback, and application lifecycle mutation require explicit operator authorization.
4. Route Windows WSL lifecycle to the PowerShell service and native Linux lifecycle to the Bash service.
5. Route Resume Matcher install, validate, start, status, and stop requests to the dedicated application service; do not force a source-built WSL application into the Windows EXE/MSI approved-package catalog.
6. When already inside tmux, route to Status or current-session use; never start a nested interactive tmux client. Repo-owned detached application sessions may be managed by their product service.
7. Route agent checks through AgentSwitchboard using the selected execution domain. Preserve native, bridge, missing, and authentication-required truth.
8. Route Lua changes to the managed configuration operation; never paste Lua into PowerShell or Bash.
9. Report fixture, configuration, launcher, health, live runtime, and operator acceptance as distinct proof levels.

## Inputs and outputs

- Inputs: requested operation, platform, execution domain, terminal context, mutation authorization, optional fixture path, and optional application deployment profile.
- Outputs: lifecycle result, registered artifact roles, concise English classification, and explicit next action.

## Forbidden conditions

- No automatic authentication, secret context, home-file ingestion, silent Apply, Mac support, nested interactive tmux, or prompt-only launcher implementation.
- Do not place source-built WSL applications in the Windows approved EXE/MSI catalog merely to reuse an installer menu.
- Do not claim application execution from routing or manifest tests. Product scripts and the orchestrator own behavior.

## Proof ceiling

Routing and manifest tests prove agent-harness behavior only. They do not prove launcher execution, GUI behavior, provider authentication, uploaded-resume handling, application interaction, PDF export, or persistence.
