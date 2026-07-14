# End-to-End Testing Capability

## Contract

Use end-to-end validation as the default merge and release proof target for executable or integration-affecting changes. Keep unit and contract tests as fast diagnostic layers, not substitutes for a required closed-loop journey.

## Invariants

- Run the smallest targeted check first so failures are cheap to diagnose.
- Then run at least one applicable journey through the real repo-owned entrypoint, composition boundary, artifact/result path, and final classification.
- Prefer synthetic, fixture, or loopback E2E before broad suites when it can exercise the real integration safely.
- Mark E2E `not_applicable` only for changes that cannot affect an executable or integration boundary, and record the reason.
- Missing required E2E dependencies fail the gate; they are not silent skips.
- Keep external target, device, deployment, and mutation journeys behind their explicit authorization and teardown gates.
- Keep generated logs and results in ignored local paths or CI artifacts.
- Never describe fixture or loopback E2E as live target proof.

## Default runner

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default
```

The profile authority is `harness/e2e/e2e-profiles.json`. The doctrine authority is `docs/END_TO_END_TESTING_POSTURE.md`.

## Used by

- `.claude/skills/end-to-end-validation/SKILL.md`
- `.claude/skills/scoped-validation/SKILL.md`
