# Scoped Validation Skill

Use this skill whenever an AI-assisted change needs validation.

## Steps

1. Classify the touched files.
2. Prefer the smallest deterministic check that covers the change.
3. Do not run live probes or require network access for documentation/config-only changes.
4. For AI harness changes, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
```

5. If `pwsh` is unavailable, report that limitation clearly and do not claim the validator passed.

## Scope matrix

| Change type | Preferred validation |
|---|---|
| AI harness docs/config | `tools/validate-ai-layer.ps1` |
| Bash survey scripts | Relevant `tests/bash/` contract test plus static shell checks when available |
| PowerShell tooling | Existing Pester or targeted script validation requested by the user |
| .NET dashboard/managed code | `dotnet test` for the relevant solution/project |
| Docs only outside harness | Link check or targeted static review when available |

## Guardrails

- Keep validation scoped and bounded.
- Do not invent a pass result.
- Separate local smoke tests from network-feature validation.
- Preserve local evidence in ignored paths only.
