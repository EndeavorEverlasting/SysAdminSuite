# Authorized deployment manifest

This lane recovers the useful part of PR #150: a bounded, auditable manifest in front of the canonical SysAdminSuite software-install engine.

## Surfaces

- `scripts/New-SasAuthorizedDeploymentManifest.ps1` performs package intake and generates a reviewable manifest.
- `scripts/Invoke-SasAuthorizedDeploymentManifest.ps1` validates that manifest and delegates each row to the canonical installer.
- `scripts/Invoke-SasSoftwareInstall.ps1` remains the only remote-install implementation.

The manifest layer does not contain a second remoting engine.

## Package intake

`New-SasAuthorizedDeploymentManifest.ps1` turns operator-supplied deployment intent into package evidence and a ready-to-review JSON manifest.

It:

1. accepts explicit target hostnames or an approved target CSV;
2. caps the result at 25 unique targets;
3. resolves the package only beneath an approved software-source root;
4. rejects rooted or parent-traversal installer paths;
5. requires explicit nonblank silent installer arguments and an `InstallerArgumentsReference` identifying the vendor document, packaging record, or approved test that supports them;
6. computes the package SHA-256;
7. records Authenticode status, signer identity when available, file size, product version, and file version;
8. emits `authorized-deployment-manifest.json`, `package-intake-summary.json`, and `operator_handoff.txt` under a gitignored output root.

Package intake does not contact target workstations and does not mutate them. It creates no service, scheduled task, startup-folder command, Run key, or other persistence.

### Request-only package-intake validation

This validates the request shape and returns before contacting the package share or writing output:

```powershell
.\scripts\New-SasAuthorizedDeploymentManifest.ps1 `
  -ComputerName 'PILOT001','PILOT002' `
  -PackageName 'NW AutoLogon Setup x64' `
  -SoftwareShareRoot '\\nt2kwb972sms01\' `
  -InstallerRelativePath 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe' `
  -InstallerArguments @('<vendor-validated-switch-1>','<vendor-validated-switch-2>') `
  -Owner 'Endpoint Engineering' `
  -RequestReference 'REQ-REPLACE-ME' `
  -ChangeReference 'CHG-REPLACE-ME' `
  -TicketReference 'TASK-REPLACE-ME' `
  -InstallerArgumentsReference 'vendor documentation or approved packaging record' `
  -WhatIf
```

### Verified package intake

This reads the approved package, computes the real SHA-256, captures signature/version evidence, and writes a local manifest. It still does not contact any workstation:

```powershell
$intake = .\scripts\New-SasAuthorizedDeploymentManifest.ps1 `
  -ComputerName 'PILOT001','PILOT002' `
  -PackageName 'NW AutoLogon Setup x64' `
  -SoftwareShareRoot '\\nt2kwb972sms01\' `
  -InstallerRelativePath 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe' `
  -InstallerArguments @('<vendor-validated-switch-1>','<vendor-validated-switch-2>') `
  -Owner 'Endpoint Engineering' `
  -RequestReference 'REQ-REPLACE-ME' `
  -ChangeReference 'CHG-REPLACE-ME' `
  -TicketReference 'TASK-REPLACE-ME' `
  -InstallerArgumentsReference 'vendor documentation or approved packaging record' `
  -OutputRoot .\survey\output\authorized_package_intake `
  -Confirm:$false

$intake.manifest_path
$intake.sha256
$intake.signature_status
```

Use `-RequireValidSignature` only when the approved package is expected to carry a valid Authenticode signature. An unsigned internal wrapper must be reviewed and dispositioned rather than silently represented as signed.

## Deployment adapter

`Invoke-SasAuthorizedDeploymentManifest.ps1`:

1. accepts a JSON manifest with at most 100 rows and 25 unique target workstations;
2. validates every target, package, approved software-source root, relative installer path, installer argument array, SHA-256, and request/change/ticket reference before target mutation;
3. verifies the installer SHA-256 on the admin box during live execution;
4. delegates each approved row to `scripts/Invoke-SasSoftwareInstall.ps1`;
5. writes one local batch summary plus the canonical per-install child summaries.

The recovered manifest lane currently fails closed on `CopyThenInstall`. PR #150's review correctly identified that a copied installer must be hashed again on the target before execution. Until that proof is added to the canonical engine, this adapter permits only `UncDirect` so it cannot execute an unverified staged copy.

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
- `InstallMode`: currently `UncDirect` only
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

Do not guess silent switches. Use vendor-validated arguments and record the evidence source through `InstallerArgumentsReference` during package intake. Confirm that the remote execution context can read the approved UNC path before the pilot.

## Request-only deployment validation

This performs Request-only validation on the generated manifest and invokes the canonical engine in `WhatIf` mode. It does not contact the software share or target workstations.

```powershell
.\scripts\Invoke-SasAuthorizedDeploymentManifest.ps1 `
  -ManifestPath $intake.manifest_path `
  -WhatIf
```

## Approved pilot execution

Use a dedicated generated manifest containing no more than two approved pilot workstations.

```powershell
.\scripts\Invoke-SasAuthorizedDeploymentManifest.ps1 `
  -ManifestPath $intake.manifest_path `
  -AllowTargetMutation `
  -Confirm
```

Review:

```text
survey/output/authorized_package_intake/<run_id>/package-intake-summary.json
survey/output/authorized_package_intake/<run_id>/authorized-deployment-manifest.json
survey/output/authorized_app_deployment/<run_id>/authorized_deployment_summary.json
survey/output/authorized_app_deployment/<run_id>/operator_handoff.txt
survey/output/authorized_app_deployment/<run_id>/software_install/
```

## Expansion gate

Do not expand beyond the pilot until all of the following are true:

- the package-intake SHA-256 matches the package on the approved share;
- signature status and publisher identity have been reviewed;
- installer arguments are vendor-validated and their evidence reference is recorded;
- the target is reachable through the approved administrative path;
- the remote execution context can read the approved UNC package path without an interactive user logon;
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
