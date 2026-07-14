# End-to-End Testing Posture

## Default posture

End-to-end validation is the default merge and release proof target for executable or integration-affecting changes in SysAdminSuite.

Unit, parser, contract, and component tests remain required where they provide fast diagnosis. They do not, by themselves, prove that the repository entrypoint, composed dependencies, artifact path, and final classification work together.

A change may be marked E2E not applicable only when it cannot affect an executable or integration boundary. The PR must state the reason and name the strongest available substitute proof.

## Validation order

Use this order unless a task-specific contract requires a stricter sequence:

1. parser, unit, or narrow contract checks for fast feedback;
2. fixture, synthetic, or loopback end-to-end journey through the real entrypoint;
3. broader regression suites;
4. controlled live end-to-end proof when the feature touches authorized targets, devices, deployment, or user-visible runtime behavior.

A lower stage helps diagnose failure. It does not replace a required higher stage.

## What counts as end-to-end

An E2E journey must cross a meaningful system boundary and prove a closed loop:

```text
repo-owned entrypoint
  -> real composition or process boundary
  -> real artifact/result path
  -> final machine-readable classification
```

Valid fixture-safe examples include:

- the one-command harness creating run context, artifact registry entries, reports, and a final validation result;
- the software-install operator wrapper launching a real fixture installer process, producing installed package state, structured logs, before/after snapshots, and an added/changed/removed delta;
- the dashboard relay starting as a real subprocess, authenticating over a real loopback WebSocket, receiving a probe request, and returning cancellation or abort behavior;
- a deployment fixture creating and consuming the same manifest and summary shapes used by the operator lane without contacting a target.

A test that only imports one function, mocks every dependency, greps source text, or asserts a launcher exists is not E2E proof.

## Safety classes

| Class | Allowed by default | Proof ceiling |
|---|---|---|
| `synthetic-offline` | Yes | Fixture E2E |
| `loopback-only` | Yes | Loopback E2E |
| `approved-control-plane` | Only when the task authorizes it | Control-plane E2E |
| `approved-target-read` | Separate target gate required | Observed target E2E |
| `approved-target-mutation` | Separate mutation and teardown gates required | Live runtime E2E |

The default CI profile must not contact corporate targets, public targets, package shares, workstations, printers, or devices. It must not mutate target state.

## Merge and release gate

For executable or integration-affecting changes, merge readiness requires:

- targeted checks pass;
- at least one applicable E2E journey passes;
- broader checks pass or every failure is proven unrelated;
- generated E2E evidence remains in ignored paths or CI artifacts;
- the PR reports which E2E class ran and whether live target proof remains.

Unit tests alone are insufficient unless E2E is explicitly not applicable and that decision is supported by repository evidence.

## Repository implementation

The default fixture-safe profile is declared in:

```text
harness/e2e/e2e-profiles.json
```

Run it with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default
```

The runner emits:

```text
e2e_validation_matrix.txt
e2e_validation_result.json
<journey-id>.log
```

The default profile composes existing real journeys rather than replacing them:

- one-command synthetic harness proof;
- software installation against an isolated fixture target with before/after delta and structured evidence;
- dashboard relay cancellation over loopback;
- dashboard relay process-abort handling over loopback.

The software-install journey is documented in `docs/SOFTWARE_INSTALL_E2E.md`.

## Proof language

Report these separately:

- targeted/unit proof;
- fixture or synthetic E2E proof;
- loopback E2E proof;
- launcher/browser proof;
- command ACK proof;
- behavior observed proof;
- live target/runtime proof;
- operator acceptance proof.

Never promote fixture or loopback E2E to live target proof.
