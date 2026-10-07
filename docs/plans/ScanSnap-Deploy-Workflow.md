# ScanSnap Deploy Workflow (canonical plan)

**Branch intent:** `feat/scansnap-deploy-adminbox1-ptop-20261006`
**Execution host:** Admin Box 1 — `LPW003ASI173`
**Certification target:** PTop — `CheexMcClappeth`
**Field targets:** `WRH250STR001`, `WRH250STR002`
**Stale (do not use):** `LPW003ASI105`

## Outcome

Deterministic SysAdminSuite package under `Config/SoftwareDeploy/ScanSnap/` that validates an operator-provided installer (SHA256), classifies admin-share access, stages to `\\HOST\C$\SoftwareRepo\ScanSnap\`, executes silent install via schtasks as SYSTEM, polls result evidence, and gates success on detection — with `/WHATIF` performing zero remote mutation.

## Locked decisions

- Installer is operator-provided; no invented download URL or silent args.
- Delivery is stage + install + verify (not stage-only).
- Same protocol for PTop cert and later field hosts.
- Product name remains SysAdminSuite.

## Artifacts

| Path | Role |
|------|------|
| `Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.cmd` | Operator entrypoint |
| `Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.ps1` | Engine |
| `Config/SoftwareDeploy/ScanSnap/Bind-ScanSnapPackage.ps1` | Manifest binder |
| `Config/SoftwareDeploy/ScanSnap/hosts_smoke.txt` | `CheexMcClappeth` |
| `Config/SoftwareDeploy/ScanSnap/hosts_field.txt` | WRH hosts |
| `Config/SoftwareDeploy/ScanSnap/package.manifest.json` | Tracked unbound package template |\n| `Config/SoftwareDeploy/ScanSnap/package.local.manifest.json` | Ignored Admin Box bound package truth |
| `Config/SoftwareDeploy/ScanSnap/Runbook-ScanSnap.md` | Operator runbook |

## Phases

0. Refresh repo truth / isolated worktree from `origin/main`
1. Implement package + contract tests
2. Bind real installer on Admin Box 1
3. WhatIf against CheexMcClappeth
4. Live cert against CheexMcClappeth (`INSTALL_DETECTED`)
5. Field deploy when VPN/network ready

## Reused contracts

- Staging depot path pattern from `Config/Stage-To-Clients.ps1` / `Copy-SoftwareToClients` (scoped, no full `/MIR`)
- Remote SYSTEM execution from `mapping/Controllers/Enforce-SingleHost.ps1`
- CMD `/KEY=VALUE` style from `EnvSetup/Deploy-Shortcuts.bat`
- Optional type fingerprint assist from `Config/GoLiveTools.ps1` patterns (never auto-promoted to SilentArgs)
