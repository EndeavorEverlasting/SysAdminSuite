# Validated Software Deployment and Finalization

## Contract

The client workstation must be left with the approved requested software and its vendor-owned artifacts, not SysAdminSuite tooling or staging.

The canonical workflow is:

```text
closed deployment request
-> approved source and pinned SHA-256
-> production install wrapper
-> package-specific read-only validation
-> run-scoped SysAdminSuite teardown
-> verify zero run-scoped remnants
-> repeat package validation
-> final deployment classification
```

Use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasValidatedSoftwareDeployment.ps1 `
  -RequestPath .\survey\input\software-install\approved-request.json `
  -WhatIf
```

Transport selection is explicit when needed:

- `WinRM` preserves the existing PSSession adapter when it is separately certified.
- `SmbScheduledTask` requires one fresh matching P02 result per target and uses
  Kerberos-authenticated SMB staging plus a one-time SYSTEM task.
- `Auto` is limited to a one-target pilot and consumes a fresh P02 result. It does
  not probe, guess, or fall back during mutation.

The default remains `WinRM` for existing callers. Select `SmbScheduledTask` for a
certified target where WinRM is unavailable.

After the request, target list, installer hash, vendor arguments, and validation checks are reviewed, run the separately authorized pilot. Do not add `-Confirm:$false` during the first real pilot:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasValidatedSoftwareDeployment.ps1 `
  -RequestPath .\survey\input\software-install\approved-request.json `
  -AllowTargetMutation
```

Then double-click:

```text
Inspect-LatestValidatedSoftwareDeployment.cmd
```

## Request authority

Schema:

```text
schemas/harness/validated-software-deployment-request.schema.json
```

Example:

```text
docs/examples/validated-deployment-request.example.json
```

The request is closed and fail-closed. It requires:

- one approved package name;
- one approved UNC source root and relative installer path;
- the exact SHA-256 expected on the admin workstation;
- nonblank vendor-supported arguments and their evidence reference;
- one to twenty-five explicit approved targets;
- approver, request, change, and ticket references;
- one to sixteen bounded package-validation checks;
- the fixed cleanup policy `repo_owned_run_scoped_only`.

Live deployment refuses to start unless `-AllowTargetMutation` is present. `-WhatIf` does not read the package share or contact targets.

## Allowed validation checks

Validation is read-only and does not accept arbitrary PowerShell:

- `FileExists`
- `FileSha256Equals`
- `FileVersionEquals`
- `JsonPropertyEquals`
- `RegistryValueEquals`, restricted to exact non-secret `HKLM:` values
- `UninstallEntry`, restricted to the two standard machine uninstall roots
- `ServiceExists`, by exact service name

Wildcard paths, relative paths, arbitrary commands, secret-like registry value names, broad registry searches, and custom cleanup paths are rejected.

A required check must pass both before and after finalization. The second pass proves that removing SysAdminSuite did not remove the requested package evidence.

## Cleanup boundary

Finalization may remove only:

```text
%ProgramData%\SysAdminSuite\SoftwareInstall\<validated run id>
```

It may prune these parents only when empty:

```text
%ProgramData%\SysAdminSuite\SoftwareInstall
%ProgramData%\SysAdminSuite
```

It does not remove:

- installed application files;
- vendor MSI cache or installer logs;
- vendor services, tasks, registry values, shortcuts, or data;
- Windows logs or monitoring evidence;
- another SysAdminSuite run directory;
- any path supplied by the operator as a cleanup target.

Cleanup is idempotent and runs even after installer or validation failure. A failed package installation may therefore finish as `INSTALL_FAILED_TOOLS_REMOVED`; that is not deployment success.

## Final classifications

```text
DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED
INSTALL_FAILED_TOOLS_REMOVED
POST_INSTALL_VALIDATION_FAILED_TOOLS_REMOVED
TEARDOWN_FAILED
REQUESTED_SOFTWARE_NOT_PRESERVED
EVIDENCE_INVALID
```

Only `DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED` means all targets passed installer execution, package-specific validation, run-scoped teardown, zero-remnant verification, and post-teardown package preservation.

Application launch, reboot behavior, user workflow success, and client acceptance remain separate proof stages when required by the package.

## Evidence

Each run keeps evidence on the admin workstation only:

```text
software_install_summary.json
software_install_events.jsonl
operator_handoff.txt
software_install_finalization.json
validated_deployment_result.json
validated_deployment_review.json
```

The workstation receives no SysAdminSuite logs, reports, manifests, credentials, scheduled tasks, services, Run keys, startup entries, or hidden persistence.

For `SmbScheduledTask`, a closed worker result exists transiently inside the
run-specific staging root only long enough to be retrieved. Successful completion
requires verified task deletion and verified absence of the run root. Normal
Windows and endpoint telemetry is neither suppressed nor cleared.

## Pilot gate

Before expanding beyond one or two approved targets:

1. Verify the actual installer hash and signer against the request.
2. Run `-WhatIf` and review target count, source, mode, and arguments.
3. Confirm each package validation check is specific and observable.
4. Execute the approved pilot.
5. Inspect the validated deployment result.
6. Confirm zero SysAdminSuite remnants and preserved package evidence.
7. Perform package-specific runtime and client acceptance proof separately.
