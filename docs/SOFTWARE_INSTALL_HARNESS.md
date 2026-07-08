# Admin Software Install Harness

## Purpose

SysAdminSuite needs a controlled operator-execute lane for installing approved software from an approved read-only software source onto authorized target computers.

This lane is intentionally not stealth tooling. It must not suppress Windows logs, bypass monitoring, collect credentials, or hide the fact that an authorized install occurred. The no-artifact requirement means no persistent SysAdminSuite staging payloads should remain on the target after the run. The installed software, normal installer traces, endpoint management records, and Windows event logs are expected client records.

## Approved source

Initial approved source root:

```text
\\nt2kwb972sms01\
```

The operator supplies an installer path relative to that root, for example:

```text
SomeShare\Vendor\Package\setup.exe
```

The harness rejects installer paths that are absolute, use `..`, or do not resolve under the approved source root.

## Modes

| Mode | Target staging | Use when |
| --- | --- | --- |
| `UncDirect` | None by SysAdminSuite | The target can execute the installer directly from the approved read-only share. |
| `CopyThenInstall` | Temporary `ProgramData\SysAdminSuite\SoftwareInstall\<run_id>` | The installer must be copied from the admin box to the target before execution. |

`UncDirect` is preferred because it avoids placing the installer payload on the target. `CopyThenInstall` is allowed only when direct UNC execution is not practical. When staging is used, the wrapper removes the staging directory in a `finally` cleanup block and records cleanup status in local evidence.

## Operator contract

The install wrapper must require all of the following:

1. An explicit target list through `-ComputerName` or `-TargetsCsv`.
2. An installer path under the approved software source root.
3. Explicit `-AllowTargetMutation` unless running with `-WhatIf`.
4. Local output under `survey/output/software_install/<run_id>/` or another operator-supplied local output root.
5. Per-target status events written locally as JSONL.
6. A summary JSON that names targets, installer, mode, exit codes, staging cleanup status, and unresolved failures.

## Guardrails

The lane must preserve these boundaries:

- Authorized admin context only.
- Approved read-only software share only.
- No credential collection or embedded credentials.
- No monitoring bypass, log suppression, or event-log cleanup.
- No hidden listeners, services, agents, persistence, or background daemons.
- No broad network discovery from this operation.
- No target-side SysAdminSuite staging artifacts after completion when cleanup succeeds.
- Cleanup failure is a reportable failure, not something to hide.
- Generated run artifacts stay in gitignored local output paths.

## Expected artifacts

Each run should produce local evidence similar to:

```text
survey/output/software_install/<run_id>/
  software_install_events.jsonl
  software_install_summary.json
```

The evidence belongs on the admin box. It should be used to update the client-facing deployment tracker without writing extra audit files to target hosts.

## Example dry run

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -ComputerName WNH269OPR009 `
  -PackageName ExampleVendorTool `
  -InstallerRelativePath 'SomeShare\Vendor\Package\setup.exe' `
  -InstallerArguments @('/quiet', '/norestart') `
  -InstallMode UncDirect `
  -WhatIf
```

## Example approved execution

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -TargetsCsv .\targets\local\approved-software-targets.csv `
  -PackageName ExampleVendorTool `
  -InstallerRelativePath 'SomeShare\Vendor\Package\setup.exe' `
  -InstallerArguments @('/quiet', '/norestart') `
  -InstallMode CopyThenInstall `
  -AllowTargetMutation `
  -Confirm:$false
```

## Known operational limits

- Some installers create their own logs, caches, services, scheduled tasks, or registry keys. That is part of the software installation, not SysAdminSuite staging.
- Direct UNC execution can fail if the target cannot read the source share. Use `CopyThenInstall` when the admin box can read the share but the target cannot.
- This wrapper does not provide credentials. It relies on the operator's approved admin session and normal Windows authorization.
