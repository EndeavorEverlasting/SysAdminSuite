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
- Admin share `\\CheexMcClappeth\C$` (and `.local` / IP variants) was **not** available at first probe — classify as `UNREACHABLE` until share/auth is fixed.
- No ScanSnap installer binary was present under common drop locations at first probe — package bind remains required before live mutation.
