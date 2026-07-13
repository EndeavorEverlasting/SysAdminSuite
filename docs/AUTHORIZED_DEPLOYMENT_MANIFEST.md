# Authorized deployment manifest

This lane recovers the useful part of PR #150: a bounded, auditable manifest in front of the canonical SysAdminSuite software-install engine.

## What it does

`Invoke-SasAuthorizedDeploymentManifest.ps1`:

1. accepts a JSON manifest with at most 100 rows and 25 unique target workstations;
2. validates every target, package, approved software-source root, relative installer path, installer argument array, SHA-256, and request/change/ticket reference before target mutation;
3. verifies the installer SHA-256 on the admin box during live execution;
4. delegates each approved row to `scripts/Invoke-SasSoftwareInstall.ps1`;
5. writes one local batch summary plus the canonical per-install child summaries.

The wrapper does not contain a second remote-install implementation. The canonical engine remains responsible for PowerShell remoting, optional `CopyThenInstall` staging, installer execution, cleanup, and per-target evidence.

## Pre-logon behavior

The deployment path uses PowerShell remoting from the admin box. It does not depend on an interactive desktop session, the Public Startup folder, or AutoLogon already being configured. A workstation may be sitting at the Windows sign-in screen as long as the approved management path, permissions, firewall policy, and software share are available.

This lane does **not** create a Windows service, scheduled task, Run key, startup-folder command, or hidden persistence. A separate explicitly approved startup-trigger sprint would be required only when machines must retry autonomously after reboot or temporary network loss.

## Manifest fields

Each JSON row requires:

- `TargetHostname`
- `PackageName`
- `SoftwareShareRoot`
- `InstallerRelativePath`
- `ExpectedSha256`
- `InstallerArguments` as a JSON string array
- `InstallMode`: `UncDirect` or `CopyThenInstall`
- `Owner`
- `RequestReference`
- `ChangeReference`
- `TicketReference`

The canonical approved source root is currently:

```text
\\nt2kwb972sms01\
```

For AutoLogon, the relative installer path is:

```text
packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe
```

Replace the example SHA-256 and references before any live execution. Do not guess silent switches. Use vendor-validated arguments.

## Request-only validation

This performs local manifest validation and invokes the canonical engine in `WhatIf` mode. It does not contact the software share or target workstations.

```powershell
.\scripts\Invoke-SasAuthorizedDeploymentManifest.ps1 `
  -ManifestPath .\examples\authorized-deployment-manifest.example.json `
  -WhatIf
```

## Approved pilot execution

Use a dedicated manifest containing no more than two approved pilot workstations. Confirm the installer hash and silent arguments first.

```powershell
.\scripts\Invoke-SasAuthorizedDeploymentManifest.ps1 `
  -ManifestPath .\targets\local\authorized-deployment-pilot.json `
  -AllowTargetMutation `
  -Confirm
```

Review:

```text
survey/output/authorized_app_deployment/<run_id>/authorized_deployment_summary.json
survey/output/authorized_app_deployment/<run_id>/operator_handoff.txt
survey/output/authorized_app_deployment/<run_id>/software_install/
```

## Expansion gate

Do not expand beyond the pilot until all of the following are true:

- the expected SHA-256 matches the package on the approved share;
- the installer arguments are vendor-validated;
- the target is reachable through the approved administrative path;
- the child software-install summary reports no unresolved cleanup failure or SysAdminSuite-owned target remnant;
- application detection confirms the intended software state;
- for AutoLogon, a controlled reboot and observed automatic sign-in have been completed separately.

## Safety boundary

- No credentials or Winlogon password values belong in the manifest or output.
- No event logs are cleared or suppressed.
- No security tooling is disabled or bypassed.
- No broad target discovery is performed.
- No target-side SysAdminSuite reports, manifests, transcripts, or evidence are intentionally retained.
- Installer-owned application files, services, registry values, logs, and caches remain outside SysAdminSuite cleanup.
