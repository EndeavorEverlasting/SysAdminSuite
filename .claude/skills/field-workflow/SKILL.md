# Field Workflow Skill

Use this skill for technician commands, launchers, menus, QR command capsules, operator runbooks, or dashboard entry guidance.

## Capability dependencies

- [Field Command Design](../../capabilities/field-command-design.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Workflow

1. Identify the field user, target environment, and mutation posture.
2. Prefer an existing launcher, profile, menu, or wrapper.
3. Reduce the technician action to one short entrypoint when practical.
4. Put target validation, elevation, retries, teardown, progress, evidence, and classification inside the repo-owned workflow.
5. Keep developer diagnostics separate from the field front door.
6. Provide a dry-run or review mode before mutation when the operation supports it.
7. Validate the launcher contract and the delegated workflow separately.

## Guardrails

- Do not require technicians to memorize run IDs or reconstruct long commands when state can be stored locally and safely.
- Do not hide scope, mutation, or failure classifications.
- A launcher ACK is not proof that the intended behavior occurred.
