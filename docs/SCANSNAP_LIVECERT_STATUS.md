# ScanSnap live-cert status (Admin Box 1)

**Updated:** 2026-10-06 (continuation after PR #507 merge `2610c4f4`)
**Control host:** `LPW003ASI173` @ `192.168.1.88` (Wi-Fi lab LAN)
**Target:** `CheexMcClappeth` / `192.168.1.79`

## Proven

| Gate | State | Evidence |
|---|---|---|
| Package on main | INTEGRATED | PR #507 / `2610c4f4` |
| WhatIf no mutation | VALIDATED | prior + 20261006_224231 / 224237 CSVs |
| Precise access class | VALIDATED | hostname=`AUTH_DC_UNAVAILABLE`; IP=`LOGON_FAILURE` |
| Installer bound | NOT YET | `installers\` empty; `Bound=false` |
| INSTALLATION_DETECTED | NOT YET | blocked |

## Root cause (Blocker A)

Admin Box is domain-joined (`nslijhs.net`) but **no DC is reachable** on the current LAN (`nltest` → ERROR_NO_SUCH_DOMAIN 1355).

- `\\CheexMcClappeth\C$` → cannot contact domain controller
- `\\192.168.1.79\C$` → username or password incorrect (NTLM with current domain token rejected)

No stored credentials for PTop. WinRM unavailable.

## Root cause (Blocker B)

No ScanSnap installer binary present under `Config/SoftwareDeploy/ScanSnap/installers\` or common local drop locations.

## Resume commands (operator)

Clear share auth (local admin password known only to operator):

```cmd
net use \\192.168.1.79\C$ /user:CheexMcClappeth\<LocalAdminUser> *
cd /d C:\Dev\SysAdminSuite-wt-scansnap-deploy-20261006\Config\SoftwareDeploy\ScanSnap
Deploy-ScanSnap.cmd /LIST=192.168.1.79 /WHATIF
```

Bind installer once dropped:

```powershell
.\Bind-ScanSnapPackage.ps1 -InstallerPath .\installers\<file> -SilentArgs '<evidenced>' -DetectType file -DetectValue '<evidenced path>'
```

Live cert:

```cmd
Deploy-ScanSnap.cmd /LIST=192.168.1.79
```

Expect `FinalClass=INSTALLATION_DETECTED`.
