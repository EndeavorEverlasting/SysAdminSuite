# Universal field platform

SysAdminSuite field execution is based on **approved network authority and a machine-local controller runtime**, not on a particular technician laptop, Windows username, checkout folder, or one exact network ritual.

## Supported protected network angles

Target-capable features must accept any currently proven Northwell protected path:

- **hardwire / LAN** — a usable non-Wi-Fi Windows connection profile with `NetworkCategory = DomainAuthenticated`;
- **NSLIJHS-WAB** — the approved WAB Wi-Fi prefix with usable connectivity;
- **authenticated VPN** — a usable non-Wi-Fi `DomainAuthenticated` virtual/VPN interface such as Citrix Secure Access.

The physical uplink may coexist with another connection. The application evaluates the protected authority itself; it must not tell an operator to disconnect a harmless uplink merely because another approved protected path is active. Guest/Internet-only posture remains fail-closed for target operations.

## Machine-neutral execution

The canonical field front door is `scripts/Invoke-SasUniversalField.ps1`, installed by `Install-SasOperatorCommand.cmd` through `scripts/Install-SasUniversalFieldLauncher.ps1`.

Controller/runtime resolution prefers:

1. explicit `SAS_RUNTIME_ROOT` when it is a local controller surface;
2. the canonical local runtime `C:\SASAL`;
3. explicit `SAS_REPO_ROOT`;
4. the invoking local checkout or a machine-state cache.

A username-specific path is not execution authority. The platform does not scan a named user's Desktop, OneDrive, backup tree, or development folder to decide whether field operations are allowed.

The installer prefers `%ProgramData%\SysAdminSuite\bin`. If Windows permissions require a current-user shim, that shim is only a command-discovery fallback; protected runtime authority still resolves independently through the local controller/runtime rules above.

## Northwell printer mapping

Technical operators can use:

```text
sas printer
```

Non-technical technicians get the same workflow through the installed one-click CMD:

```text
Map-NorthwellPrinter.cmd
```

The universal installer places that CMD beside `sas.cmd`. The CMD trusts only that installer-owned sibling `sas.cmd` or a sibling trusted printer bootstrap when run from a current SysAdminSuite runtime. It intentionally does not run an arbitrary same-named command from the current directory or PATH, and it does **not** implement a second printer mapper.

Both entrypoints therefore retain the same protected-network gate, current runtime selection, SYSTEM-wide HKLM proof, recent-PC/printer convenience cache, resilient mapping/finalization chain, explicit operator outcomes, and bounded local admin-box run trail.

The current operator layer reports outcomes including `MAPPED NOW`, `ALREADY MAPPED`, `NOT FOUND`, `FAILED`, `READY`, and `READY NEXT LOGON`. Its local trail is stored under `%LOCALAPPDATA%\SysAdminSuite\Cache\Printer` and remains per-user, local-only, best-effort, and optional to share.

Technician tutorial: `docs/tutorials/NORTHWELL_PRINTER_MAPPING_FOR_TECHS.md`.

Advanced printer management: `START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md`.

The mapper does not use printer IP fallback and does not print a test page.

## Crash-safe AutoLogon Remote

`AutoLogon Remote` is target-mutating, so the universal `sas` command must not send it through the generic on-site deployment dispatcher. `scripts/Invoke-SasUniversalField.ps1` resolves `Bootstrap-SysAdminSuiteAutoLogon.cmd` from the machine-local runtime and invokes that sealed bootstrap for Remote. The bootstrap verifies the staged runtime/manifest and then enters `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`, which creates the registered transcript, field-run result, and latest pointer under `%LOCALAPPDATA%\SysAdminSuite`.

`AutoLogon Recover` remains recovery-only through `Run-AutoLogonOnsite.cmd Recover HOST`; it is not converted into a deployment action.

The operator execution-route harness is stricter than the installed command-discovery shim: it uses `sas repo` only to locate the sealed runtime and calls `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly. This protects field execution when an installed `sas` dispatcher is older than the currently sealed runtime.

## Local clipboard recovery

The recurring Windows clipboard failure has a first-class local recovery path. The field-proven repair primitive is:

`Get-Service cbdhsvc* | Restart-Service -Force`

SysAdminSuite keeps that exact mechanism behind two easier entry points:

- `sas clipboard` (or `sas clipboard reset`) from an installed SysAdminSuite command surface;
- `Reset-SysAdminSuiteClipboard.cmd` from the repository/runtime root for a visible double-click fallback.

The wrapper is local-only. It restarts only the current Windows Clipboard User Service instance(s) matching `cbdhsvc_*`, verifies they return to `Running`, and reports the instance names. It does not require Northwell protected-network authority and does not touch printers, AutoLogon, target hosts, or the Windows spooler.

## Do not distribute SysAdminSuite among targets

The SysAdminSuite runtime is **controller-local**. `Test-SasLocalControllerPath` rejects UNC paths and mapped network drives as runtime authority. The universal launcher records `LOCAL_MACHINE_ONLY` as the runtime scope.

Authorized deployment workflows may move their own bounded, run-scoped installer payloads and collect run-scoped evidence. The SysAdminSuite controller runtime is **not copied to target machines**: workflows must not copy `C:\SASAL`, a source checkout, the universal launcher, or the general SysAdminSuite repository onto targets as a deployment mechanism.

This keeps one controller copy authoritative instead of leaving drifting SysAdminSuite fragments distributed across workstations.

## Compatibility

The universal front door owns machine/runtime discovery and protected-path admission for network-sensitive operations, then delegates existing product workflows rather than replacing them:

- `sas network`
- `sas printer` / `Map-NorthwellPrinter.cmd` — canonical system-wide Northwell printer mapping after the same protected-path authority gate;
- `sas clipboard` — local Windows Clipboard User Service recovery;
- `sas autologon Remote HOST` — sealed crash-safe bootstrap and durable field evidence;
- `sas autologon Recover HOST` — recovery-only;
- protected `sas cybernet ...` operations;
- existing non-network-sensitive `sas` commands through the prior dispatcher.

The canonical product-level network gate still runs before target work. The platform resolver does not weaken that gate; it removes operator/path assumptions before the canonical gate runs. Local clipboard recovery is intentionally outside that network gate because it mutates only the controller's per-user clipboard service.

## Proof boundary

Repository tests prove classification and routing for sanitized hardwire, WAB, VPN, guest-only, local fixed-drive, UNC, mapped-drive, sealed AutoLogon bootstrap, and stale-dispatcher-bypass fixtures. Printer technician-launcher contracts prove that `Map-NorthwellPrinter.cmd` remains a thin delegate to the trusted printer bootstrap, is installed beside `sas.cmd`, rejects an unqualified PATH shim, and stays aligned with repository governance/tutorial routing.

On August 20, 2026, SysAdminSuite commit `4c5f1252aae24269ac1e0ab28ef9366ea08fd33f` was separately field-observed through `sas printer` on a protected `DomainAuthenticated` wired route producing SYSTEM-wide HKLM registration proof and immediate active-user materialization proof. Later mainline work added the explicit operator outcome/journal layer while preserving that mapping/finalization authority. Repository validation proves the newer composition; the one-click technician CMD still needs post-refresh field acceptance before claiming that exact wrapper was observed live. The earlier field proof does not claim physical document output without a separately observed real print.

Platform tests do not prove every specific hospital switch port, Wi-Fi access point, VPN session, target authorization, package execution, reboot, sign-in, or physical print. Live target work still owns its normal field evidence.
