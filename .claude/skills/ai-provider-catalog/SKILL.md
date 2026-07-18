# AI Provider Catalog Skill

Use this skill for AI provider model routing, free-token-priority fallback chains, agent feedback voting, or agent visibility. Use ONLY when the task touches model selection, orchestration routing around flagged agents, or technician workstation agent/model display.

## Capability dependencies

- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)

## Authority

- `Config/ai-provider-catalog.json` — provider catalog with tier, models, free-token flags, and fallback ordering.
- `schemas/harness/ai-provider-catalog.schema.json` — fail-closed provider catalog schema.
- `docs/AGENT_FEEDBACK_AND_ROUTING.md` — feedback contract, vote values, evidence paths, orchestrator routing rules.
- `docs/TECHNICIAN_WORKSTATION_QUICKSTART.md` — one-command technician setup for agents, models, and feedback.

## Fallback chain

The provider fallback chain prefers free tokens before paid billing:

```
free_local → free_cloud_free_tokens → free_cloud_trial → paid
```

The orchestrator MUST select the first matched provider in fallback order that has an available model.

## Agent feedback routing

- Every `thumbs_down` vote requires a reason.
- 2 consecutive `thumbs_down` OR 3 of last 5 `thumbs_down` flags the agent+model tuple for orchestrator avoidance.
- Use `scripts/Invoke-SasAgentFeedback.ps1` to cast votes.
- Use `scripts/Show-SasAgentFeedbackSummary.ps1` to read accumulated feedback.
- Use `scripts/Show-SasActiveAgent.ps1` to display the active agent, model, provider, tier, and free-token status.

## Validators

- `Tests/survey/test_ai_provider_catalog_contracts.py` — 16 provider catalog and feedback contracts.
- `Tests/survey/test_agent_capability_manifest_contracts.py` — manifest integrity and discoverability.
