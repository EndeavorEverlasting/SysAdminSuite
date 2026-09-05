# Cursor Workstation Lifecycle

## Purpose

This is the progressive-disclosure authority for **local Windows Cursor installation, uninstall, broken-uninstaller recovery, clean system-wide reinstall, and verification** in SysAdminSuite.

Load this document only when the request is specifically about Cursor on a developer workstation. The generic Developer Workstation skill remains the routing owner. The application behavior lives in `scripts/Invoke-SasCursorWorkstation.ps1`; this document explains when and why to select each operation.

This lane does **not** replace the admin-box remote software-install harness, package-analysis workflows, Northwell endpoint deployment, or a vendor/service-status investigation. It owns the local workstation installation state only.

## The failure class this use case preserves

A Cursor problem is not automatically a remote service problem. Local evidence has priority when Windows shows installation inconsistency.

The field-proven local failure signature that motivated this profile was:

- more than one Cursor registration in **Settings > Apps > Installed apps**;
- a mixture of old/current or `Cursor (User)` registrations;
- the active installation rooted under `%LOCALAPPDATA%\Programs\cursor`;
- uninstall failure referencing `unins000.dat` with **Error 32** because another process held the installer/uninstaller file;
- a clean result only after Cursor processes, install roots, uninstall registrations, startup/shortcut/PATH residue, and intentionally selected user state were removed, followed by a reboot;
- a successful fresh **system** installation afterward.

Those observations are local installation evidence. When they are present, do not derail the operator into server-status speculation before completing the local audit and recovery decision.

Conversely, a clean canonical local system install plus a successful application launch does not prove vendor services are healthy. If the remaining symptom is network/API/service behavior after local state is clean, the problem may then route to external service-status or network diagnosis.

## Canonical front door

Use the tracked launcher from a current SysAdminSuite checkout:

```text
Manage-Cursor.cmd
```

The launcher delegates to:

```text
scripts/Invoke-SasCursorWorkstation.ps1
```

The canonical profile is:

```text
Config/cursor-workstation-profile.json
```

Runtime evidence is local and untracked under `%LOCALAPPDATA%\SysAdminSuite\field-runs\cursor\<run-id>\cursor_workstation_result.json` unless the operator deliberately supplies another output root. Never commit these machine-local results.

## Operations

| Operation | Mutation | Intent |
| --- | --- | --- |
| `Audit` | No application mutation | Enumerate Cursor uninstall registrations, install roots, Cursor-owned processes, CLI resolution, user-state roots, and classify the local state. |
| `Verify` | No application mutation | Assert `Absent`, `System`, or simply report the observed state. |
| `Uninstall` | Yes; requires elevation and `-AllowMutation` | Stop Cursor-owned processes and invoke registered uninstallers. Preserves user settings/state. |
| `RecoveryPurge` | Yes; requires elevation and `-AllowMutation` | Recover from duplicate/stale registrations, missing or locked uninstallers, mixed user/system installs, or uninstall residue. User state is preserved unless `-PurgeUserState` is explicitly supplied. |
| `InstallSystem` | Yes; requires elevation and `-AllowMutation` | Install from an operator-downloaded official Cursor **system** installer after a clean absent baseline. |

`RecoveryPurge` is not the ordinary uninstall path. Use `Uninstall` first when the registered uninstaller is coherent. Escalate when the audit or failed uninstall proves the registration/install state is broken.

## Clean-recovery sequence

For a broken local installation, the canonical sequence is:

```powershell
.\Manage-Cursor.cmd Audit
.\Manage-Cursor.cmd RecoveryPurge -AllowMutation -PurgeUserState
```

Then **reboot Windows**. The lifecycle engine intentionally does not reboot the workstation for the operator.

After reboot, prove the clean baseline before downloading or executing another installer:

```powershell
.\Manage-Cursor.cmd Verify -ExpectedState Absent
```

If verification fails, do not reinstall over the residue. Run `Audit`, inspect the exact remaining registration/path/process/command evidence, and repair only that boundary.

## System-wide installation contract

SysAdminSuite does not use `winget`, Chocolatey, or another package manager for this Cursor use case. The operator obtains the **Windows system installer** from the profile-owned official download location:

```text
https://cursor.com/download
```

Then run:

```powershell
.\Manage-Cursor.cmd InstallSystem -InstallerPath 'C:\path\to\CursorSetup.exe' -AllowMutation
```

Before execution, the engine requires all of the following:

1. Cursor is proven absent by local inventory.
2. The selected file is not named like the Cursor user installer.
3. The filename is admitted by the system-installer profile.
4. Windows Authenticode reports a valid signature.
5. The signing certificate subject matches the expected Anysphere publisher identity.
6. The installer SHA-256 is recorded in local runtime evidence.

The engine does not invent silent installer arguments. If a future approved installer requires arguments, the operator must supply them explicitly through `-InstallerArguments` after verifying the vendor contract.

After installation:

```powershell
.\Manage-Cursor.cmd Verify -ExpectedState System
```

The expected local state is machine-install evidence without a concurrent user-scoped Cursor installation.

## Smoke test before state restoration

A verified registry/filesystem installation is not proof that the GUI or account/session works. Launch the freshly installed Cursor application and prove that it opens and remains usable **before** restoring settings, extensions, settings sync, or copied `.cursor` state.

This ordering preserves causal evidence. If pristine Cursor works and the problem returns only after old state is restored, the regression belongs to restored state rather than the installer. If pristine Cursor fails before restoration, keep the old state out of the diagnosis.

## What `RecoveryPurge` may remove

The purge is tightly bounded to the canonical Cursor profile. It may stop `Cursor.exe` and executables running from known Cursor install roots; remove known machine/user Cursor install roots; remove uninstall keys whose display name matches the Cursor application profile; remove Cursor startup values, Cursor shortcuts, and exact Cursor CLI PATH entries; and, only with `-PurgeUserState`, remove the profile-owned Cursor state roots.

It must not remove VS Code, Git configuration, repositories, arbitrary application registrations, unrelated PATH entries, browser data, other developer tools, Windows event logs, or monitoring/audit records.

A locked `unins000.dat` or `unins000.exe` is handled by terminating Cursor-owned processes before bounded removal. Do not broaden process termination to unrelated applications just because an uninstall is blocked.

## Agent anti-regression rules

When Cursor local setup is the stated problem, agents should load this document and the Cursor profile before proposing repair. Preserve these decisions:

1. **Audit before hypothesis expansion.** Duplicate registrations, mixed scopes, stale directories, path residue, or Error 32 are local evidence and must be addressed before assuming a vendor outage.
2. **Prefer registered uninstall first.** A healthy registration gets the normal uninstall path; broken residue gets the explicit recovery path.
3. **System installer is canonical for clean reinstall.** Do not silently fall back to `Cursor (User)` because it is convenient.
4. **Recovery purge is explicit and bounded.** It requires elevation and `-AllowMutation`; user state requires the additional `-PurgeUserState` switch.
5. **Reboot is a separate operator step after broken-install purge.** Do not claim the pre-reboot state proves Windows has released every file/registration cache.
6. **Verify absent before reinstall, verify system after reinstall.** Do not stack another Cursor install onto unresolved residue.
7. **Smoke pristine application before restoring state.** Settings/extensions/sync restoration belongs after basic launch proof.
8. **Do not confuse proof levels.** A green repository contract is not a live workstation purge; a clean inventory is not GUI proof; a working GUI is not proof that vendor services are healthy.

## Proof ceilings

Repository/schema/contract validation can prove that the Cursor profile, mutation gates, bounded removal surfaces, launcher, and progressive-disclosure doctrine agree. Windows CI can prove PowerShell parsing and read-only `Audit`/`Verify` behavior on a clean runner.

Only an authorized live Windows run can prove that a particular workstation was purged, rebooted, reinstalled, and launched successfully. The successful workstation incident that inspired this profile is reusable operational evidence, not a substitute for each future workstation's own result.
