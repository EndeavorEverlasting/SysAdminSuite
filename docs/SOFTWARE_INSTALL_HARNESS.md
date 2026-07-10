# Admin Software Install Harness

## Purpose

SysAdminSuite needs a controlled operator-execute lane for installing approved software from an approved read-only software source onto authorized target computers.

This lane is intentionally not stealth tooling. It must not suppress Windows logs, bypass monitoring, collect credentials, or hide the fact that an authorized install occurred. The no-artifact requirement means no persistent SysAdminSuite-owned staging payloads, reports, manifests, transcripts, scripts, or evidence should remain on the target after the run. The installed software and the installer-owned files, logs, registry changes, caches, services, or records created by the approved executable or MSI are outside the SysAdminSuite cleanup boundary.

## Approved source

Initial approved source root:

```text
\\nt2kwb972sms01\
```

The approved root list is read from `harness/api/sas-harness-api.json`. Supplying a different UNC root, including a near-prefix match, is rejected before the share or any target is contacted.

The operator supplies an installer path relative to that root, for example:

```text
SomeShare\Vendor\Package\setup.exe
```

The harness rejects installer paths that are absolute, use `..`, or do not resolve under the approved source root.

`-WhatIf` does not test the installer on the share and does not open a remote session, copy a payload, or start an installer. It validates the request and writes local planning evidence only.

## Modes

| Mode | Target staging | Use when |
| --- | --- | --- |
| `UncDirect` | None by SysAdminSuite | The target can execute the installer directly from the approved read-only share. |
| `CopyThenInstall` | Temporary `ProgramData\SysAdminSuite\SoftwareInstall\<run_id>` | The installer must be copied from the admin box to the target before execution. |

`UncDirect` is preferred because it avoids placing the installer payload on the target. `CopyThenInstall` is allowed only when direct UNC execution is not practical. When staging is used, the wrapper removes the run-specific staging directory in cleanup and records cleanup status in local evidence.

## Target-side repo-owned artifact boundary

SysAdminSuite must not write target-side logs, reports, manifests, transcripts, scripts, or evidence for this lane. Run evidence belongs on the admin box only.

When `CopyThenInstall` is used, these paths are SysAdminSuite-owned temporary staging and must be cleaned up:

```text
%ProgramData%\SysAdminSuite\SoftwareInstall\<run_id>
%ProgramData%\SysAdminSuite\SoftwareInstall    # prune only when empty
%ProgramData%\SysAdminSuite                    # prune only when empty
```

Cleanup is attempted from both the normal remote installer `finally` block and the outer failure path that catches copy/session/install orchestration failures. A cleanup failure is a reportable failure, not something to hide. The summary must state whether a repo-owned staging path may still remain.

This cleanup boundary deliberately does not remove records owned by Windows, endpoint tooling, or the approved installer itself. The harness avoids creating SysAdminSuite-owned target evidence and cleans SysAdminSuite-owned filesystem staging; it does not erase operating-system audit logs.

## Operator contract

The install wrapper must require all of the following:

1. An explicit target list through `-ComputerName` or `-TargetsCsv`.
2. An installer path under the approved software source root.
3. Explicit `-AllowTargetMutation` unless running with `-WhatIf`.
4. Local output under the approved gitignored roots `survey/output/`, `logs/nmap/`, or `survey/artifacts/`; the default is `survey/output/software_install/<run_id>/`.
5. Per-target status events written locally as JSONL.
6. A summary JSON that names targets, installer, mode, exit codes, staging cleanup status, repo-owned target remnant status, and unresolved failures.

## Guardrails

The lane must preserve these boundaries:

- Authorized admin context only.
- Approved read-only software share only.
- No credential collection or embedded credentials.
- No monitoring bypass, log suppression, or event-log cleanup.
- No hidden listeners, services, agents, persistence, or background daemons.
- No broad network discovery from this operation.
- No target-side SysAdminSuite logs, reports, manifests, transcripts, scripts, or evidence.
- No target-side SysAdminSuite staging artifacts after completion when cleanup succeeds.
- Run-specific staging cleanup is attempted on normal and failure paths.
- A run-specific staging path is validated against the expected `%ProgramData%\SysAdminSuite\SoftwareInstall\<run_id>` boundary before recursive deletion.
- Empty SysAdminSuite parent directories are pruned when no sibling run artifacts remain.
- Cleanup failure is a reportable failure, not something to hide.
- Generated run artifacts stay in gitignored local output paths.

## Expected local artifacts

Each run should produce local evidence similar to:

```text
survey/output/software_install/<run_id>/
  software_install_events.jsonl
  software_install_summary.json
  operator_handoff.txt
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

From Git Bash on Windows:

```bash
pwsh -NoProfile -Command \
  '& ./scripts/Invoke-SasSoftwareInstall.ps1 -ComputerName WNH269OPR009 -PackageName ExampleVendorTool -InstallerRelativePath "SomeShare\Vendor\Package\setup.exe" -InstallerArguments @("/quiet", "/norestart") -InstallMode UncDirect -WhatIf'
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

From Git Bash on Windows:

```bash
pwsh -NoProfile -Command \
  '& ./scripts/Invoke-SasSoftwareInstall.ps1 -TargetsCsv ./targets/local/approved-software-targets.csv -PackageName ExampleVendorTool -InstallerRelativePath "SomeShare\Vendor\Package\setup.exe" -InstallerArguments @("/quiet", "/norestart") -InstallMode CopyThenInstall -AllowTargetMutation -Confirm:$false'
```

## Known operational limits

- Some installers create their own logs, caches, services, scheduled tasks, or registry keys. Those are part of the software installation, not SysAdminSuite staging.
- Direct UNC execution can fail if the target cannot read the source share. Use `CopyThenInstall` when the admin box can read the share but the target cannot.
- This wrapper does not provide credentials. It relies on the operator's approved admin session and normal Windows authorization.
- Remote session creation is bounded to 30 seconds, remote operations to 60 minutes, and the installer process to 30 minutes per target.
- This wrapper does not erase operating-system audit records. It is designed to avoid and clean SysAdminSuite-owned target filesystem remnants.

