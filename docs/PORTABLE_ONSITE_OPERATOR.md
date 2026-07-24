# Portable On-Site Operator Command

## Purpose

Remove per-PC/per-user path editing from SysAdminSuite field work while keeping target operations fail-closed on Guest or otherwise unapproved network posture.

The portable command is user-local. It does not require administrator rights and does not change Wi-Fi profiles or credentials.

## One-time setup per Windows user / PC

From any local SysAdminSuite checkout, double-click:

```text
Install-SasOperatorCommand.cmd
```

The installer:

1. copies the portable dispatcher to `%LOCALAPPDATA%\SysAdminSuite\bin`;
2. caches the current repository root in `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`;
3. adds the user-local bin directory to the current user's `PATH`;
4. does not write machine-wide PATH or require elevation.

Open a new terminal after installation.

## Daily field commands

```text
sas
sas repo
sas open
sas network
sas autologon
sas cybernet Plan HOST
sas cybernet Apply HOST
sas cybernet Validate HOST
```

`SasPortableLauncher.ps1` resolves the repo in this order:

1. `SAS_REPO_ROOT` when explicitly set;
2. the user-local cached repo root;
3. the Git root containing the current terminal directory;
4. common `%USERPROFILE%`, Desktop/dev, OneDrive, and nested `OG Laptop Backup\Desktop\dev\SysAdminSuite` layouts.

No Windows username is baked into the launcher.

## AutoLogon on Guest

Run:

```text
sas autologon
```

The on-site menu exposes:

- Prepare/edit qualification request — Guest-safe.
- Validate qualification request — Guest-safe and performs no target contact.
- Controlled LocalSystem pilot — requires approved Northwell network posture.
- Open latest qualification evidence.

If no request exists, the launcher copies the tracked example to:

```text
survey\input\autologon-system-qualification\qualification-request.local.json
```

and opens it in Notepad. `survey/input/*` is ignored by git, so live site, ticket, hostname, hash, and authorization values remain operator-local.

The template still requires a materially different approved AutoLogon candidate. The launcher does not invent installer switches, hashes, or authorization references.

## Guest-to-Northwell transition

Before live AutoLogon qualification, Cybernet Apply, or Cybernet Validate, `Confirm-SasNorthwellNetwork.ps1` classifies only local network evidence.

When approved posture is not detected, the operator receives these bounded choices:

```text
[R] I switched networks - recheck now
[W] Open Windows Wi-Fi settings, then recheck
[C] Cancel this target operation
```

The script never calls `netsh wlan connect`, adds a Wi-Fi profile, changes credentials, scans a subnet, contacts a target, or mutates a target while blocked.

Choosing Cancel exits before target contact. Choosing Wi-Fi settings opens Windows settings; the technician performs the actual network switch, confirms, and the gate rechecks fresh local evidence.

## Cybernet batch boundary

`Run-CybernetBatchConfiguration.cmd` gates Apply and Validate before target contact. Plan remains local-only.

The underlying `Hardware/Cybernet/Invoke-CybernetBatchConfiguration.ps1` also enforces the same gate for direct PowerShell / CSV batch invocation, so bypassing the root CMD does not bypass the Guest-network stop.

Fixture mode remains offline and does not require network posture.
