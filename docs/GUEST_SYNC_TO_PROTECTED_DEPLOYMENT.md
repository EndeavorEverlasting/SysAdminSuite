# Guest Sync to Protected-Network Deployment

Use this runbook when a technician has Internet/GitHub access on Guest but must move to the approved protected network or DomainAuthenticated VPN before contacting a Cybernet or software source.

## Non-negotiable network split

SysAdminSuite repository acquisition and refresh happen **only on Guest / Internet**.

Protected Northwell/VPN deployment consumes a pre-staged short runtime at `C:\SASAL` and performs **no Git network I/O**. The protected runtime is sealed with no Git remotes so an accidental `fetch`, `pull`, or clone cannot occur from that runtime during field deployment.

The expected operator rhythm is:

```text
Guest / Internet  ->  sas refresh  ->  C:\SASAL sealed
Protected / VPN   ->  sas autologon Remote HOST
```

Do not combine those phases in one command.

## Required sequence

### Phase 1 — Guest / Internet only

Do **not** contact a Cybernet from Guest.

Refresh the operator surface before switching networks:

```powershell
sas refresh
```

`refresh` now fails closed before its first remote Git probe unless the current network classifies as `GUEST_INTERNET`.

Expected terminal markers:

```text
SAS_AUTOLOGON_SHORT_RUNTIME_READY
SAS_OPERATOR_REFRESH_READY
```

`refresh` performs repository/operator maintenance only:

1. proves the current network is Guest/Internet **before** any `ls-remote` or fetch;
2. resolves the cached SysAdminSuite repository;
3. fetches the selected tracked branch from GitHub;
4. creates or refreshes an isolated `%LOCALAPPDATA%\SysAdminSuite\field-ready` worktree at that exact fetched commit;
5. locally transfers that already-fetched commit into `C:\SASAL` without contacting GitHub from the runtime;
6. pins `C:\SASAL` to the exact commit and refuses to overwrite dirty runtime work;
7. removes every Git remote from `C:\SASAL`;
8. writes `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json` proving the staged commit and Guest preparation posture;
9. verifies the deployment, recovery, evidence, launcher, and installer entrypoints exist;
10. reinstalls the user-local `sas` dispatcher from the field-ready worktree.

It performs no Cybernet target contact, no software-share access, no scheduled-task action, no package installation, and no restart.

### One-time stale-launcher bootstrap

This is only for machines where `%LOCALAPPDATA%\SysAdminSuite\bin\sas.cmd` exists but rejects `refresh` or the current operator command set.

Do this while still on Guest/Internet. Never perform this Git bootstrap on protected Northwell/VPN.

From any existing SysAdminSuite checkout:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Refresh-SasOperatorCommand.ps1 -RepositoryRoot (Get-Location).Path
```

Require both runtime/refresh markers before leaving Guest.

If no usable checkout exists, clone SysAdminSuite **while on Guest/Internet**, install the operator command once, and immediately run `sas refresh`. Do not clone on the protected network.

### Phase 2 — verify the sealed runtime before leaving Guest

Run:

```powershell
sas
```

The help must include:

```text
sas refresh
sas autologon Remote HOST
sas autologon Recover HOST
sas cybernet Deploy HOST
sas evidence
```

The short AutoLogon runtime must exist:

```powershell
Test-Path C:\SASAL
Get-Content "$env:LOCALAPPDATA\SysAdminSuite\autologon-short-runtime.json"
```

The manifest must identify `GUEST_INTERNET`, the exact prepared commit, `LOCAL_FILESYSTEM_ONLY`, and `protected_bootstrap_git_network_allowed=false`.

Do not run target deployment while still on Guest.

### Phase 3 — move to approved protected Northwell or DomainAuthenticated VPN

Switch networks only after `sas refresh` has completed successfully.

For the AutoLogon-only case where the five clinical-core applications are already proven and must not be reinstalled:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

The installed `sas` launcher reads the sealed runtime manifest and invokes `C:\SASAL\Bootstrap-SysAdminSuiteAutoLogon.cmd` at the prepared commit.

The protected bootstrap performs only local Git verification (`HEAD`, clean state, no remotes). It does not clone, fetch, pull, checkout, reset, or clean the runtime. It then owns:

1. sealed-runtime verification;
2. exact DomainAuthenticated VPN/LAN authority when requested;
3. canonical protected-network gate;
4. canonical FQDN resolution;
5. exact FQDN-only local host authorization;
6. crash-safe AutoLogon field transaction;
7. required restart and offline/online observation;
8. terminal evidence preservation.

Required AutoLogon-only success:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

If durable terminal evidence already exists, the transaction may instead return:

```text
AUTOLOGON_DEPLOYMENT_ALREADY_COMPLETED
```

Stop after either terminal completion marker. Do not run the same target from a second Admin Box merely because another terminal is available.

For a full authorized Cybernet deployment where the clinical-core applications are not already proven:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

Do not run a separate probe first unless the goal is diagnosis rather than deployment. Full deployment owns a fresh readiness gate in the same transaction before target mutation.

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

For the AutoLogon-only lane, inspect:

```text
%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json
C:\SASAL\runs\...\autologon_field_deployment_result.json
```

If the previous result reports target mutation, pre-reboot readiness, restart activity, or ambiguous started state, do not blind-rerun from another Admin Box. Use the recorded recovery path.

## Protected runtime staleness rule

The protected bootstrap never refreshes itself.

If `C:\SASAL` is missing, dirty, has a Git remote, has a HEAD different from the seal, or the sealed commit differs from the requested commit, protected deployment fails with an `AUTOLOGON_RUNTIME_*` error and instructs the operator to return to Guest/Internet and run:

```powershell
sas refresh
```

That is intentional. Field deployment does not repair repository state on the protected network.

## Safety boundary

Guest sync is repository maintenance only. Protected-network deployment is target work. Keep those phases separate.

Never substitute broad subnet discovery, Naabu/Nmap, WinRM discovery, fixture loops, repeated blind probes, or a second Admin Box attempt for the bounded one-target deployment and evidence-recovery path.
