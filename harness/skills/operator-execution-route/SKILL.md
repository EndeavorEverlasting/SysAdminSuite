# Operator Execution Route

## Trigger

Load this skill after a canonical command has been selected when the command is repository/runtime-relative, a crash-safe front door exists, the operator's current directory is unknown, or AutoLogon `autologon-remote` is selected.

Before this skill emits, executes, or asks an operator to run the resolved command, load `harness/skills/operator-command-handoff/SKILL.md`. Execution-route resolution is one component of the required **path -> freshness -> network intent -> command -> restoration** transaction; it is not permission to hand out a bare product command.

## Required inputs

- canonical `command_id`;
- requested goal;
- explicit target when required;
- whether the current environment can execute on the operator workstation;
- current repository/network authorization context;
- selected refreshed repository commit and production/runtime currentness proof when the route executes outside the canonical development checkout.

## Procedure

1. Read `harness/api/operator-execution-route-registry.json` and `harness/workflows/operator-execution-route.yaml`.
2. Resolve exactly one route and prove its repository freshness dependency is tracked.
3. Do **not** assume the current directory or assume every valid runtime is a full repository.
4. Validate the explicit target against `target_validation_pattern`, encode it according to `target_encoding`, and never interpolate raw target text into PowerShell source.
5. For `autologon-remote`, prove the canonical development/repository floor first. On Guest/Internet, use the existing `sas refresh` / `scripts/Refresh-SasOperatorCommand.ps1` path to derive the field-ready checkout and seal the protected runtime from the selected refreshed commit before switching to protected execution.
6. If installed `sas` exists on the protected side, use the sealed-runtime state/manifest path rather than Git: `scripts/SasPortableLauncher.ps1` resolves `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json`, requires the v2 staging contract and SHA-256 tracked-file seal, and yields a prepared runtime such as `C:\SASAL`. Require its `prepared_commit` to equal the selected refreshed repository commit for this operation. A valid older sealed commit is not currentness proof.
7. Require `Bootstrap-SysAdminSuiteAutoLogon.cmd` beneath that sealed runtime and invoke it with the validated target and prepared commit. Do not delegate the target-mutating route to an arbitrary stale dispatcher and do not run remote Git inside `C:\SASAL`.
8. The sealed bootstrap must verify its local staging manifest and enter `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`, which owns the registered transcript/result/latest-pointer evidence.
9. If installed `sas`/sealed runtime is unavailable, resolve the bounded full-repository fallback from `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`, prove every `required_files` dependency and canonical currentness requirement, and invoke `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` through `powershell.exe -File`.
10. Preserve the child exit code and outer operator PowerShell on failure.
11. Before operator execution/handoff, compose this selected route through `harness/skills/operator-command-handoff/SKILL.md`: canonical development path plus starting-network capture first, InternetSync repository freshness and return second, product network intent third, this canonical front door fourth, and required network restoration fifth.
12. If this environment cannot execute on the operator workstation, emit **one copy-paste command** (atomic as one PowerShell block) that advances the first unproven field gate and contains prerequisite path/freshness/runtime-currentness routing rather than assuming it ran earlier. Network transition/restoration remains delegated to repository-owned network/session authorities, not reimplemented in the snippet.

## AutoLogon rule

The durable crash-safe authority remains:

`Run-AutoLogonCrashSafe.cmd HOST`

The canonical product command remains:

`sas autologon Remote HOST`

The installed universal command is implemented by `scripts/Invoke-SasUniversalField.ps1`. Current product code routes AutoLogon **Remote** into `Bootstrap-SysAdminSuiteAutoLogon.cmd`; **Recover** remains recovery-only through the on-site recovery launcher. The protected route is stricter still: it consumes the sealed runtime whose manifest was produced by `sas refresh`, proves `prepared_commit` against the selected refreshed repository commit, and calls `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly. This prevents both a stale installed dispatcher and remote Git on the protected network from bypassing crash-safe evidence.

For network-sensitive execution, the route must preserve `scripts/Invoke-SasNetworkAwareField.ps1` / `SasNetworkIntent.psm1` authority. Capture the starting network before the freshness transition. Repository refresh is an `InternetSync` subtransaction; product AutoLogon is a later `ProtectedNorthwell` transition. Do not issue ad-hoc Wi-Fi/VPN switch commands around either phase. If the repository-owned network transaction changes WLANs, its `finally` restoration and restore result are part of command success.

## Failure handling

- `C:\SASAL` exists but its manifest/seal is missing, malformed, or prepared for a different selected commit: return to Guest/Internet and run the repository-owned refresh/seal path; do not use Git inside the sealed runtime.
- sealed runtime lacks `Bootstrap-SysAdminSuiteAutoLogon.cmd`: fail at that boundary; do not fall through to a weaker dispatcher.
- installed `sas` absent: use the proven full-repository helper fallback only when its canonical freshness dependencies are satisfied.
- invalid target/encoding: fail before either execution path.
- dirty or separately owned checkout: preserve it; do not reset/clean.
- repository freshness is unproven: stop before product command handoff.
- required sealed/runtime currentness is unproven: stop before protected product execution.
- required network intent is unproven: stop before target-capable product execution.
- required network restoration fails: do not promote the child command to success.
- failure after target mutation: classify the registered crash-safe evidence before any rerun.

## Expected outputs

- selected route id;
- selected execution adapter (`sealed crash-safe bootstrap` or full-repository fallback);
- canonical development root plus resolved runtime/repository root when known;
- selected refreshed repository commit;
- sealed `prepared_commit` and seal/currentness disposition when applicable;
- repository freshness disposition;
- starting and required network posture plus freshness-return/product-transition/final-restore disposition when applicable;
- executed/not-executed disposition;
- propagated exit code;
- durable result/latest-pointer path;
- one exact next action only when an unproven gate remains.

## Proof ceiling

This skill proves routing, safe target transport, sealed-runtime crash-safe delegation/currentness contract or fallback dependency proof, and exit disposition. It is not standalone handoff authority: a complete operator handoff also requires the composed canonical-path, repository-freshness, network-intent, and restoration gates. Repository proof does not itself establish live target mutation, deployment, reboot, automatic sign-in, or runtime acceptance; those require the registered field artifacts.
