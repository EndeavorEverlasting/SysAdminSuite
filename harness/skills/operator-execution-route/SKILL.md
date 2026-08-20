# Operator Execution Route

## Trigger

Load this skill after a canonical command has been selected when any of the following is true:

- the command is repository-relative;
- a registered crash-safe or technician front door exists;
- the operator asks to get to the right path and run the command;
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
4. If current repository behavior matters, satisfy `harness/workflows/repository-freshness-before-launch.yaml` first.
5. Resolve the executable repository/runtime location. Do **not** assume the current directory.
6. Prefer `sas repo` when the installed operator launcher is available; otherwise use the bounded `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt` cache.
7. Verify every route `required_files` entry beneath the resolved root before execution.
8. When a registered `operator_front_door` exists, use it. The inner product command is implementation context, not operator handoff text.
9. Set the shell location to the resolved root and run the front door.
10. Propagate the child exit code exactly.
11. If this environment cannot execute on the operator workstation, emit one copy-paste route-and-run command from the registry template. Do not split it into “cd here” plus a second command when the harness can do both.
12. Report the durable artifact/pointer expected from the front door. Terminal text is not durable proof.

## AutoLogon rule

For `autologon-remote`, the operator front door is:

`Run-AutoLogonCrashSafe.cmd HOST`

Do not hand the operator only:

`sas autologon Remote HOST`

The latter remains an inner product command. The registered crash-safe launcher owns persistent diagnostics, offline evidence recovery, and exit propagation.

## Failure handling

- Unresolved repository root: fail closed and route the operator to `sas refresh` on Guest/Internet when freshness/staging is required.
- Resolved root missing a required front door: treat this as a repository freshness/path proof failure before inventing an alternate command.
- Dirty or separately owned checkout: preserve it; use the repository-freshness workflow rather than reset/clean.
- Missing workstation execution capability: state that exact external blocker and provide one copy-paste route-and-run command.
- Command failure: preserve the registered crash-safe artifacts and latest pointer before considering any rerun.

## Expected outputs

- selected route id;
- resolved repository root or exact reason it could not be resolved;
- selected operator front door;
- executed/not-executed disposition;
- propagated exit code when executed;
- durable success/failure artifact path;
- one exact next action only when a real unproven gate remains.

## Proof ceiling

This skill proves routing and execution-location correctness only. Live target, deployment, reboot, automatic sign-in, and runtime acceptance require the registered product artifacts.
