# Operator Execution Route

## Trigger

Load this skill after a canonical command has been selected when the command is repository/runtime-relative, a crash-safe front door exists, the operator's current directory is unknown, or AutoLogon `autologon-remote` is selected.

Before this skill emits, executes, or asks an operator to run the resolved command, load `harness/skills/operator-command-handoff/SKILL.md`. Execution-route resolution is one component of the normal **path -> freshness -> network intent -> command -> restoration** transaction, with one bounded exception for an already-protected AutoLogon window whose provider-fresh accepted floor and sealed runtime are both proven.

## Required inputs

- canonical `command_id`;
- requested goal;
- explicit target when required;
- whether the current environment can execute on the operator workstation;
- current repository/network authorization context;
- refreshed provider/default-branch identity;
- selected accepted immutable deployment floor/capability and ancestry/revocation proof;
- selected refreshed repository commit when repository maintenance is required;
- production/runtime currentness proof when the route executes outside the canonical development checkout.

## Procedure

1. Read `harness/api/operator-execution-route-registry.json` and `harness/workflows/operator-execution-route.yaml`.
2. Resolve exactly one route and prove its repository/runtime freshness dependency is tracked.
3. Do **not** assume the current directory or assume every valid runtime is a full repository.
4. Validate the explicit target against `target_validation_pattern`, encode it according to `target_encoding`, and never interpolate raw target text into PowerShell source.
5. For `autologon-remote`, refresh provider/default-branch truth before handoff. If preserving an already-protected window, select an explicit immutable deployment floor from that refreshed truth and prove the floor is an ancestor of the refreshed default head, contains every currently required lane safety/capability fix, and is not revoked by a current contract.
6. Classify the starting network before choosing a workstation freshness action. If the operator is already on **PROTECTED NORTHWELL** through approved hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN, attempt the protected-window fast path first.
7. Protected-window fast path: use only locally sealed authority. Require the v2 AutoLogon manifest, exact prepared commit, `LOCAL_FILESYSTEM_ONLY` transport, removed remotes, complete SHA-256 tracked-file seal, protected bootstrap, and exact equality between `prepared_commit` and the provider-selected accepted immutable deployment floor. For continuity compatibility, a sealed `Run-AutoLogon-ContiguousProgress.cmd` plus `scripts\SasAutoLogonProgress.psm1` proves the already-merged presentation capability on runtimes prepared before continuity moved into the common crash-safe runner.
8. When the fast path is admitted, execute the sealed crash-safe route immediately from the current protected posture. Do not run workstation remote Git, do not invoke `sas refresh`, do not switch WLAN, and do not disconnect/reconnect VPN merely to replace an accepted immutable floor with the latest head.
9. If protected-window local proof is insufficient, fail quickly and preserve the current network. State the exact missing runtime/floor proof and the later Guest/Internet refresh action; do not perform that refresh while the protected window is intentionally being preserved.
10. When the fast path is not applicable and the operator is on Guest/Internet, use the existing `sas refresh` / `scripts/Refresh-SasOperatorCommand.ps1` path to derive the field-ready checkout and seal the protected runtime from the selected refreshed commit before protected execution.
11. If installed `sas` exists on the protected side, use the sealed-runtime state/manifest path rather than Git: `scripts/SasPortableLauncher.ps1` resolves `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json`, requires the v2 staging contract and SHA-256 tracked-file seal, and yields a prepared runtime such as `C:\SASAL`.
12. Require `Bootstrap-SysAdminSuiteAutoLogon.cmd` beneath that sealed runtime and invoke it with the validated target and prepared commit. Do not delegate the target-mutating route to an arbitrary stale dispatcher and do not run remote Git inside `C:\SASAL`.
13. The sealed bootstrap must verify its local staging manifest and enter `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`, which owns the registered transcript/result/latest-pointer evidence and contiguous operator-progress presentation.
14. If installed `sas`/sealed runtime is unavailable outside a protected-window fast path, resolve the bounded full-repository fallback from `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`, prove every `required_files` dependency and canonical currentness requirement, and invoke `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` through `powershell.exe -File`.
15. Preserve the child exit code and outer operator PowerShell on failure.
16. Before standard repository-backed execution/handoff, compose the selected route through `harness/skills/operator-command-handoff/SKILL.md`: canonical development path plus starting-network capture first, InternetSync repository freshness and return second, product network intent third, this canonical front door fourth, and required network restoration fifth.
17. If this environment cannot execute on the operator workstation, emit **one copy-paste command** that advances the first unproven field gate. When already protected, provider freshness/floor selection must already be complete and the command must try only the local exact-floor protected-window path; it must not contain a repository refresh or network transition.

## AutoLogon rule

The durable crash-safe authority remains:

`Run-AutoLogonCrashSafe.cmd HOST`

The canonical product command remains:

`sas autologon Remote HOST`

The installed universal command is implemented by `scripts/Invoke-SasUniversalField.ps1`. Current product code admits approved hardwire, WAB, and authenticated DomainAuthenticated VPN through the protected-network authority, then routes AutoLogon **Remote** into `Bootstrap-SysAdminSuiteAutoLogon.cmd`; **Recover** remains recovery-only through the on-site recovery launcher.

The user-scoped portable dispatcher intentionally checks the sealed AutoLogon Remote/Recover lane before general repository discovery. This is the runtime behavior the protected-window fast path relies on: once provider freshness has accepted the exact sealed floor, the workstation does not need to locate a mutable checkout or perform Git merely because the operator is already protected.

`Invoke-SasAutoLogonCrashSafeFieldRun.ps1` is the shared post-bootstrap execution seam for both installed routes. It owns stable local evidence and contiguous numbered progress. If the underlying engine advances past an unentered stage, the operator sees an explicit `SKIP` before the later stage rather than a visible numbering jump.

For network-sensitive standard execution, preserve `scripts/Invoke-SasNetworkAwareField.ps1` / `SasNetworkIntent.psm1` authority. Repository refresh is an `InternetSync` subtransaction and product AutoLogon is `ProtectedNorthwell`. The protected-window fast path is different: provider freshness is already complete, the sealed immutable floor is accepted, and the starting protected posture already satisfies product intent, so no workstation freshness/network transition occurs and there is nothing for SysAdminSuite to restore.

## Failure handling

- refreshed provider truth cannot prove the selected immutable floor is an ancestor, safety/capability-complete, and unrevoked: do not issue the protected-window fast path.
- `C:\SASAL` exists but its manifest/seal/exact accepted floor/capability is missing or malformed during an already-protected window: fail there, preserve the protected network, and report the later Guest/Internet `sas refresh` action; do not leave the window automatically.
- sealed runtime lacks `Bootstrap-SysAdminSuiteAutoLogon.cmd`: fail at that boundary; do not fall through to a weaker dispatcher.
- continuity is required but neither the common crash-safe continuity integration nor the sealed compatibility wrapper/module is present: fail before deployment rather than reintroducing a visible numbered-stage gap.
- installed `sas` absent: use the proven full-repository helper fallback only when not preserving a protected window and its canonical freshness dependencies are satisfied.
- invalid target/encoding: fail before either execution path.
- dirty or separately owned checkout: preserve it; do not reset/clean.
- repository freshness is unproven for a repository-backed route: stop before product command handoff.
- required sealed/runtime currentness is unproven: stop before protected product execution.
- required network intent is unproven: stop before target-capable product execution.
- required network restoration fails after a workflow actually changed network state: do not promote the child command to success.
- failure after target mutation: classify the registered crash-safe evidence before any rerun.

## Expected outputs

- selected route id;
- selected execution adapter (`sealed protected-window crash-safe route` or standard repository-backed route);
- canonical development root only when repository maintenance is required;
- refreshed provider/default-branch identity;
- selected accepted immutable deployment floor/capability plus ancestry/revocation disposition;
- selected refreshed repository commit when applicable;
- sealed `prepared_commit` and exact-floor/seal disposition;
- workstation repository freshness disposition (`not required: provider-fresh accepted sealed floor` is valid when proven);
- starting and required network posture plus transition/restore disposition;
- executed/not-executed disposition;
- propagated exit code;
- durable result/latest-pointer path;
- one exact next action only when an unproven gate remains.

## Proof ceiling

This skill proves routing, safe target transport, provider-fresh accepted-floor selection, sealed-runtime crash-safe delegation/currentness contract or fallback dependency proof, and exit disposition. Repository/static/CI validation cannot establish a live workstation's VPN/hardwire/WAB state, sealed runtime bytes, protected target access, target mutation, reboot, automatic sign-in, or runtime acceptance; those require field evidence.
