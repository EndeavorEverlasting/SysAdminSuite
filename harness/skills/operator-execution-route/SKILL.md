# Operator Execution Route

## Trigger

Load this skill after a canonical command has been selected when any of the following is true:

- the command is repository-relative;
- a registered crash-safe or technician front door exists;
- the operator asks to get to the right execution surface and run the command;
- the current shell location is unknown;
- the agent is about to hand a command to the operator rather than execute it;
- AutoLogon `autologon-remote` is selected.

## Required inputs

- canonical `command_id`;
- requested goal;
- explicit target when the command requires one;
- whether the current environment can execute on the operator workstation;
- current repository/network authorization context.

## Procedure

1. Read `harness/api/operator-execution-route-registry.json`.
2. Resolve exactly one execution route for the selected `command_id`.
3. Read `harness/workflows/operator-execution-route.yaml`.
4. Verify the route `repository_freshness_dependency` is tracked; if current repository behavior matters, satisfy it before execution.
5. Do **not** assume the current directory or assume every runtime is a full repository.
6. For `autologon-remote`, prefer a proven installed `sas` command. Validate/decode the encoded target and invoke `sas autologon Remote HOST`; the launcher owns `Resolve-SasPreparedAutoLogonRuntime`, the sealed `C:\SASAL` manifest, and protected bootstrap selection.
7. Do not require `C:\SASAL` to contain `harness/api/operator-execution-route-registry.json`; the sealed runtime intentionally contains the bounded product surface rather than the full harness tree.
8. If installed `sas` is unavailable, resolve a full repository via `sas repo` and then `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt` as bounded fallback.
9. On that full-repository fallback only, verify every route `required_files` entry, invoke the registered `operator_helper` via `powershell.exe -File`, and let the helper decode/revalidate the target and invoke `operator_entrypoint`.
10. When the route declares a target, validate it against `target_validation_pattern`, encode it exactly as `target_encoding` requires, and never interpolate raw target text into PowerShell source.
11. Propagate the child exit code exactly and preserve the outer operator PowerShell on failure.
12. If this environment cannot execute on the operator workstation, emit one copy-paste command that advances the first unproven field gate.
13. Report the durable artifact/pointer expected from the crash-safe field transaction. Terminal text is not durable proof.

## AutoLogon rule

The durable crash-safe authority remains:

`Run-AutoLogonCrashSafe.cmd HOST`

The installed SAS product command is:

`sas autologon Remote HOST`

A proven installed SAS command is a valid field execution adapter because `scripts/SasPortableLauncher.ps1` resolves the prepared sealed runtime and invokes its AutoLogon bootstrap, which enters the crash-safe field transaction. Do not hand `sas autologon Remote HOST` as an unproven generic shortcut. When installed SAS and its prepared runtime are already proven on the operator machine, it may be the exact next field command.

## Failure handling

- Installed SAS with prepared sealed runtime: use it; do not reinterpret its `sas repo` result as a full repository requirement.
- Installed SAS absent: use the full-repository helper fallback and prove every registered dependency.
- Invalid target or target encoding: fail before either execution path; never weaken hostname validation.
- Dirty or separately owned checkout: preserve it; use repository freshness rather than reset/clean.
- Missing workstation execution capability: state that external blocker and provide the one executable command that advances it.
- Command failure after target mutation: preserve the registered crash-safe artifacts/latest pointer and classify that evidence before considering any rerun.

## Expected outputs

- selected route id;
- selected execution adapter (`installed sas` or full-repository fallback);
- resolved runtime/repository root when known;
- executed/not-executed disposition;
- propagated exit code when executed;
- durable success/failure artifact path;
- one exact next action only when a real unproven gate remains.

## Proof ceiling

This skill proves routing, safe target transport, sealed-runtime delegation or fallback dependency proof, and exit disposition. Live target mutation, deployment, reboot, automatic sign-in, and runtime acceptance require the registered product artifacts.
