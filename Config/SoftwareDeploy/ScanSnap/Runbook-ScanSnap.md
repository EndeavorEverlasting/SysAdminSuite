# Runbook — ScanSnap Deployment

## Topology

| Role | Host |
|---|---|
| Control plane / Admin Box 1 | `LPW003ASI173` |
| PTop certification target | `CheexMcClappeth` |
| Field targets (after cert) | `WRH250STR001`, `WRH250STR002` |

`LPW003ASI105` is **retired** for this workflow. Do not use it as a smoke host, example, or acceptance gate.

```text
Admin Box 1 / LPW003ASI173
        |
        |  SMB + admin share + remote scheduled task
        v
PTop / CheexMcClappeth
        |
        |  successful live certification
        v
same protocol --> WRH250STR001 + WRH250STR002 (authorized network)
```

## Artifacts

All under `Config/SoftwareDeploy/ScanSnap/`:

- `Deploy-ScanSnap.cmd` — operator entrypoint
- `Deploy-ScanSnap.ps1` — engine
- `hosts_smoke.txt` — `CheexMcClappeth`
- `hosts_field.txt` — field hosts
- `package.manifest.json` — binding contract
- `installers/` — operator-provided binary (gitignored)

## Phase 0 — Preconditions

- Run elevated from Admin Box 1 when performing live installs.
- Drop the ScanSnap installer into `installers\`.
- Bind the manifest (filename, SHA256, Type, SilentArgs, DetectType, DetectValue, Bound=true).
- Do not invent Fujitsu/Ricoh URLs or silent switches.

## Phase 1 — WhatIf against PTop

From Admin Box 1:

```cmd
cd /d C:\Dev\SysAdminSuite-wt-scansnap-deploy-20261006\Config\SoftwareDeploy\ScanSnap
Deploy-ScanSnap.cmd /HOSTSFILE=hosts_smoke.txt /WHATIF
```

Acceptance:

- Target resolves or precise `RESOLVE_FAILED` is recorded
- Admin-share class is one of `ADMIN_SHARE_READY` / `ACCESS_DENIED` / `UNREACHABLE`
- Package hash validated when bound
- No remote mutation (no stage, no schtasks, no install)

Evidence: `%SystemDrive%\ScanSnapDeployLogs\DeployScanSnap_*.csv`

## Phase 2 — Live certification on PTop

```cmd
Deploy-ScanSnap.cmd /HOSTSFILE=hosts_smoke.txt
```

Required proof chain:

1. Admin share ready on `CheexMcClappeth`
2. Payload staged to `\\CheexMcClappeth\C$\SoftwareRepo\ScanSnap\`
3. Task `SysAdminSuite_ScanSnap_Install` created/run as SYSTEM
4. Installer completed (exit observed)
5. Detection gate passed (`DetectType`/`DetectValue`)
6. Final class `INSTALLATION_DETECTED`

Ping, `C$` open, file copy, or task creation alone is **not** enough.

## Phase 3 — Field hosts

Only after Phase 2 succeeds:

```cmd
Deploy-ScanSnap.cmd /HOSTSFILE=hosts_field.txt
```

Add `/DNSSUFFIX=nslijhs.net` only when resolution evidence requires it.

## Logging

| Location | Purpose |
|---|---|
| `%SystemDrive%\ScanSnapDeployLogs\` | Admin Box evidence (txt + CSV) |
| `C:\ProgramData\SysAdminSuite\SoftwareDeploy\ScanSnap\` on target | Remote runner + `install-result.json` |

States are recorded separately: access, staged, task created, task executed, installer completed, detected.

## Observed Admin Box 1 evidence

### 2026-10-06 (initial WhatIf)

- WhatIf against `CheexMcClappeth` persisted under `C:\ScanSnapDeployLogs\`.
- Classified `ACCESS_DENIED` (DNS/ping OK; `net view` system error 5).
- Package unbound (`Bound=false`).

### 2026-10-06 evening (live-cert continuation diagnosis)

Control host: `LPW003ASI173` (`nslijhs\pa_rperez26`), domain-joined to `nslijhs.net`.

| Probe | Result |
|---|---|
| Ping `CheexMcClappeth` / `192.168.1.79` | OK |
| TCP/identity | Host at `192.168.1.79` (ARP present) |
| `nltest /dsgetdc:nslijhs.net` | **ERROR_NO_SUCH_DOMAIN (1355)** — no DC on current LAN |
| `dir \\CheexMcClappeth\C$` | cannot contact a domain controller |
| `dir \\192.168.1.79\C$` | user name or password is incorrect |
| WinRM to `192.168.1.79` | unavailable |
| Stored creds for PTop | none |
| ScanSnap installer under `installers\` | **missing** |

Root cause (admin share): Admin Box is on a network without a reachable domain controller, so Kerberos/domain auth to the hostname fails; NTLM to the IP rejects the current domain credentials (PTop does not accept them as a local admin in this context).

### Smallest operator actions to clear blockers

**Blocker A — admin share** (pick one):

1. Connect Admin Box to the corporate path where `nslijhs.net` DCs are reachable (VPN if required), ensure `nslijhs\pa_rperez26` is a local administrator on `CheexMcClappeth`, then re-run WhatIf; **or**
2. On Admin Box, map with an explicit **PTop local admin** account (password known to operator only):

```cmd
net use \\192.168.1.79\C$ /user:CheexMcClappeth\<LocalAdminUser> *
dir \\192.168.1.79\C$
```

Then:

```cmd
cd /d C:\Dev\SysAdminSuite-wt-scansnap-deploy-20261006\Config\SoftwareDeploy\ScanSnap
Deploy-ScanSnap.cmd /LIST=192.168.1.79 /WHATIF
```

Expect `AccessClass=ADMIN_SHARE_READY`.

**Blocker B — package bind:** drop the real ScanSnap installer into `installers\`, then:

```powershell
.\Bind-ScanSnapPackage.ps1 -InstallerPath .\installers\<file> -SilentArgs '<evidenced>' -DetectType file -DetectValue '<evidenced path>'
```
