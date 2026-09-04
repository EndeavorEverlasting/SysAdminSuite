# Operator Execution Route

## Trigger

Load this skill after a canonical command has been selected when the command is repository/runtime-relative, a crash-safe front door exists, the operator's current directory is unknown, or AutoLogon `autologon-remote` is selected.

Before this skill emits, executes, or asks an operator to run the resolved command, load `harness/skills/operator-command-handoff/SKILL.md`. Execution-route resolution is one component of the required **path -> freshness -> network intent -> command -> restoration** transaction; it is not permission to hand out a bare product command.

## Required inputs

- canonical `command_id`;
- requested goal;
- explicit target when required;
- whether the current environment can execute on the operator workstation;
- current repository/network authorization context.

## Procedure

1. Read `harness/api/operator-execution-route-registry.json` and `harness/workflows/operator-execution-route.yaml`.
2. Resolve exactly one route and prove its repository freshness dependency is tracked.
3. Do **not** assume the current directory or assume every valid runtime is a full repository.
4. Validate the explicit target against `target_validation_pattern`, encode it according to `target_encoding`, and never interpolate raw target text into PowerShell source.
5. For `autologon-remote`, if installed `sas` exists, use `sas repo` only to locate the sealed runtime. A valid result may be `C:\SASAL` and may intentionally omit the full `harness\` tree.
6. Require `Bootstrap-SysAdminSuiteAutoLogon.cmd` beneath that sealed runtime and invoke it with the validated target. Do not delegate the target-mutating route to an arbitrary installed `sas autologon Remote` dispatcher.
7. The sealed bootstrap must verify its local staging manifest and enter `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`, which owns the registered transcript/result/latest-pointer evidence.
8. If installed `sas` is unavailable, resolve the bounded full-repository fallback from `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`, prove every `required_files` dependency, and invoke `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` through `powershell.exe -File`.
9. Preserve the child exit code and outer operator PowerShell on failure.
10. Before operator execution/handoff, compose this selected route through `harness/skills/operator-command-handoff/SKILL.md`: canonical path first, current repository proof second, starting network and command intent third, this canonical front door fourth, and required network restoration fifth.
11. If this environment cannot execute on the operator workstation, emit one atomic copy-paste command that advances the first unproven field gate **and contains the prerequisite path/freshness routing rather than assuming it was run earlier**. Network transition/restoration remains delegated to the repository-owned network-aware front door, not reimplemented in the snippet.

## AutoLogon rule

The durable crash-safe authority remains:

`Run-AutoLogonCrashSafe.cmd HOST`

The canonical product command remains:

`sas autologon Remote HOST`

The installed universal command is implemented by `scripts/Invoke-SasUniversalField.ps1`. Current product code routes AutoLogon **Remote** into `Bootstrap-SysAdminSuiteAutoLogon.cmd`; **Recover** remains recovery-only through the on-site recovery launcher. The operator execution route is stricter still: it resolves the sealed runtime with `sas repo` and calls `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly, so a stale installed dispatcher cannot bypass crash-safe evidence.

For network-sensitive execution, the route must preserve `scripts/Invoke-SasNetworkAwareField.ps1` / `SasNetworkIntent.psm1` authority. Do not issue ad-hoc Wi-Fi/VPN switch commands around AutoLogon or another protected operation. If the repository-owned network transaction changes WLANs, its `finally` restoration and restore result are part of command success.

## Failure handling

- `sas repo` resolves `C:\SASAL`: expected; do not require a harness registry there.
- sealed runtime lacks `Bootstrap-SysAdminSuiteAutoLogon.cmd`: fail at that boundary; do not fall through to a weaker dispatcher.
- installed `sas` absent: use the proven full-repository helper fallback.
- invalid target/encoding: fail before either execution path.
- dirty or separately owned checkout: preserve it; do not reset/clean.
- repository freshness is unproven: stop before product command handoff.
- required network intent is unproven: stop before target-capable product execution.
- required network restoration fails: do not promote the child command to success.
- failure after target mutation: classify the registered crash-safe evidence before any rerun.

## Expected outputs

- selected route id;
- selected execution adapter (`sealed crash-safe bootstrap` or full-repository fallback);
- resolved runtime/repository root when known;
- repository freshness disposition;
- starting and required network posture plus transition/restore disposition when applicable;
- executed/not-executed disposition;
- propagated exit code;
- durable result/latest-pointer path;
- one exact next action only when an unproven gate remains.

## Proof ceiling

This skill proves routing, safe target transport, sealed-runtime crash-safe delegation or fallback dependency proof, and exit disposition. It is not standalone handoff authority: a complete operator handoff also requires the composed canonical-path, repository-freshness, network-intent, and restoration gates. Live target mutation, deployment, reboot, automatic sign-in, and runtime acceptance require the registered field artifacts.
