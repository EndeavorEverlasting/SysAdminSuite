# AutoLogon on-site production gate

## Purpose

Use this runbook when a technician is physically on site and needs the next safe action toward live AutoLogon production deployment.

This document is a field gate, not a replacement for the detailed contracts in:

- `docs/AUTOLOGON_SYSTEM_QUALIFICATION.md`
- `docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md`
- `docs/AUTOLOGON_PHYSICAL_PILOT_CHECKLIST.md`

The repository and generated operator-local evidence remain the source of truth.

## Current production disposition

**Do not run a live canonical AutoLogon production deployment yet.**

The currently pinned `NW_AutoLogon_Setup_x64.exe` no-argument invocation was executed as LocalSystem and returned exit code `0`, but it did not establish the required `AutoAdminLogon=1` postcondition.

The production catalog therefore keeps:

```text
install_enabled = true
canonical_system_install_enabled = false
canonical_system_qualification.status = failed_runtime_validation
```

The package remains visible for inventory, fixtures, and `-WhatIf` planning. Real canonical worker generation is blocked before target mutation.

Repeating the same failed installer SHA-256 plus argument set is not an authorized qualification attempt.

## On-site launch order

### 1. Synchronize to the reviewed repository state

From an existing clean SysAdminSuite clone:

```powershell
Set-Location C:\path\to\SysAdminSuite
git fetch --all --prune
git switch main
git pull --ff-only

git status --short
git log -1 --oneline
```

Do not discard local work to obtain a clean tree. If the primary clone contains owned changes, use a separate clean worktree or clone for the field run.

### 2. Confirm the production gate before touching a target

Verify the catalog still blocks canonical SYSTEM execution:

```powershell
$Catalog = Get-Content .\configs\software-packages\approved-apps.json -Raw | ConvertFrom-Json
$AutoLogon = @($Catalog.packages | Where-Object id -eq 'autologon')

$AutoLogon | Select-Object `
  id, install_enabled, canonical_system_install_enabled, readiness, `
  @{n='qualification_status';e={$_.canonical_system_qualification.status}}
```

Required current result:

```text
id                               autologon
install_enabled                  True
canonical_system_install_enabled False
readiness                        installer_and_no_arguments_confirmed
qualification_status             failed_runtime_validation
```

If `canonical_system_install_enabled` is already `true`, stop and inspect the exact promotion commit and qualification receipt before proceeding. Do not assume a catalog change is valid merely because the flag changed.

### 3. Identify a materially different qualification candidate

A candidate must differ from the failed invocation by installer SHA-256, approved installer arguments, or both.

Acceptable argument evidence includes vendor documentation, package-owner guidance, or an approved wrapper owned by the package team. Do not invent or guess switches.

Copy the tracked template:

```powershell
New-Item -ItemType Directory -Force `
  .\survey\input\autologon-system-qualification | Out-Null

Copy-Item `
  .\configs\software-packages\autologon-system-qualification-request.example.json `
  .\survey\input\autologon-system-qualification\candidate.json
```

Populate the operator-local request with one exact authorized Cybernet FQDN, the candidate package version, approved share-relative package path, exact SHA-256, approved arguments, argument evidence, failed-candidate identity, and current authorization/change references.

Do not place credentials, password data, real target identifiers, or private software-share details in tracked files, screenshots, commits, or chat transcripts.

### 4. Run the bounded qualification launcher

From the repository root, double-click:

```text
Qualify-AutoLogonSystemPackage.cmd
```

Use the menu in this order:

1. validate the candidate request locally;
2. run one controlled LocalSystem qualification pilot on one clean authorized target;
3. open the latest qualification evidence.

The qualification lane performs fresh Kerberos/SMB preflight, harmless transport live certification, clean-baseline proof, the final-step gate, one canonical LocalSystem package execution, required pre-reboot registry checks, and run-scoped cleanup verification.

Do not serially test multiple candidates on the same changed workstation.

## Qualification completion gate

Proceed only when the result classification is exactly:

```text
QUALIFIED_FOR_CANONICAL_SYSTEM
```

A process exit code of `0` or `3010` is necessary but not sufficient.

The qualification must also prove all required pre-reboot postconditions, including:

- `SetAutoLogon=Autologon_YES`;
- `AutoAdminLogon=1`;
- `DefaultPassword` value-name presence without reading its data;
- expected workstation-account match;
- LocalSystem execution;
- source/target hash agreement;
- state-collector cleanup;
- deployment cleanup;
- zero SysAdminSuite task/staging remnants.

A successful qualification writes an operator-local receipt under:

```text
survey/output/runs/autologon-system-qualification/<run>/autologon_system_qualification_receipt.json
```

Do not commit the operator-local receipt.

## Catalog promotion gate

Qualification does **not** automatically enable production.

After a successful qualification, create a bounded catalog-promotion change that updates both production catalogs with the exact qualified package version, SHA-256, installer arguments, and receipt-derived qualification identity.

Only that reviewed promotion may set:

```text
canonical_system_install_enabled = true
canonical_system_qualification.status = qualified
```

Run the owning AutoLogon/system-qualification contracts and required repository validators on the promotion head before merge.

## First live production pilot after promotion

Only after the qualification receipt is reviewed and the exact promotion commit is merged:

1. use one exact authorized FQDN;
2. run fresh `kerberos_smb_task` preflight;
3. run AutoLogon `-WhatIf` against the same reviewed inputs;
4. run the dedicated AutoLogon fixture E2E;
5. execute one attended production pilot through `scripts\Invoke-SasAutoLogonDeployment.ps1` with `-AllowTargetMutation`;
6. inspect the public-safe result with `Inspect-LatestAutoLogon.cmd -RequireDeploymentSucceeded`;
7. require cleanup and zero-remnant proof before any reboot;
8. perform the approved attended reboot separately;
9. directly observe automatic sign-in;
10. run current-token session-access proof from the actual AutoLogon desktop;
11. run the approved technician application-behavior proof;
12. obtain operator/product-owner acceptance before expanding beyond one workstation.

Do not use the older WinRM installer as a fallback for AutoLogon. Do not bypass the final-step gate. Do not add `-Confirm:$false` to field runbook commands.

## Stop classifications

Stop expansion and preserve the operator-local run root for any result other than the exact positive gate required for the current stage, including:

- `QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE`;
- `QUALIFICATION_BLOCKED_DIRTY_BASELINE`;
- `QUALIFICATION_FINAL_GATE_BLOCKED`;
- `QUALIFICATION_TRANSPORT_BLOCKED`;
- `CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION`;
- `QUALIFICATION_CLEANUP_REVIEW_REQUIRED`;
- `QUALIFICATION_FAILED`;
- deployment cleanup or zero-remnant failure;
- runtime/session/application proof failure.

Do not blindly retry, broaden transport, delete evidence, or treat process completion as proof of configuration.

## Immediate post-AutoLogon dependency

After the one-target AutoLogon runtime and acceptance gates pass, continue with the Cybernet workstation profile as a separate bounded workflow. Shared laptops and other standard profiles remain separate profile lanes and must not inherit AutoLogon unless their profile contract explicitly authorizes it.
