# Software Install Result Inspection

## Purpose

`Inspect-LatestSoftwareInstall.cmd` replaces the manual PowerShell sequence for locating the latest software-install run, reading its handoff, parsing its summary, and formatting every target result.

The inspector is mandatory presentation logic. It does not perform an installation and it does not contact a target or software share.

## Technician entrypoint

From the SysAdminSuite repository, double-click:

```text
Inspect-LatestSoftwareInstall.cmd
```

The launcher finds the latest run beneath:

```text
survey\output\software_install\
```

For automation or an explicit evidence location:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Show-SasSoftwareInstallResult.ps1 `
  -RunRoot .\survey\output\software_install\<run_id>
```

The script writes:

```text
software_install_review.json
```

inside the selected run directory and prints a concise classification plus a per-target table.

## Required logical moments

Agents and operator workflows invoke the inspector:

1. immediately after `Invoke-SasSoftwareInstall.ps1` returns;
2. after recovering an interrupted software-install run;
3. before answering whether deployment succeeded;
4. before expanding from a pilot to additional targets;
5. before PR, sprint, release, or operator closeout that cites software installation.

The classification and target table must be presented to the user. Do not replace them with “exit code 0” or a generic success sentence.

## Classifications and exit codes

| Classification | Exit | Meaning |
|---|---:|---|
| `INSTALLER_EXECUTION_COMPLETE_POST_INSTALL_VERIFICATION_REQUIRED` | 0 | Every target reported installer completion and SysAdminSuite cleanup evidence is consistent. Application-specific verification is still required. |
| `PLAN_ONLY_NO_INSTALL` | 10 | A WhatIf plan was produced; no installation occurred. |
| `INSTALL_FAILED` | 20 | At least one target failed or remained unresolved. |
| `PARTIAL_OR_MIXED_RESULT` | 20 | Results contain a mixed or incomplete state. |
| `CLEANUP_REVIEW_REQUIRED` | 21 | Cleanup failed or repo-owned target remnants may remain. |
| `EVIDENCE_INVALID` | 22 | Required files, JSON, JSONL, or recomputed counts are inconsistent. |
| `NO_RUN_FOUND` | 23 | No inspectable run exists at the requested location. |

## Proof boundary

A successful inspection proves only:

- the local evidence package is internally consistent;
- the installer process reported completion for every target;
- the recorded installer exit code and cleanup state are available;
- no SysAdminSuite-owned target remnant was reported.

It does not prove the application is installed correctly, launches, exposes the expected version, runs its service, completes a business workflow, or has client acceptance. Those checks remain package-specific post-install verification.
