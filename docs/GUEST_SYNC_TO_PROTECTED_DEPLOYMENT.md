# Guest Sync to Protected-Network Deployment

Use this runbook when a technician has Internet/GitHub access on Guest but must move to the approved protected network before contacting a Cybernet or software source.

## Required sequence

### Phase 1 — Guest / Internet only

Do **not** contact a Cybernet from Guest.

Refresh the operator surface before switching networks:

```powershell
sas refresh
```

Expected terminal marker:

```text
SAS_OPERATOR_REFRESH_READY
```

`refresh` performs only repository/operator maintenance:

1. resolves the cached SysAdminSuite repository;
2. fetches current `origin/main` from GitHub;
3. creates or refreshes an isolated `%LOCALAPPDATA%\SysAdminSuite\field-ready` worktree at that exact `origin/main` commit;
4. does not reset, clean, merge, or overwrite the technician's normal working tree;
5. verifies the deployment, probe, evidence, launcher, and installer entrypoints exist;
6. reinstalls the user-local `sas` dispatcher from the field-ready worktree.

It performs no Cybernet target contact, no software-share access, no scheduled-task action, no package installation, and no restart.

If the installed `sas` command predates `sas refresh`, use the one-time stale-launcher bootstrap in the next section.

### One-time stale-launcher bootstrap

This is specifically for machines where `%LOCALAPPDATA%\SysAdminSuite\bin\sas.cmd` exists but rejects newer commands such as `evidence` or `refresh`.

From a normal Windows terminal while still on Guest, use the cached repo path to fetch `origin/main`, extract the tracked refresh script directly from the fetched commit, and execute it without changing the old working tree:

```cmd
for /f "usebackq delims=" %R in ("%LOCALAPPDATA%\SysAdminSuite\repo-root.txt") do set "SAS_REPO=%R"
git -C "%SAS_REPO%" fetch --prune origin main
git -C "%SAS_REPO%" show origin/main:scripts/Refresh-SasOperatorCommand.ps1 > "%TEMP%\Refresh-SasOperatorCommand.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\Refresh-SasOperatorCommand.ps1" -RepositoryRoot "%SAS_REPO%"
```

Require:

```text
SAS_OPERATOR_REFRESH_READY
```

After that one bootstrap, the installed shim is self-refreshing from the cached field-ready repo and `sas refresh` becomes the normal Guest-side sync command.

If `repo-root.txt` is missing, open any existing SysAdminSuite checkout and run `Install-SasOperatorCommand.cmd` once, then run `sas refresh` while still on Guest.

### Phase 2 — verify before leaving Guest

Run:

```powershell
sas
```

The help must include all of these commands:

```text
sas refresh
sas cybernet Deploy HOST
sas cybernet Probe HOST
sas evidence
```

Optional repo confirmation:

```powershell
sas repo
```

The resolved repo should normally be the isolated field-ready checkout created by refresh.

Do not run the target probe or deployment while still on Guest.

### Phase 3 — move to the approved protected network

After the Guest-side refresh is complete, connect to the approved network required for Cybernet administration and package access.

For a full authorized deployment:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

Do not run a separate probe first unless the goal is diagnosis rather than deployment. Full deployment owns a fresh readiness gate in the same transaction before any target mutation.

The full deployment sequence is:

1. approved local network posture;
2. canonical one-target identity resolution;
3. bounded Kerberos SMB plus Task Scheduler readiness;
4. five approved clinical-core applications;
5. AutoLogon last through the current S4U lane;
6. required restart and offline/online restart observation;
7. final crash-recoverable result artifact.

Required full success:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

### Phase 4 — terminal crash or lost output

Do **not** rerun deployment merely because the terminal closed.

Run:

```powershell
sas evidence Cybernet Open
```

This recovery action is local/offline with respect to targets. Inspect the newest readiness, clinical-core, controller, AutoLogon, or full-deployment artifact and continue only from the recorded state.

If the five clinical-core applications are already proven complete but AutoLogon remains incomplete, preserve the core and use the AutoLogon-only lane instead of reinstalling the applications:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

Required AutoLogon-only success:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

## Staleness rule

The user-local `sas.cmd` is now a stable shim. Before each command it compares the cached repository's tracked `SasPortableLauncher.ps1` with the installed copy. If the repo copy changed and parses cleanly, the shim refreshes the installed dispatcher automatically. If the repo copy has parse errors, the previously installed launcher is preserved.

That self-refresh does **not** fetch GitHub by itself. Use `sas refresh` on Guest whenever you need current `origin/main` before protected-network field work.

## Safety boundary

Guest sync is repository maintenance only. Protected-network deployment is target work. Keep those phases separate.

Never substitute broad subnet discovery, Naabu/Nmap, WinRM discovery, fixture loops, or repeated blind probes for the bounded one-target deployment path.
