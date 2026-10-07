# ScanSnap Deployment Workflow (canonical plan)

**Branch / worktree:** `feat/scansnap-deploy-adminbox1-ptop-20261006` @ `C:\Dev\SysAdminSuite-wt-scansnap-deploy-20261006`  
**Base:** `origin/main` (`ed3782a6` at lane start)

## Outcome

Deterministic ScanSnap deploy package in SysAdminSuite, certified from Admin Box 1 against PTop, then reused for field hosts.

## Topology (authoritative)

```text
Admin Box 1 / LPW003ASI173
    → PTop / CheexMcClappeth   (attended certification)
    → WRH250STR001 + WRH250STR002 when authorized network exists
```

`LPW003ASI105` is stale and must not appear as a prerequisite, target, or acceptance gate.

## Locked decisions

- Installer is operator-provided; no invented download URL or silent switches.
- Delivery = stage + SYSTEM schtasks install + detection gate.
- Product name remains SysAdminSuite.
- Reuse Stage-To-Clients / SoftwareRepo path, Enforce-SingleHost schtasks pattern, Deploy-Shortcuts `/KEY=VALUE` CMD style.

## Package path

`Config/SoftwareDeploy/ScanSnap/`

## Proof gates

1. Entrypoint exists (`Deploy-ScanSnap.cmd` → `.ps1`).
2. WhatIf against `CheexMcClappeth` mutates nothing.
3. Package SHA256 validated before live install.
4. Live cert proves stage → task → install → detection on PTop.
5. Field deploy uses the same protocol when authorized network is reachable.
6. Evidence distinguishes access / staged / task / installer / detected states.

## Observed floor (recovery)

- Execution host confirmed: `LPW003ASI173`.
- `CheexMcClappeth` resolves (`CheexMcClappeth.local` → `192.168.1.79`) and responds to ping.
- WhatIf (`Deploy-ScanSnap.cmd /HOSTSFILE=hosts_smoke.txt /WHATIF`) from Admin Box 1 classified PTop as `ACCESS_DENIED` (admin share probe + `net view` corroboration). Evidence: `C:\ScanSnapDeployLogs\DeployScanSnap_20261006_203933.csv`. Stage/task/install were `NOT_ATTEMPTED` / `NOT_OBSERVED` (no mutation).
- No ScanSnap installer binary was present under common drop locations at first probe — package bind remains required before live mutation.

## Current blockers

1. **Admin share / auth on PTop** — need `ADMIN_SHARE_READY` for `\\CheexMcClappeth\C$` (credentials or local admin rights).
2. **Installer bind** — drop binary under `installers\`, freeze SHA256 / SilentArgs / Detect* / Bound=true from evidence only.
