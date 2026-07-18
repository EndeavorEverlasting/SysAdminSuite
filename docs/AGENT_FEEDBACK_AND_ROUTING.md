# Agent Feedback and Orchestrator Routing

## Purpose

When an agent or model produces a contribution that has to be undone, modified, or mutated, that feedback must be captured so the orchestrator can route around the problematic agent or model on future work.

## Feedback Contract

1. **Every agent contribution may receive a vote** after review.
2. **Votes are local evidence** written as JSONL events under `survey/output/agent_feedback/`.
3. **Thumbs-down votes require a reason.** A thumbs-down without a reason is rejected.
4. **The orchestrator reads accumulated feedback** before selecting an agent or model for a task.
5. **Feedback is never automatically shared.** It stays on the local admin box.

## Vote Values

| Vote | Meaning | Effect |
|------|---------|--------|
| `thumbs_up` | Contribution was acceptable | No routing change |
| `thumbs_down` | Contribution had to be undone or modified | Triggers orchestrator review; may demote agent or model |
| `neutral` | Contribution was acceptable but unremarkable | No routing change; used for statistical tracking |

## Evidence Path

```
survey/output/agent_feedback/
  feedback_events.jsonl    # Append-only JSONL, one event per line
  feedback_summary.json    # Aggregated counts per agent, model, provider
```

Both paths are gitignored. The summary is regenerated from the events on read.

## Schema

Each event follows `schemas/harness/agent-feedback-event.schema.json`.

## Orchestrator Routing

The orchestrator reads `feedback_summary.json` before routing a task:

1. **Count thumbs-down per (agent, model, provider) tuple.**
2. **If thumbs-down rate exceeds threshold** (default: 2 consecutive or 3 of last 5), the tuple is flagged.
3. **Flagged tuples are avoided** in future routing unless no alternative agent or model exists.
4. **When avoided, the fallback chain** from `Config/ai-provider-catalog.json` determines the next-best provider, tier, and model.

The threshold is defined in the provider catalog:

```json
"catalog_policy": {
  "agent_feedback_tracking_enabled": true,
  "feedback_gates_orchestrator_routing": true
}
```

## Operator Workflow

```text
1. Agent produces a contribution (code, config, report, etc.)
2. Operator reviews the contribution
3. If acceptable:  cast thumbs_up or neutral
4. If unacceptable: cast thumbs_down with the reason
5. Orchestrator reads feedback before the next task
6. If agent/model is flagged, orchestrator selects the fallback
```

To cast a vote:

```powershell
# Append a feedback event
.\scripts\Invoke-SasAgentFeedback.ps1 -AgentId opencode -ModelId gpt-4o-mini -ProviderId github-models -Vote thumbs_down -Reason "Generated invalid config that required manual revert" -WorkContext "Workstation profile generation"

# Read the current feedback summary
.\scripts\Show-SasAgentFeedbackSummary.ps1
```
