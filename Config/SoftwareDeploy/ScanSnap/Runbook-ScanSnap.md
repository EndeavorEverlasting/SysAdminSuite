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

## Observed Admin Box 1 evidence (2026-10-06)

From `LPW003ASI173`:

- WhatIf against `CheexMcClappeth` persisted evidence under `C:\ScanSnapDeployLogs\`.
- Final class: `ACCESS_DENIED` (DNS/ping OK; `net view` system error 5; admin share not usable).
- Package unbound (`Bound=false`) — installer not yet present on Admin Box 1.
- Live certification and field deploy remain blocked until admin-share access and package binding are available.
