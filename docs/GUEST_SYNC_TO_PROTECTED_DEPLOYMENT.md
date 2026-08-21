# Guest Sync to Protected-Network Deployment

Use this runbook when a technician has Internet/GitHub access on Guest or another ordinary Internet connection but must move to the approved protected network or DomainAuthenticated VPN before contacting a Cybernet or software source.

## Non-negotiable network split

SysAdminSuite repository acquisition and refresh happen **only on Guest / Internet**. Off site, this means ordinary home/hotel/mobile Internet with the Northwell VPN **disconnected** while repository synchronization is running.

Protected Northwell/VPN deployment consumes a pre-staged short runtime at `C:\SASAL` and performs **no Git network I/O**. The protected runtime is sealed with no Git remotes so an accidental `fetch`, `pull`, or clone cannot occur from that runtime during field deployment.

The installed `sas` command prints a network canary before execution. Read `NETWORK REQUIRED`, `CURRENT NETWORK`, and `CURRENT AUTHORITY` as the authoritative routing instruction for that command.

The expected operator rhythm is:

```text
Guest / ordinary Internet, VPN disconnected  ->  sas refresh  ->  sync-cache -> field-ready -> C:\SASAL sealed
Protected hardwire / WAB / authenticated VPN ->  sas autologon Remote HOST
```

Do not combine repository synchronization and target deployment into one product transaction. The network-aware front door may perform a bounded saved-WLAN transition around one command and restore the starting WLAN afterward; that does not merge the Guest-only Git phase with protected target work.

### Automatic transition boundary

SysAdminSuite may automatically move between **previously proven saved WLAN profiles** when it has exact paired bookmarks and can verify the requested destination. The common on-site example is saved Guest/Internet ↔ saved NSLIJHS-WAB. If it switches WLAN for a command, restoration of the starting saved WLAN is part of wrapper success; an unproven restore fails closed.

Authenticated VPN is valid protected authority when already connected, but VPN connect/disconnect is **not** automated yet. The repository has no proven Citrix/other VPN-client lifecycle adapter or credential contract, so `sas refresh` launched while VPN is active tells the operator to disconnect VPN while keeping ordinary Internet connected. Protected commands launched with no protected path tell the operator to connect hardwire, WAB, or authenticated VPN. SysAdminSuite does not guess at VPN commands or disable network adapters.

## Runtime layers

SysAdminSuite deliberately keeps three repository/runtime roles separate:

1. `%LOCALAPPDATA%\SysAdminSuite\sync-cache` — **Guest-only GitHub-facing cache**. This is the only field runtime layer allowed to own a GitHub remote.
2. `%LOCALAPPDATA%\SysAdminSuite\field-ready` — clean operator worktree derived from the sync cache at the exact fetched commit.
3. `C:\SASAL` — protected AutoLogon execution authority. It is populated from field-ready by local Git object transfer and then has every Git remote removed.

The operator's OneDrive/Desktop development checkout is not the field sync cache and is not the protected deployment runtime. Git failures, dirty work, long paths, or unavailable local policy files in that development checkout therefore do not become field-deployment prerequisites. Legacy evidence fallback is disabled unless a caller explicitly supplies one.

## Required sequence

### Phase 1 — Guest / Internet only

Do **not** contact a Cybernet from Guest.

**NETWORK: GUEST / INTERNET — off site, keep ordinary Internet connected and disconnect the Northwell VPN.**

Refresh the operator surface before protected target work:

```powershell
sas refresh
```

The canary must say `NETWORK REQUIRED: GUEST / INTERNET`. `refresh` then fails closed before its first remote Git operation unless the current network classifies as `GUEST_INTERNET`. When a previously paired saved WAB/Guest WLAN transition is safe, the new network-aware front door may temporarily select the exact saved Guest profile and restore the starting WAB after refresh.

Expected terminal markers:

```text
SAS_AUTOLOGON_SHORT_RUNTIME_READY
SAS_OPERATOR_REFRESH_READY
```

`refresh` performs repository/operator maintenance only:

1. proves the current network is Guest/Internet before any remote Git operation;
2. creates or reuses the dedicated `%LOCALAPPDATA%\SysAdminSuite\sync-cache`;
3. validates that cache belongs to the official SysAdminSuite origin and contains no local work;
4. fetches `origin/main` by default, or an explicitly requested ref, **only from that Guest-only cache**;
5. creates or refreshes an isolated `%LOCALAPPDATA%\SysAdminSuite\field-ready` worktree at that exact fetched commit;
6. rechecks Guest/Internet before staging protected runtime state;
7. locally transfers that already-fetched commit from field-ready into `C:\SASAL`;
8. pins `C:\SASAL` to the exact commit and refuses to overwrite dirty runtime work;
9. removes every Git remote from `C:\SASAL`;
10. writes `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json` proving the staged commit and Guest preparation posture;
11. verifies the deployment, recovery, evidence, launcher, and installer entrypoints exist;
12. reinstalls the local `sas` dispatcher from the refreshed runtime.

It performs no Cybernet target contact, no software-share access, no scheduled-task action, no package installation, and no restart.

### One-time stale-launcher bootstrap

This is only for machines where the installed `sas.cmd` exists but rejects `refresh` or the current operator command set.

**NETWORK: GUEST / INTERNET — VPN disconnected.** Never perform this Git bootstrap on protected Northwell/VPN.

From any existing checkout that contains the current refresh script:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Refresh-SasOperatorCommand.ps1 -RepositoryRoot (Get-Location).Path
```

The caller checkout is used only to locate the refresh/network-classifier code. Remote Git still occurs only in the dedicated sync cache.

Require both runtime/refresh markers before protected target work.

If no usable checkout exists, clone SysAdminSuite **while on Guest/Internet with VPN disconnected**, install the operator command once, and immediately run `sas refresh`. Do not clone on the protected network.

### Phase 2 — verify the sealed runtime before protected target work

**NETWORK: ANY / UNCHANGED — local-only checks.**

Run:

```powershell
sas
```

The help must include the current operator commands, and the canary must identify the local-only/unchanged posture.

The short AutoLogon runtime must exist:

```powershell
Test-Path C:\SASAL
Get-Content "$env:LOCALAPPDATA\SysAdminSuite\autologon-short-runtime.json"
```

The manifest must identify `GUEST_INTERNET`, the exact prepared commit, `LOCAL_FILESYSTEM_ONLY`, `runtime_remotes_removed=true`, and `protected_bootstrap_git_network_allowed=false`.

Do not run target deployment while still on unprotected Internet.

### Phase 3 — move to approved protected Northwell or DomainAuthenticated VPN

Switch to protected authority only after `sas refresh` has completed successfully.

**NETWORK: PROTECTED NORTHWELL — authenticated DomainAuthenticated VPN, Northwell hardwire, or NSLIJHS-WAB.**

For the AutoLogon-only case where the five clinical-core applications are already proven and must not be reinstalled:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

The canary must say `NETWORK REQUIRED: PROTECTED NORTHWELL` and identify the active protected authority before target work. The installed `sas` launcher reads the sealed runtime manifest and invokes `C:\SASAL\Bootstrap-SysAdminSuiteAutoLogon.cmd` at the prepared commit.

For this canonical one-target AutoLogon command, the explicit `HOST` argument is the deployment authority. The CMD carries that target only inside its process tree. The host eligibility gate accepts only that same non-local hostname or its canonical FQDN. A pre-existing `Config\host-eligibility-policy.local.json` file is **not required, generated, copied, or consulted as a veto** for this transaction. A different hostname, localhost, fixture/VM/local execution, and unrelated software paths retain their normal fail-closed behavior.

The protected bootstrap performs no remote Git maintenance. It owns:

1. sealed-runtime verification;
2. exact DomainAuthenticated VPN/LAN/WAB authority when requested;
3. canonical protected-network gate;
4. canonical FQDN resolution inside the field transaction;
5. exact process-scoped operator target authorization;
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

**NETWORK: PROTECTED NORTHWELL — authenticated VPN/hardwire/WAB.**

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

**NETWORK: ANY / UNCHANGED — evidence recovery is local/offline with respect to targets.**

```powershell
sas evidence Cybernet Open
```

Inspect the newest readiness, clinical-core, controller, AutoLogon, or full-deployment artifact and continue only from the recorded state.

For the AutoLogon-only lane, inspect:

```text
%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json
C:\SASAL\runs\...\autologon_field_deployment_result.json
```

If the previous result reports target mutation, pre-reboot readiness, restart activity, or ambiguous started state, do not blind-rerun from another Admin Box. Use the recorded recovery path.

## Protected runtime staleness rule

The protected bootstrap never refreshes itself.

If `C:\SASAL` is missing, dirty, has a Git remote, has a HEAD different from the seal, or the sealed commit differs from the requested commit, protected deployment fails with an `AUTOLOGON_RUNTIME_*` error and instructs the operator to return to Guest/Internet.

**NETWORK: GUEST / INTERNET — VPN disconnected before repository synchronization.**

```powershell
sas refresh
```

That is intentional. Field deployment does not repair repository state on the protected network.

## Safety boundary

Guest sync is repository maintenance only. Protected-network deployment is target work. Keep those authorities separate even when the network-aware wrapper can safely automate a saved-WLAN transition around one command.

Never substitute broad subnet discovery, Naabu/Nmap, WinRM discovery, fixture loops, repeated blind probes, or a second Admin Box attempt for the bounded one-target deployment and evidence-recovery path.
