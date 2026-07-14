# Scoped Validation Skill

Use this skill whenever an AI-assisted change needs validation.

## Capability dependencies

- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Steps

1. Classify the touched files, integration boundaries, and claimed proof level.
2. Run the smallest deterministic targeted check, parser, unit test, or contract first for fast diagnosis.
3. For executable or integration-affecting changes, run the applicable E2E journey before treating validation as merge-ready.
4. Run broader regression checks after the E2E slice is recoverable.
5. Do not run live probes or require external network access for documentation/config-only changes.
6. For agent instruction, skill, capability, or AI harness changes, run:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
   ```
7. Run the targeted Python contracts when agent instructions, capability metadata, or E2E posture change:
   ```text
   python3 Tests/survey/test_agent_instruction_factoring_contracts.py
   python3 Tests/survey/test_agent_capability_manifest_contracts.py
   python3 Tests/survey/test_e2e_default_posture_contracts.py
   ```
8. Run the default fixture-safe E2E profile when shared harness or dashboard integration can be affected:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default
   ```
9. If E2E is not applicable, state why and name the strongest substitute proof. If a required runtime is unavailable, report the exact command and do not claim it passed.

## Scope matrix

| Change type | Preferred validation |
|---|---|
| Agent instructions, skills, capabilities | Factoring, manifest, and E2E-posture contracts plus `tools/validate-ai-layer.ps1` |
| Shared harness or dashboard integration | Targeted contracts, default fixture/loopback E2E, then broad regression |
| Bash survey scripts | Relevant `tests/bash/` contract plus a fixture/loopback E2E when an entrypoint exists |
| PowerShell tooling | Parser/Pester diagnostics plus the real wrapper or fixture E2E |
| .NET dashboard/managed code | Targeted `dotnet test` plus launcher/browser or service-boundary E2E |
| Docs only outside harness | Targeted links/contracts; E2E may be not applicable with reason |
| Live deployment/device behavior | Fixture E2E first, then separately approved live target/runtime proof |

## Guardrails

- Keep validation scoped and bounded.
- Unit-test count is not merge readiness.
- Do not invent a pass result or silently skip a required journey.
- Separate fixture E2E, loopback E2E, launcher proof, command ACK, observed behavior, and live runtime proof.
- Preserve generated evidence in ignored paths or CI artifacts only.
