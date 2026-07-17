# SysAdminSuite Agent Capabilities

Capabilities are stable, reusable rule modules. Skills compose capabilities into task-specific workflows.

## Contract

- A capability defines one bounded concern and its invariants.
- A capability does not duplicate a full task workflow.
- A skill must name its capability dependencies explicitly.
- Agents load only capabilities required by the selected skills.
- Product behavior remains authoritative in schemas, workflow specs, scripts, and canonical docs; capabilities route agents to those surfaces.

## Machine-readable catalog

The authoritative metadata catalog is `harness/api/agent-capability-manifest.json`. Its contract is
`schemas/harness/agent-capability-manifest.schema.json`.

Markdown remains the human-readable operating law. The manifest supplies IDs, versions, paths, lanes,
default network and target-mutation posture, authority paths, validators, and exact skill-to-capability
dependencies for harness consumers and future bounded adapters.

## Catalog

| Capability | Concern |
|---|---|
| [Repository Evidence](repository-evidence.md) | Recover Git/repo truth and preserve concurrent work. |
| [Proof and Checkpointing](proof-and-checkpointing.md) | Preserve progress and classify validation/runtime proof honestly. |
| [End-to-End Testing](end-to-end-testing.md) | Make closed-loop fixture, loopback, and authorized runtime journeys the default merge/release proof target. |
| [Language Runtime Selection](language-runtime-selection.md) | Choose Bash, PowerShell, Windows-native, or managed surfaces without deleting active tooling. |
| [Mutation and Evidence Boundaries](mutation-and-evidence-boundaries.md) | Separate read-only lanes, authorized mutation, teardown, and private evidence. |
| [Field Command Design](field-command-design.md) | Produce short technician entrypoints and bounded operator handoffs. |
| [Workstation Inventory](workstation-inventory.md) | Observe terminal, execution-domain, backend, tmux, service, and agent state. |
| [Workstation Planning](workstation-planning.md) | Produce a read-only domain-correct plan. |
| [Workstation Managed Configuration](workstation-managed-configuration.md) | Route bounded backup-first configuration. |
| [Workstation Backend Lifecycle](workstation-backend-lifecycle.md) | Route Windows WSL and native-Linux backend lifecycle. |
| [Workstation Session Lifecycle](workstation-session-lifecycle.md) | Route deterministic tmux Start, Status, and Stop. |
| [Workstation Agent Domain Resolution](workstation-agent-domain-resolution.md) | Preserve native, bridge, missing, and authentication truth. |
| [AgentSwitchboard Invocation](agentswitchboard-invocation.md) | Enforce the structured cross-repository request/result boundary. |
| [Workstation Rollback](workstation-rollback.md) | Restore only manifest-owned configuration and launch surfaces. |
| [Package Static Inspection](package-static-inspection.md) | Inventory packages without execution. |
| [Package Semantic Enrichment](package-semantic-enrichment.md) | Convert static structure into bounded semantic harness requirements. |
| [Package Offline Trust Verification](package-offline-trust-verification.md) | Cache-only Authenticode and explicit trust-policy gating. |
| [Package CLR Strong-Name Verification](package-clr-strong-name-verification.md) | Offline CLR strong-name integrity for managed assemblies. |
| [Package VM Qualification Validation](package-vm-qualification-validation.md) | Fail-closed disposable-VM qualification without starting a VM. |
