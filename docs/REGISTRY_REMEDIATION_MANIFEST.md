# Registry Remediation Manifest Contract

## Remediation Is Not the Default Lane

This sprint defines an evidence pipeline first. Registry mutation is not the default behavior.

- Standard pipeline modes remain read-only for registry operations.
- Remediation is future-gated and must never be implied by diff classification alone.

## ApprovedRemediation Gating Requirement

Registry mutation requires explicit **ApprovedRemediation** mode.

No registry writes are allowed unless all of the following are true:

1. ApprovedRemediation mode is explicitly selected.
2. A remediation manifest is provided.
3. Rollback evidence requirements are satisfied.
4. Clear mutation logs are emitted and preserved.

## Required Manifest Fields

Any remediation manifest contract must include at minimum:

- `software_id`
- `target_key`
- `value_name`
- `value_type`
- `desired_value`
- `reason`
- `approved_by`
- `rollback_required`
- `rollback_plan`

These fields establish accountability, intent, and rollback posture before any write operation is considered.

## Rollback Evidence Requirement

Before applying any registry mutation under ApprovedRemediation:

- Capture pre-remediation evidence for affected keys/values.
- Record rollback plan steps as actionable evidence.
- Preserve enough state to verify and execute rollback if required.
- Emit post-action evidence confirming resulting state.

Rollback evidence must be exportable with the same evidence-first discipline as install diff runs.

## Clear Logging Requirement

Remediation logs must be explicit and reviewable:

- Who approved the change (`approved_by`).
- Why the change is necessary (`reason`).
- What key/value was targeted.
- What previous value existed (if any) and what desired value was applied.
- Whether rollback was required and whether rollback was tested or executed.
- Final status and exported evidence location.

## Sprint Scope Statement

This sprint may document remediation requirements without implementing remediation execution.

Documented remediation contracts are valid as design guardrails even when write-path implementation is deferred.
