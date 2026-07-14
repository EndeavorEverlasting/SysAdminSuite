# End-to-End Validation Skill

Use this skill for integration gates, composed workflow proof, browser or launcher journeys, deployment proof planning, runtime proof planning, or merge/release validation of executable changes.

## Capability dependencies

- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Workflow

1. Identify the real user or operator entrypoint and the final artifact or classification.
2. Classify the safest applicable E2E class: synthetic-offline, loopback-only, approved control-plane, approved target read, or approved target mutation.
3. Run parser, unit, or narrow contract checks first for fast diagnosis.
4. Run the fixture-safe default profile when the change touches shared harness or dashboard integration:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default
   ```
5. After any software-install execution or recovered run, invoke:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Show-SasSoftwareInstallResult.ps1
   ```
   Present the classification and target table. Give technicians `Inspect-LatestSoftwareInstall.cmd`; do not present installer completion as application acceptance.
6. Run broader regression checks after the E2E slice is recoverable.
7. Run live target or mutation proof only when explicitly authorized and when teardown/evidence boundaries are satisfied.
8. Report the journey IDs, result artifacts, proof class, and every unrun higher gate.

## Guardrails

- Do not mock away the boundary the journey claims to prove.
- Do not treat unit-test count as merge readiness.
- Do not silently skip a required journey because a dependency is missing.
- Do not contact non-loopback targets from the default profile.
- Do not infer live runtime proof from synthetic or loopback success.
