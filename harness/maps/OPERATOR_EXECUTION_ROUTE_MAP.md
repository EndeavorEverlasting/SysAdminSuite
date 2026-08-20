# Operator Execution Route Map

This map closes the gap between **choosing a command** and **actually running it from the correct execution surface**.

## Route chain

1. `AGENTS.md` — governance and task router.
2. `CODEBASE_MAP.md` — product/harness orientation.
3. `harness/api/harness-command-registry.json` — canonical command intent.
4. `harness/api/operator-execution-route-registry.json` — execution adapter + fallback + target transport.
5. `harness/workflows/repository-freshness-before-launch.yaml` — current-tree proof when freshness matters.
6. `harness/workflows/operator-execution-route.yaml` — resolve sealed runtime or full-repository fallback, validate/encode target, execute/handoff.
7. `scripts/Invoke-SasUniversalField.ps1` — installed universal `sas` implementation. Current AutoLogon Remote dispatch is crash-safe; Recover remains recovery-only.
8. `Bootstrap-SysAdminSuiteAutoLogon.cmd` — sealed runtime crash-safe AutoLogon entrypoint used directly by the operator route.
9. `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` — full-repository fallback helper that decodes/revalidates target data and re-proves route dependencies.
10. `harness/skills/operator-execution-route/SKILL.md` — repeatable agent procedure.
11. `harness/api/terminal-evidence-survival-registry.json` — durable field evidence authority.
12. `harness/validators/validate-operator-execution-route.py` — completeness and anti-regression proof.
13. `Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1` — Windows PowerShell 5.1 proof, including registry-less sealed runtime and stale-dispatcher bypass.

## Windows execution resolution

Do not assume the shell is already in SysAdminSuite, and do not assume every valid runtime is a full repository.

For `autologon-remote`:

1. If installed `sas` exists, run `sas repo` to locate the machine-local runtime.
2. A result such as `C:\SASAL` is valid even when it contains no `harness\` tree.
3. Require `Bootstrap-SysAdminSuiteAutoLogon.cmd` beneath that resolved runtime and invoke it directly with the validated target.
4. Do **not** trust an arbitrary installed `sas autologon Remote` dispatcher as crash-safe; installed command copies can lag the sealed runtime.
5. If installed `sas` is unavailable, use `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt` only as a full-repository fallback and prove every registered `required_files` entry before helper execution.

## AutoLogon deployment

`command_id: autologon-remote`

Canonical product command:

`sas autologon Remote HOST`

Sealed route entrypoint:

`Bootstrap-SysAdminSuiteAutoLogon.cmd HOST`

Durable crash-safe authority:

`Run-AutoLogonCrashSafe.cmd HOST`

Full-repository fallback helper:

`harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`

The target is checked against the hostname/FQDN pattern and transported as UTF-8 Base64 in the rendered route. The route decodes and revalidates it before resolving the sealed runtime. When installed SAS is present, the route calls the sealed bootstrap directly. If installed SAS is absent, the same encoded target crosses into the tracked helper as a positional `powershell.exe -File` argument and is decoded/revalidated again before fallback launcher execution.

The sealed bootstrap verifies `C:\SASAL` staging state and invokes `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`, which creates the registered `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon` result/transcript/latest-pointer evidence. The outer route preserves `$LASTEXITCODE` and the operator shell on failure.

## Build / test / deploy orientation

- Harness validation: `python harness/validators/validate-operator-execution-route.py`
- Universal SAS routing validation: `python Tests/survey/test_universal_field_platform_contracts.py`
- Windows route execution: `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\PowerShell\OperatorExecutionRouteHarness.Tests.ps1`
- General harness registry validation: `python harness/validators/validate-harness-registries.py`
- Harness completeness: `python Tests/survey/test_operational_harness_completeness_contracts.py`
- Patch whitespace: `git diff --check`

## Known trap this prevents

A sealed product runtime such as `C:\SASAL` is not a full repository. Do not append `harness\api\operator-execution-route-registry.json` to it and classify the missing harness tree as an AutoLogon failure. Also do not assume that the mere presence of an installed `sas` command proves its AutoLogon dispatcher is current: resolve the sealed runtime and invoke `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly for target-mutating Remote work.
