# Pre-stage Bootstrap Safety Status

## Working

- Repository freshness already has a canonical preservation-first workflow: `harness/workflows/repository-freshness-before-launch.yaml`.
- Current `scripts/SasTargetNameResolution.psm1` assigns the empty suffix collection directly for already-canonical FQDN input, avoiding the Windows PowerShell 5.1 pipeline-unwrapping shape that can become `$null` under StrictMode.
- `Tests/Pester/TargetNameResolution.Tests.ps1` contains an executable regression for an already-canonical FQDN with zero suffix candidates under StrictMode.
- The scoped pre-stage harness now maps the relevant bootstrap surfaces, defines the workflow, registers artifacts, provides a validator and completeness check, wires local hooks, and has dedicated Linux/Windows CI.

## Repaired operational boundary

A failure before stage 1 is not automatically an S4U scheduled-task, transport, target-registry, or field-environment failure. The first owned question is whether the controller is executing current repository code.

A known stale-code failure shape is an already-canonical FQDN entering an older target resolver where an `if` expression emits `@()`, Windows PowerShell 5.1 unwraps the empty pipeline result to `$null`, and StrictMode later raises `The property 'Count' cannot be found on this object.` Current repository truth avoids that expression shape and tests it directly.

The harness therefore requires freshness reconciliation before anyone patches the wrong `.Count`, reconstructs an alternate deployment path, or reruns target mutation.

## Broken / blocked conditions

- A controller checkout behind the selected current ref is not certified to diagnose current product behavior.
- Fetching `origin/main` without moving or isolating the executing tree is still stale execution.
- If current-tree `TargetNameResolution.Tests.ps1` fails, product behavior is genuinely unproven and requires a separate product-code lane.
- This harness cannot produce live field proof from CI or an offline agent environment.

## Missing proof

The harness does not prove target contact, S4U task creation, registry mutation, cleanup, restart, automatic sign-in, or technician acceptance. A green current-tree regression only proves that the known pre-stage StrictMode FQDN defect is not present in the tested repository tree.

## Operator next gate

Before another field attempt from a controller that may be stale, select a current repository commit through the preservation-first freshness workflow, run the focused target-name-resolution regression on that executing tree, and only then return to `Run-AutoLogonCrashSafe.cmd HOST` under the normal deployment authorization gates.
