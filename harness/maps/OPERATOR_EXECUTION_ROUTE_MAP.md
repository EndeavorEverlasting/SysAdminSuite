# Operator Execution Route Map

This map closes the gap between **choosing a command** and **actually running it from the correct execution surface**.

## Route chain

1. `AGENTS.md` — governance and task router.
2. `CODEBASE_MAP.md` — product/harness orientation.
3. `harness/api/harness-command-registry.json` — canonical command intent.
4. `harness/api/operator-execution-route-registry.json` — execution adapter + fallback + target transport.
5. `harness/workflows/repository-freshness-before-launch.yaml` — current-tree proof when freshness matters.
6. `harness/workflows/operator-execution-route.yaml` — select installed product adapter or full-repository fallback, validate/encode target, execute/handoff.
7. `scripts/SasPortableLauncher.ps1` — installed `sas` product adapter; for AutoLogon it resolves the prepared sealed runtime and invokes its bootstrap.
8. `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` — full-repository fallback helper that decodes/revalidates target data and re-proves route dependencies.
9. `harness/skills/operator-execution-route/SKILL.md` — repeatable agent procedure.
10. `harness/api/terminal-evidence-survival-registry.json` — crash-safe durable evidence for registered field commands.
11. `harness/validators/validate-operator-execution-route.py` — completeness and anti-regression proof.
12. `Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1` — Windows PowerShell 5.1 execution proof, including the sealed-runtime case.

## Windows execution resolution

Do not assume the shell is already in SysAdminSuite, and do not assume every valid runtime is a full repository.

For `autologon-remote`:

1. If installed `sas` exists, use it as the first-class product execution adapter.
2. `sas autologon Remote HOST` owns `Resolve-SasPreparedAutoLogonRuntime` and the sealed `C:\SASAL` bootstrap contract.
3. `C:\SASAL` is allowed to omit the full `harness\` tree; that is expected for the bounded AutoLogon runtime.
4. Only if installed `sas` is unavailable, resolve a full repository via `sas repo`, then `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`, and prove every `required_files` entry before helper execution.

## AutoLogon deployment

`command_id: autologon-remote`

Installed product adapter:

`sas autologon Remote HOST`

Durable crash-safe authority:

`Run-AutoLogonCrashSafe.cmd HOST`

Full-repository fallback helper:

`harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`

The target is checked against the hostname/FQDN pattern and transported as UTF-8 Base64 in the rendered route. The route decodes and revalidates it before invoking installed SAS. If installed SAS is unavailable, the same encoded value crosses into the tracked helper as a positional `powershell.exe -File` argument, where it is decoded/revalidated again before fallback launcher execution.

The outer PowerShell command does not call `exit`; child disposition remains in `$LASTEXITCODE`, and a failure raises an error while leaving the operator shell available for evidence/recovery work.

## Build / test / deploy orientation

- Harness validation: `python harness/validators/validate-operator-execution-route.py`
- Windows route execution: `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\PowerShell\OperatorExecutionRouteHarness.Tests.ps1`
- General harness registry validation: `python harness/validators/validate-harness-registries.py`
- Harness completeness: `python Tests/survey/test_operational_harness_completeness_contracts.py`
- Patch whitespace: `git diff --check`
- AutoLogon field execution with proven installed SAS: `sas autologon Remote HOST`

## Known trap this prevents

A sealed product runtime such as `C:\SASAL` is not a full repository. Do not append `harness\api\operator-execution-route-registry.json` to it and then classify the missing harness tree as an AutoLogon failure. Equally, do not interpolate raw target text into shell source, bypass the prepared-runtime verification, or lose crash-safe evidence because the outer shell was closed.
