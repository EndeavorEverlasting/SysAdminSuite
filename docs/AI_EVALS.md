# Repository-wide AI behavior evaluations

SysAdminSuite treats AI behavior as a versioned product surface. Ordinary unit tests still validate code; this layer evaluates **agent decisions, grounding, remediation, tool use, emitted handoff evidence, and proof boundaries**.

## Canonical entrypoint

```text
python tools/run-agent-behavior-evals.py --manifest harness/evals/agent-behavior-eval-manifest.v1.json --responses <response-set.json> --report <result.json>
```

The harness-owned workflow is `harness/workflows/agent-behavior-evals.yaml`, and the blocking framework validator is `harness/validators/validate-agent-behavior-evals.py`.

The response adapter is provider-agnostic. A local agent, external agent framework, recorded trace, or future model runner only needs to emit `sas-agent-behavior-response-set/v1`; the repository scorer remains deterministic. Cases that must validate an actual emitted command or handoff may include `output_text` in the response and pair it with repository-owned `required_output_patterns` / `forbidden_output_patterns`. Those patterns inspect the candidate's emitted evidence instead of trusting self-reported action labels.

## Eval pyramid

1. **Deterministic** — exact IDs, schema types, tool names/parameters, required and forbidden actions, authorization, emitted-text patterns, and repository contracts.
2. **Synthetic integration** — sanitized multi-seam cases that combine context, tool output, and decision state.
3. **Model judge** — only after exact oracles are exhausted. The versioned rubric is `harness/evals/judges/repository-quality-rubric.v1.json`.
4. **Human review** — only for irreducible operator judgment or real-world acceptance.

Model tokens are deliberately not spent checking facts the repository can check exactly.

## Hallucination diagnosis pair

The core suite contains two paired grounding cases:

- **truth absent**: classify `missing_context` and perform targeted retrieval of the exact owner;
- **truth present but ignored**: classify `present_context_ignored`, re-anchor/compact existing context, and do **not** fetch redundant context.

The scorer checks the diagnosis and the remediation. A superficially correct final answer is not enough.

## Current regression classes

The suite covers CMD-first field guidance, exact harness operation IDs/tool parameters, malformed tool results, repository freshness before operator commands, timeout/recovery behavior, Boolean schema truthiness, profile/identity proof separation, instruction conflicts, missing authorization, paired grounding failures, environment-derived canonical-path handoffs, containment-based reconciliation after a benign default-branch advance, and PowerShell preflight abort semantics. These cases are sanitized from repository regression history; live hostnames, credentials, private runtime evidence, and named-user checkout paths are forbidden.

For path-sensitive operator handoffs, a passing response must show the relevant evidence when the oracle requires it. Declaring an action such as `resolve_desktop_known_folder` or `verify_required_sha_is_ancestor` is not sufficient if the emitted handoff still hard-codes `C:\Users\...`, pins an earlier default-branch HEAD by equality, omits clean/behind-only proof, or lets a dependent command run after a failed preflight.

## Success, acceptable degradation, and failure

**Success** means every deterministic criterion passes, aggregate deterministic correctness is `1.0`, and there are zero critical failures.

**Acceptable degradation** is deliberately narrow: style may remain unscored, and judge or human layers may remain not applicable when deterministic evidence fully decides a case. Acceptable degradation never lowers deterministic correctness, waives a critical failure, or converts missing grounding into a pass.

**Failure** is any failed deterministic criterion, any critical failure, duplicate or unknown response case, baseline/reference polarity inversion, or threshold relaxation without an approved evidence record.

## Reproducible scoring

`harness/evals/agent-behavior-eval-manifest.v1.json` pins:

- case-set version;
- known-failure baseline;
- reference candidate;
- scorer;
- judge rubric;
- thresholds;
- report artifact names;
- the threshold approval ledger.

Correctness is scored per criterion and per case. Style is a separate field and does not rescue an incorrect result. Reports retain the case ID, failure class, expected/actual value, false-positive risk, and false-negative risk.

The normal gate is intentionally strict: deterministic correctness must be `1.0` and critical failures must be zero.

A weaker threshold is not authorized by editing those numbers alone. `harness/evals/approved-threshold-changes.v1.json` is the approved threshold-change ledger. A relaxation must have a matching record with the exact from/to thresholds, explicit approval, approver role, timestamp, rationale, and non-empty evidence references. The scorer rejects a relaxed threshold when that record is absent or malformed. Cases are never weakened merely to make a candidate pass.

## Baseline and candidate

The baseline fixture encodes known bad behaviors and **must fail**. The reference candidate encodes the current desired behavior and **must pass**. CI runs both. This proves the evaluator can detect the regression classes instead of only proving that its happy path succeeds.

For a real candidate, replace only the response-set input. Do not edit the case oracle to accommodate the candidate.

## Adding a case

Add a sanitized case when a failure is observed in an issue, PR, trace, support note, field incident, or review. Prefer exact deterministic criteria. Record both false-positive and false-negative risks. When the defect is visible in the generated handoff itself, use `output_text` plus narrowly scoped required/forbidden regex patterns rather than relying only on declared actions. If a judge is genuinely necessary, set `oracle_mode=judge`, pin the rubric version and threshold, and preserve the judge result beside the candidate response. Human review is the last layer, not the default.

## Proof boundary

A passing repository eval proves the checked decision contract for the supplied response set. It does not by itself prove a physical CMD launcher works on a technician workstation, that an external model/provider will emit the reference response, that a protected target was reached, or that an operator accepted the result. Those remain workflow-specific executable or field gates.
