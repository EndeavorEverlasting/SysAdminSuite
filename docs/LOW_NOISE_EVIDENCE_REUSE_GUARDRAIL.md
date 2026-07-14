# Low-noise evidence reuse guardrail

## Purpose

SysAdminSuite must not generate live probes just because a probe lane exists.

Naabu/Nmap output is live reachability and service-state evidence. It is not population proof, serial identity proof, target ownership proof, or permission to keep probing by itself.

Probe output may contribute to identity, population, target ownership, or action-readiness proof only when it is joined with approved source data and the match is complete, fresh, in scope, and unambiguous. Population authority stays with approved manifests, AD-derived target lists, or other approved local evidence.

## Elemental rule

If all required data is already present in approved evidence, do not probe again by default.

If live probe evidence already exists, prefer that existing evidence unless it is stale, incomplete, conflicting, ambiguous, or from the wrong approved scope.

If the existing evidence is only a partial match or an ambiguous match, it is insufficient. It may guide review, but it cannot be treated as complete reuse proof.

If a live probe must be repeated for the same target and same scope, stop at five total live probes unless a lead/operator override is recorded.

## Required decision order

Before emitting or executing a live probe command, agents, scripts, and validators must answer:

1. Is there approved existing evidence for this target/scope?
2. Are all required data fields present?
3. Is the match complete rather than partial or ambiguous?
4. Is the evidence fresh enough for the current workflow?
5. Is the evidence from the correct approved scope?
6. Is there conflicting evidence?
7. Is the live probe result joined to approved source data instead of treated as proof by itself?
8. Has this target/scope already reached five live probes?
9. If the cap is reached, is a lead/operator override recorded?

Only after this decision order may a workflow stage a live probe.

## Decision outcomes

| Evidence state | Required outcome |
|---|---|
| Complete approved evidence exists | Reuse evidence. Do not probe by default. |
| Complete approved live probe evidence exists | Prefer existing live probe evidence. Do not re-probe by default. |
| Complete approved source data plus fresh scoped live probe evidence exists | This may contribute to identity, population, target ownership, or action-readiness proof for that workflow. |
| Live probe evidence exists by itself | Treat as reachability/service-state evidence only. Do not promote it to identity or population proof. |
| No existing evidence exists | A bounded live probe may be staged if the scope is otherwise approved. |
| Partial match exists | Review before probe. Do not treat as complete reuse proof. |
| Ambiguous match exists | Review before probe. Do not treat as complete reuse proof. |
| Stale, conflicting, or wrong-scope evidence exists | Review before probe. |
| Five live probes already exist for the same target/scope | Block live probe unless override is recorded. |

## Harness contract

The canonical low-noise policy must expose:

- `live_probe_budget_policy.check_existing_evidence_before_probe`
- `live_probe_budget_policy.complete_match_required_for_reuse`
- `live_probe_budget_policy.partial_or_ambiguous_match_is_insufficient`
- `live_probe_budget_policy.prefer_existing_live_probe_evidence`
- `live_probe_budget_policy.max_live_probes_per_target_scope`
- `live_probe_budget_policy.override_requires_recorded_lead_or_operator_reason`
- `guidance.probe_evidence_role_guidance`

Tests must fail if a policy or workflow can blindly re-probe a known target without first checking evidence reuse and the live-probe budget.

Tests must also fail if policy wording treats live probe output as useless or impossible to use as proof. The intended distinction is narrow: live probe output is not proof by itself, but it may contribute to proof when joined with complete approved evidence.

## English reporting contract

Operator-facing reports should say why a probe did or did not happen, and whether live probe evidence is being reused as part of a complete proof package or only retained as reachability evidence.

Examples:

```text
Evidence reuse decision: reuse_existing_evidence.
```

```text
Evidence reuse decision: review_before_probe.
Reason: existing evidence is partial or ambiguous.
```

```text
Evidence reuse decision: block_live_probe.
Reason: live probe budget exhausted for this target/scope.
```

```text
Evidence role: live probe output contributes to action-readiness proof because approved source data is complete, fresh, scoped, and unambiguous.
```

## Agent guardrail

AI agents must check this guardrail before generating commands. A generated command that skips the evidence-reuse decision is not low-noise, even if it uses a narrow port list or a low retry count.

AI agents must not flatten the rule into either extreme. Live probe output is not authoritative by itself, and it is also not disposable. Its value depends on the approved evidence chain around it.
