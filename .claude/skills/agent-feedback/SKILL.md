# Agent Feedback Skill

Use this skill for casting or reading agent/model feedback votes, displaying the active agent state, or understanding orchestrator routing decisions based on accumulated thumbs-down flags. Use ONLY when the task involves Invoke-SasAgentFeedback, Show-SasAgentFeedbackSummary, Show-SasActiveAgent, or agent feedback routing rules.

## Capability dependencies

- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)

## Authority

- `schemas/harness/agent-feedback-event.schema.json` — feedback vote schema.
- `scripts/Invoke-SasAgentFeedback.ps1` — cast a feedback vote; appends JSONL, regenerates summary, flags 2-consecutive or 3-of-5 thumbs_down.
- `scripts/Show-SasAgentFeedbackSummary.ps1` — display per-agent, per-model vote counts and flagged tuples.
- `scripts/Show-SasActiveAgent.ps1` — probe opencode/agy/goose managed wrappers, read GNHF fleet capability state, surface active model/provider/tier/free-token status.
- `docs/AGENT_FEEDBACK_AND_ROUTING.md` — feedback contract, vote values, evidence paths, orchestrator routing rules.

## Routing rules

| Condition | Action |
|---|---|
| 2 consecutive `thumbs_down` on an agent+model tuple | Orchestrator SHOULD avoid that tuple until cleared |
| 3 of last 5 `thumbs_down` | Orchestrator SHOULD avoid that tuple until cleared |
| GNHF hides model info | AgentSwitchboard MUST surface visible provider/tier/free-token status from `Show-SasActiveAgent.ps1` |
| Fallback chain match | Select first provider in fallback order with available model |

## Validators

- `Tests/survey/test_ai_provider_catalog_contracts.py` — feedback schema, script, and visibility contracts.
- `Tests/survey/test_agent_capability_manifest_contracts.py` — manifest integrity and discoverability.
