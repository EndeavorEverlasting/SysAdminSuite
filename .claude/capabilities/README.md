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
| [Language Runtime Selection](language-runtime-selection.md) | Choose Bash, PowerShell, Windows-native, or managed surfaces without deleting active tooling. |
| [Mutation and Evidence Boundaries](mutation-and-evidence-boundaries.md) | Separate read-only lanes, authorized mutation, teardown, and private evidence. |
| [Field Command Design](field-command-design.md) | Produce short technician entrypoints and bounded operator handoffs. |
