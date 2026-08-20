# Operator Execution Route Status

## Working

- SysAdminSuite already has repository freshness, command, outcome, deployment-state, artifact, and terminal-evidence authorities.
- AutoLogon already has a tracked crash-safe operator front door: `Run-AutoLogonCrashSafe.cmd HOST`.
- Persistent operator state already exposes `sas repo`, and the launcher caches the resolved repo root under `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`.
- The new operator-execution route contract requires path resolution before any repository-relative operator command.
- When the current environment can execute on the operator workstation, safe authorized execution continues in the same turn.
- When it cannot, the handoff is one copy-paste route-and-run command that resolves the path, verifies the front door, changes location, runs it, and propagates the exit code.

## Repaired boundary

Previously, a fresh agent could select the correct product command (`sas autologon Remote HOST`) yet still hand it to the operator without resolving where to run it. That forced the operator to reacquire repository context and bypassed the stronger crash-safe launcher already registered elsewhere in the harness.

The operator-execution route makes the front door and execution location a mandatory step between command selection and handoff.

## Missing / not proven

- CI cannot execute a live command on an Admin Box or protected Northwell workstation.
- Route validation does not prove protected-network authorization, target reachability, AutoLogon deployment, restart, or sign-in.
- Those claims require the crash-safe field-run artifacts produced by the operator front door.

## Current AutoLogon route

- command id: `autologon-remote`
- execution root: resolved at runtime via `sas repo`, then bounded cache fallback
- operator front door: `Run-AutoLogonCrashSafe.cmd HOST`
- inner product command: `sas autologon Remote HOST`
- durable result: `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run_id>\field-run-result.json`
- latest pointer: `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`

## Operator expectation

A correct handoff does not say only “run this command.” It either runs the registered front door from the proven location, or gives one command that resolves the location and runs the front door without asking the operator to reconstruct the path.
