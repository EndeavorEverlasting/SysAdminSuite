# Runbook — ScanSnap Deployment

## Authoritative topology

| Role | Host |
|---|---|
| Control plane / Admin Box 1 | `LPW003ASI173` |
| Bounded home/lab target | `CheexMcClappeth` |
| Priority field targets | `WRH250STR001`, `WRH250STR002` |

`LPW003ASI105` is retired for this workflow. Do not use it as a smoke host, example, or acceptance gate.

The multimodal execution contract lives in:

`docs/SCANSNAP_MULTIMODAL_DEPLOYMENT.md`

## Unattended remote-execution contract

The normal deployment transaction is initiated from Admin Box 1 and must not depend on anyone standing at the target workstation.

A target may be physically unknown, hidden, unattended overnight, locked, or in active clinical space. The authorized hostname/FQDN is the operational handle. The controller resolves that identity through the active network/domain authority and performs remote administrative staging/execution.

Production success must not require:

- local console access;
- a logged-on user;
- user clicks or approval prompts;
- interactive target-side credential entry;
- physically locating the workstation.

Remote SYSTEM Task Scheduler execution and deterministic detection exist specifically so the deployment can complete without a target-side operator.

Any newly discovered transport that requires target-side interaction is not an acceptable replacement for the unattended production path.

## Important split: source vs transport

ScanSnap is not assumed to come from the internal Northwell software directory.

For this workflow:

1. acquire/qualify the exact installer from the authoritative web/client source on an Internet-capable Admin Box;
2. bind filename, SHA256, type, SilentArgs, DetectType, DetectValue;
3. stage the bound package from Admin Box to the authorized target over the active deployment transport.

Package acquisition is not a network-deployment mode.

## Deployment modes

### LAB_LOCAL

Purpose: one bounded prototype against PTop.

```text
LPW003ASI173 -> CheexMcClappeth
```

Use exact-target identity evidence only. Short name, `CheexMcClappeth.local`, and the current IPv4 may be compared as aliases, but do not hard-code a DHCP IPv4 as the target contract and do not scan the subnet.

The home LAN does not provide the Northwell DC. Therefore domain-auth failure on this mode is not surprising and must not be treated as proof that the target is absent.

If explicit local-admin auth cannot establish `ADMIN_SHARE_READY` after one useful experiment loop, record the typed failure and move on. PTop is diagnostic, not a field release gate.

### NORTHWELL_PROTECTED

Purpose: primary field deployment on Northwell hardwire / WAB / protected route.

Reuse the repository network authority:

- `scripts/SasNorthwellNetworkAuthority.psm1`
- `scripts/SasNetworkGuard.psm1`
- `Config/NETWORK_GUARD_README.md`
- `docs/SOFTWARE_DEPLOYMENT_LOW_NOISE.md`

Use exact field hosts:

```text
WRH250STR001
WRH250STR002
```

Short names may be completed to the active corporate DNS suffix when required by the existing low-noise/domain contract.

### NORTHWELL_VPN

Purpose: field deployment through an authenticated `DomainAuthenticated` VPN route.

VPN is a protected authority mode, not a separate package architecture. Once protected authority and target identity are proven, use the same stage + SYSTEM Task Scheduler + detection lifecycle.

### UNKNOWN_BLOCKED

No target mutation.

## Canonical field artifacts

All under `Config/SoftwareDeploy/ScanSnap/`:

- `Preflight-ScanSnap-Field.cmd` — one-command field readiness proof; no target mutation
- `Deploy-ScanSnap-Field.cmd` — one-command live field deployment; local Admin Box confirmation required
- `Invoke-ScanSnapFieldDeployment.ps1` — deterministic field orchestrator
- `field-deployment.workflow.json` — machine-readable ordering, ownership, terminal-state, and fail-closed contract
- `Bind-ScanSnapPackage.ps1` — package binder; writes ignored `package.local.manifest.json` by default
- `hosts_field.txt` — exact field targets
- `package.manifest.json` — tracked unbound template only
- `package.local.manifest.json` — ignored Admin Box bound package truth when present
- `installers/` — local ignored package drop

Legacy/lab compatibility remains in `Deploy-ScanSnap.cmd` + `Deploy-ScanSnap.ps1`. The familiar CMD also exposes exact no-argument shunts `/FIELDPREFLIGHT` and `/FIELD`; these bypass the legacy combinatorial argument parser and delegate to the canonical field entrypoints.

## Package qualification

Before any live install:

- establish exact ScanSnap product identity from client/repository/vendor evidence;
- use an authoritative official vendor/client source;
- compute SHA256;
- determine actual supported silent arguments;
- determine an actual post-install detection rule;
- bind the manifest;
- read back the manifest.

Do not silently choose between ScanSnap product families when the client evidence does not support the choice.

## P82 execution rule

Every unresolved empirical question uses:

`HYPOTHESIS -> BUILD -> MEASURE -> CRITIQUE -> DECIDE`

A failed experiment is useful only when it changes the next decision. Do not repeat identical probes when the failed dependency has not changed.

## Home prototype

From Admin Box 1 first prove the controller identity:

```powershell
$env:COMPUTERNAME
```

Expected: `LPW003ASI173`.

Then resolve/address `CheexMcClappeth` entirely from Admin Box 1 without subnet enumeration or target-side interaction. If controller-side identity evidence converges, test the existing SMB/admin-share path with explicit authorized local credentials supplied remotely where required.

Desired lab gate:

`AccessClass=ADMIN_SHARE_READY`

Then, only if package binding is complete, the existing live command may be used against `hosts_smoke.txt`.

Lab success is useful but not required before field execution.

## Protected field readiness

On Northwell LAN/WAB or authenticated VPN, use the canonical field preflight:

```cmd
Preflight-ScanSnap-Field.cmd
```

Compatibility form:

```cmd
Deploy-ScanSnap.cmd /FIELDPREFLIGHT
```

The preflight itself proves, in order:

1. the Admin Box process is elevated;
2. bound local package truth exists and its installer SHA-256 matches;
3. `Assert-SasNorthwellNetwork` accepts the protected route;
4. each configured field target canonicalizes to one exact FQDN;
5. fresh hard-bounded P02 transport evidence classifies each target `kerberos_smb_task_ready`;
6. no target mutation has occurred.

Ordinary Internet Wi-Fi may remain present while a stronger live `DomainAuthenticated` non-Wi-Fi VPN/LAN route supplies protected authority. Visible Wi-Fi must not override that stronger route.

If target canonicalization or transport admission fails, stop on the typed terminal state. Do not broaden discovery, switch transports after mutation, or invent a second resolver.

## Live field deployment

```cmd
Deploy-ScanSnap-Field.cmd
```

Compatibility form:

```cmd
Deploy-ScanSnap.cmd /FIELD
```

The live command reruns the complete preflight. Only after every target is ready does the **Admin Box** display the exact package hash and target FQDNs and ask for the literal confirmation `DEPLOY SCANSNAP`. No confirmation is requested or accepted on a target workstation.

Required proof chain:

1. package hash validated from machine-local bound truth;
2. protected network authorized;
3. exact target FQDN bound;
4. P02 classifies Kerberos SMB + Scheduled Task ready;
5. Admin Box confirmation received;
6. source and target staged hashes match;
7. remote SYSTEM task executes noninteractively;
8. installer root plus identity-bound descendant family finishes inside one timeout budget;
9. required post-install detection passes before and after run-scoped payload cleanup;
10. transient task/staging teardown is verified;
11. controller summary reaches `SAS_SCANSNAP|STATE=DEPLOYMENT_VALIDATED`.

Do not claim success from ping, port 445, C$ access, task creation, root installer exit, or process discovery alone.

## CMD convergence

Successful prototype-only steps must not remain as ad-hoc console history.

Preserve the existing `Deploy-ScanSnap.cmd` front door unless repository factoring proves a stronger canonical `sas` owner. Promote only measured, selected behavior behind the repository's established operator surface and add regression coverage.

Do not invent a new `/MODE` argument merely because multiple modes now exist; first inspect existing command-routing/network-authority conventions and implement the smallest compatible interface.

## Existing observed evidence

Prior home run:

- Admin Box: `LPW003ASI173`
- PTop candidate: `CheexMcClappeth` / runtime `192.168.1.79`
- DC lookup: `ERROR_NO_SUCH_DOMAIN (1355)`
- hostname admin share: `AUTH_DC_UNAVAILABLE`
- IP admin share: `LOGON_FAILURE`
- no target mutation
- no package was bound at that time

The next home test should therefore target controller-side resolution/addressability + remote local-auth uncertainty. It must not require anyone at PTop and should not rediscover the already-known lack of a Northwell DC on the home LAN.

## Evidence

Canonical field evidence is controller-local:

- latest pointer: `%ProgramData%\SysAdminSuite\SoftwareDeploy\ScanSnap\latest-run.json`
- per-run root: `%ProgramData%\SysAdminSuite\SoftwareDeploy\ScanSnap\runs\<run_id>\`
- preflight receipt: `preflight-summary.json`
- live summary: `deployment-summary.json`
- package-bound stable process cache: `%ProgramData%\SysAdminSuite\SoftwareDeploy\ScanSnap\process-identity.json`

Legacy `Deploy-ScanSnap.ps1` logs remain under `%SystemDrive%\ScanSnapDeployLogs\` and are not the canonical field completion artifact.

The process cache is valid only for the same installer filename + SHA-256. Run-local PID identity additionally freezes creation time to prevent PID reuse from becoming authority. No target-side GUI coordinates, titles, clicks, or confirmation prompts are used.

Every report must distinguish design, readiness, target mutation, installer/process completion, detection, teardown, and field production proof.
