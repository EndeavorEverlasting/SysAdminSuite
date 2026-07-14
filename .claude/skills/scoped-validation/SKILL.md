# Scoped Validation Skill

Use this skill whenever an AI-assisted change needs validation.

## Capability dependencies

- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Steps

1. Classify the touched files and claimed proof level.
2. Prefer the smallest deterministic check that covers the change.
3. Do not run live probes or require network access for documentation/config-only changes.
4. For agent instruction, skill, capability, or AI harness changes, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
```

5. Run the targeted Python contracts when agent instructions or capability metadata change:

```text
python Tests/survey/test_agent_instruction_factoring_contracts.py
python Tests/survey/test_agent_capability_manifest_contracts.py
```

6. If a required runtime is unavailable, report the exact skipped command and do not claim it passed.

## Scope matrix

| Change type | Preferred validation |
|---|---|
| Agent instructions, skills, capabilities | Factoring and capability-manifest contracts plus `tools/validate-ai-layer.ps1` |
| AI harness docs/config | `tools/validate-ai-layer.ps1` plus the relevant manifest contract |
| Bash survey scripts | Relevant `tests/bash/` contract plus static shell checks |
| PowerShell tooling | Existing Pester or targeted parser/contract validation |
| .NET dashboard/managed code | `dotnet test` for the relevant solution/project |
| Docs only outside harness | Targeted links/contracts or static review when available |

## Guardrails

- Keep validation scoped and bounded.
- Do not invent a pass result.
- Separate local smoke tests, command ACK, observed behavior, and live runtime proof.
- Preserve local evidence in ignored paths only.
