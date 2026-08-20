# Universal field platform

SysAdminSuite field execution is based on **approved network authority and a machine-local controller runtime**, not on a particular technician laptop, Windows username, checkout folder, or one exact network ritual.

## Supported protected network angles

Target-capable features must accept any currently proven Northwell protected path:

- **hardwire / LAN** — a usable non-Wi-Fi Windows connection profile with `NetworkCategory = DomainAuthenticated`;
- **NSLIJHS-WAB** — the approved WAB Wi-Fi prefix with usable connectivity;
- **authenticated VPN** — a usable non-Wi-Fi `DomainAuthenticated` virtual/VPN interface such as Citrix Secure Access.

The physical uplink may coexist with another connection. The application evaluates the protected authority itself; it must not tell an operator to disconnect a harmless uplink merely because another approved protected path is active.

Guest/Internet-only posture remains fail-closed for target operations.

## Machine-neutral execution

The canonical field front door is `scripts/Invoke-SasUniversalField.ps1`, installed by `Install-SasOperatorCommand.cmd` through `scripts/Install-SasUniversalFieldLauncher.ps1`.

Controller/runtime resolution prefers:

1. explicit `SAS_RUNTIME_ROOT` when it is a local controller surface;
2. the canonical local runtime `C:\SASAL`;
3. explicit `SAS_REPO_ROOT`;
4. the invoking local checkout or a machine-state cache.

A username-specific path is not execution authority. The platform does not scan a named user's Desktop, OneDrive, backup tree, or development folder to decide whether field operations are allowed.

The installer prefers `%ProgramData%\SysAdminSuite\bin`. If Windows permissions require a current-user shim, that shim is only a command-discovery fallback; protected runtime authority still resolves independently through the local controller/runtime rules above.

## Do not distribute SysAdminSuite among targets

The SysAdminSuite runtime is **controller-local**. `Test-SasLocalControllerPath` rejects UNC paths and mapped network drives as runtime authority. The universal launcher records `LOCAL_MACHINE_ONLY` as the runtime scope.

Authorized deployment workflows may move their own bounded, run-scoped installer payloads and collect run-scoped evidence. They must not copy `C:\SASAL`, a source checkout, the universal launcher, or the general SysAdminSuite repository onto target machines as a deployment mechanism.

This keeps one controller copy authoritative instead of leaving drifting SysAdminSuite fragments distributed across workstations.

## Compatibility

The universal front door owns machine/runtime discovery and protected-path admission for network-sensitive operations, then delegates existing product workflows rather than replacing them:

- `sas network`
- `sas printer` — launches the canonical system-wide Northwell printer mapper after the same protected-path authority gate;
- `sas autologon Remote HOST`
- `sas autologon Recover HOST`
- protected `sas cybernet ...` operations
- existing non-network-sensitive `sas` commands through the prior dispatcher

The canonical product-level network gate still runs before target work. The new platform resolver does not weaken that gate; it removes operator/path assumptions before the canonical gate runs.

## Proof boundary

Repository tests prove classification and routing for sanitized hardwire, WAB, VPN, guest-only, local fixed-drive, UNC, and mapped-drive fixtures. They do not prove a specific hospital switch port, Wi-Fi access point, VPN session, target authorization, printer queue, package execution, or reboot. Live target work still owns its normal field evidence.
