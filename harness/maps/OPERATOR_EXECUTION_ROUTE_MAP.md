# Operator Execution Route Map

This map closes the gap between **choosing a command** and **actually running it from the right place**.

## Route chain

1. `AGENTS.md` — governance and task router.
2. `CODEBASE_MAP.md` — product/harness orientation.
3. `harness/api/harness-command-registry.json` — canonical command intent.
4. `harness/api/operator-execution-route-registry.json` — executable location + operator front door + target transport.
5. `harness/workflows/repository-freshness-before-launch.yaml` — current-tree proof when freshness matters.
6. `harness/workflows/operator-execution-route.yaml` — resolve location, validate/encode target, verify files, execute/handoff.
7. `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` — tracked `-File` helper that decodes/revalidates target data and re-proves route dependencies.
8. `harness/skills/operator-execution-route/SKILL.md` — repeatable agent procedure.
9. `harness/api/terminal-evidence-survival-registry.json` — crash-safe durable evidence for registered field commands.
10. `harness/validators/validate-operator-execution-route.py` — completeness and anti-regression proof.
11. `Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1` — Windows PowerShell 5.1 execution proof.

## Windows path resolution

For a repository-relative operator front door, do not assume the shell is already in SysAdminSuite.

Resolution order:

1. installed `sas repo`;
2. `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`.

After resolving the root, normalize it, read the route from the resolved repo, and prove every `required_files` entry before helper/front-door execution.

## AutoLogon deployment

`command_id: autologon-remote`

Inner product command:

`sas autologon Remote HOST`

Operator front door:

`Run-AutoLogonCrashSafe.cmd HOST`

Tracked route helper:

`harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`

Required files:

- `Run-AutoLogonCrashSafe.cmd`
- `scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1`
- `scripts/Invoke-SasAutoLogonFieldDeployment.ps1`
- `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`

The raw target is first checked against the route hostname/FQDN pattern, then encoded as UTF-8 Base64. Only the encoded `HOST_B64` value is rendered into the one-line operator command. The target crosses into the tracked helper as a positional `powershell.exe -File` argument; the helper decodes and revalidates it before invoking the CMD. This keeps target text out of PowerShell source.

The outer PowerShell command does not call `exit`; the child helper returns the launcher exit code, the outer shell preserves `$LASTEXITCODE`, and a failure raises an error while leaving the operator shell available for evidence/recovery work.

## Build / test / deploy orientation

- Harness validation: `python harness/validators/validate-operator-execution-route.py`
- Windows route execution: `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\PowerShell\OperatorExecutionRouteHarness.Tests.ps1`
- General harness registry validation: `python harness/validators/validate-harness-registries.py`
- Harness completeness: `python Tests/survey/test_operational_harness_completeness_contracts.py`
- Patch whitespace: `git diff --check`
- AutoLogon operator execution: resolve route first; then the registered helper and crash-safe front door.

## Known trap this prevents

Do not present a technically valid inner command while leaving the operator to discover the repository path, reconstruct a `cd`, interpolate raw target text into shell source, choose a weaker launcher, or lose diagnostics because the outer shell was closed.
