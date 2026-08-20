# Operator Execution Route Map

This map closes the gap between **choosing a command** and **actually running it from the right place**.

## Route chain

1. `AGENTS.md` — governance and task router.
2. `CODEBASE_MAP.md` — product/harness orientation.
3. `harness/api/harness-command-registry.json` — canonical command intent.
4. `harness/api/operator-execution-route-registry.json` — executable location + operator front door.
5. `harness/workflows/repository-freshness-before-launch.yaml` — current-tree proof when freshness matters.
6. `harness/workflows/operator-execution-route.yaml` — resolve location, verify files, execute/handoff.
7. `harness/skills/operator-execution-route/SKILL.md` — repeatable agent procedure.
8. `harness/api/terminal-evidence-survival-registry.json` — crash-safe durable evidence for registered field commands.
9. `harness/validators/validate-operator-execution-route.py` — completeness and anti-regression proof.

## Windows path resolution

For a repository-relative operator front door, do not assume the shell is already in SysAdminSuite.

Resolution order:

1. installed `sas repo`;
2. `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`.

After resolving the root, normalize it and prove the required front-door files exist before execution.

## AutoLogon deployment

`command_id: autologon-remote`

Inner product command:

`sas autologon Remote HOST`

Operator front door:

`Run-AutoLogonCrashSafe.cmd HOST`

Required files:

- `Run-AutoLogonCrashSafe.cmd`
- `scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1`
- `scripts/Invoke-SasAutoLogonFieldDeployment.ps1`

The harness must resolve the repo root, `Set-Location` there, invoke the crash-safe launcher, and propagate its exit code. If the agent cannot execute on the technician workstation, it returns one route-and-run PowerShell command that does all four steps.

## Build / test / deploy orientation

- Harness validation: `python harness/validators/validate-operator-execution-route.py`
- General harness registry validation: `python harness/validators/validate-harness-registries.py`
- Harness completeness: `python Tests/survey/test_operational_harness_completeness_contracts.py`
- Patch whitespace: `git diff --check`
- AutoLogon operator execution: resolve route first; then the registered crash-safe front door.

## Known trap this prevents

Do not present a technically valid inner command while leaving the operator to discover the repository path, reconstruct a `cd`, choose a different launcher, or lose diagnostics when the terminal closes.
