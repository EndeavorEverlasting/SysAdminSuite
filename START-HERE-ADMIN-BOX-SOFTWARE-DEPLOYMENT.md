# Start Here — Admin Box Software Deployment

Use this page when an authorized technician is deploying the current Cybernet software profile from a Windows admin workstation that may contain old, dirty, OneDrive-backed, or otherwise untrusted SysAdminSuite checkouts.

The admin workstation's historical checkouts are **not deployment authority**. Preserve them. Do not reset, clean, rebase, delete, or rehabilitate them merely to deploy software.

## Phase 1 — Guest / Internet: acquire current main and seal the field runtime

Repository synchronization is Guest/Internet-only. If off site, keep ordinary Internet connected and disconnect the protected Northwell VPN before this phase.

When the installed `sas` command is already current, the normal command remains:

```powershell
sas refresh
```

When `sas` may be stale or unavailable, do not choose an old Desktop/OneDrive checkout. Create a disposable bootstrap checkout of current `main` under `%LOCALAPPDATA%` and run its tracked field-runtime bootstrap. The bootstrap checkout is only an acquisition surface; `scripts\Refresh-SasOperatorCommand.ps1` still moves remote repository maintenance into the dedicated sync cache and stages the exact fetched commit into `C:\SASAL`.

The tracked bootstrap is:

```text
Bootstrap-SysAdminSuiteFieldRuntime.cmd
```

It runs the Guest-only refresh, seals `C:\SASAL`, and installs the universal `sas` command from that sealed runtime. It performs no field-target contact or mutation.

Required terminal marker:

```text
SAS_FIELD_RUNTIME_BOOTSTRAP_READY
```

The underlying refresh must also emit its normal successful runtime/operator markers. If refresh fails, remain on Guest/Internet and repair that exact failure. Do not switch to the protected network with a failed or partial seal.

## Phase 2 — Protected Northwell: deploy one authorized Cybernet

After Guest preparation succeeds, switch to an approved protected authority: Northwell hardwire, NSLIJHS-WAB, or an authenticated `DomainAuthenticated` VPN.

Open a new terminal and run the current field front door:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET>
```

A separate `Probe` is not required. `Deploy` owns its fresh one-target readiness gate and stops before mutation if the protected route, target, SMB/admin authorization, or Task Scheduler dependency is not ready.

The current `Deploy-CybernetSoftware.cmd` is intentionally a thin delegate. It does **not** execute a sibling deployment engine from whichever checkout happened to launch it. It requires:

```text
C:\SASAL\Bootstrap-SysAdminSuiteCybernetSoftware.cmd
```

That bootstrap performs, in order and before target contact:

1. sealed manifest authority resolution;
2. complete SHA-256 tracked-runtime audit;
3. only then, the canonical full Cybernet software deployment engine.

Protected-side Git network activity is `NONE`. If the sealed runtime, manifest, commit identity, or tracked-file hashes are missing or inconsistent, deployment fails before target contact and instructs the operator to return to Guest/Internet and run `sas refresh`.

## Full deployment result

The full transaction remains:

1. low-noise Kerberos SMB + Task Scheduler readiness;
2. five approved clinical-core applications;
3. AutoLogon last through Kerberos/S4U;
4. automatic target restart;
5. bounded observation that the target left and returned on the proven SMB path;
6. durable final evidence.

Required terminal success:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

Canonical result:

```text
survey\output\runs\cybernet-software-deployment\cybernet-software-deployment-*\cybernet_software_deployment_result.json
```

## If the terminal closes or the result is uncertain

Do not rerun the deployment merely to recover console output. Run the offline evidence path first:

```powershell
sas evidence Cybernet Open
```

Review the newest preserved readiness/deployment/AutoLogon evidence and continue only from the recorded state. A prior run that may already have mutated the target or started the restart cycle is not permission for a blind second Admin Box attempt.

## AutoLogon-only case

If the five clinical applications are already proven installed and accepted, preserve them and use the separate sealed AutoLogon lane instead of reinstalling the full profile:

```powershell
sas autologon Remote <AUTHORIZED-CYBERNET>
```

Required success classification:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

## Safety boundary

- Guest phase: repository acquisition, local staging, seal creation, launcher installation; **no target contact**.
- Protected phase: one explicitly authorized target; **no Git network I/O**.
- Old admin-box checkouts: preserved evidence/development state; **never implicit deployment authority**.
- Runtime proof of the interactive AutoLogon desktop remains a separate higher proof ceiling and is not required for deployment completion.
