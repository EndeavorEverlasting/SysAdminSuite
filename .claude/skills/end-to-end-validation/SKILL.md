# End-to-End Validation Skill

Use this project-level skill for integration gates, composed workflow proof, browser or launcher journeys, deployment proof planning, runtime proof planning, or merge/release validation of executable changes.

## Capability dependencies

- [End-to-End Testing](../../capabilities/end-to-end-testing.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Default proof posture

- End-to-end proof is the default merge and release target for executable or integration-affecting changes.
- Unit tests, parser checks, and narrow contracts are fast diagnostics; they are not substitutes for a required closed-loop journey.
- A checkpoint, green unit test, green static contract, launcher start, or command acknowledgment is not automatically merge readiness or runtime proof.
- Mark E2E `not_applicable` only when the change cannot affect an executable or integration boundary, and record the reason and remaining proof ceiling.

## Workflow

1. Identify the real user or operator entrypoint and the final artifact, state transition, or classification.
2. Classify the safest applicable E2E class: synthetic-offline, loopback-only, approved control-plane, approved target read, or approved target mutation.
3. Run parser, unit, or narrow contract checks first for fast diagnosis.
4. Run the applicable E2E journey through the real repo-owned entrypoint, composition boundary, artifact/result path, and final classification.
5. Run the fixture-safe default profile when the change touches shared harness or dashboard integration:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default
   ```
6. After any software-install execution or recovered run, invoke the post-install result inspector:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Show-SasSoftwareInstallResult.ps1
   ```
   Present the classification and target table. Give technicians `Inspect-LatestSoftwareInstall.cmd`; do not present installer completion as application acceptance.
7. Run broader regression checks only after the targeted diagnostics and required E2E slice are recoverable.
8. Run live target or mutation proof only when explicitly authorized and when teardown/evidence boundaries are satisfied.
9. Report journey IDs, result artifacts, exact passes and failures, proof class, skipped commands, and every unrun higher gate.

## Completion gate

Do not claim merge or release readiness until the applicable E2E journey has passed, its result artifacts are inspectable, and the proof class matches the claim. When a required journey cannot run, report the exact missing dependency or authorization gate instead of silently substituting unit or static checks.

## Guardrails

- Do not mock away the boundary the journey claims to prove.
- Do not treat unit-test count as merge readiness.
- Do not silently skip a required journey because a dependency is missing.
- Do not contact non-loopback targets from the default profile.
- Do not infer live runtime proof from synthetic or loopback success.
