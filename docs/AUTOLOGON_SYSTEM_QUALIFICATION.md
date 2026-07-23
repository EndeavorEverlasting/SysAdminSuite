# AutoLogon Canonical LocalSystem Qualification

## Current disposition

The previously approved invocation is **not qualified for canonical LocalSystem deployment**.

Observed live behavior:

- `NW_AutoLogon_Setup_x64.exe` ran as LocalSystem;
- no installer arguments were supplied;
- the process returned exit code `0`;
- `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\AutoAdminLogon` was not established as `1`.

Exit code `0` therefore does not satisfy the package contract. Repeating the same hash-and-arguments invocation is forbidden.

Production catalogs keep the package identity for historical and interactive-reference purposes, but `install_enabled` and `canonical_system_install_enabled` are false. This blocks:

- the dedicated canonical AutoLogon deployment workflow;
- the AutoLogon-only package set;
- the BCA plus AutoLogon recovery set;
- the six-package Cybernet clinical workstation set.

## Chosen objective

Continue with **canonical SYSTEM qualification**, not interactive installation.

Interactive elevated installation could configure one workstation, but it would not prove compatibility with the canonical Kerberos SMB scheduled-task path. This lane qualifies a materially different package version or documented switch in the same LocalSystem execution context used by production automation.

## Technician entrypoint

From the repository root, double-click:

```text
Qualify-AutoLogonSystemPackage.cmd
```

The launcher accepts no command-line arguments and presents three bounded actions:

1. Validate a qualification request without network or target contact.
2. Run one controlled LocalSystem qualification pilot.
3. Open the latest qualification evidence.

## Prepare a candidate request

Copy:

```text
configs/software-packages/autologon-system-qualification-request.example.json
```

to:

```text
survey/input/autologon-system-qualification/<candidate-id>.json
```

Complete every placeholder. The request must identify:

- one exact authorized Cybernet FQDN;
- candidate package version;
- approved software-share root and relative candidate path;
- candidate SHA-256;
- candidate installer arguments;
- the vendor or package-owner source for those arguments;
- the failed candidate SHA-256 and arguments;
- authorization, request, change, and ticket references;
- optional Authenticode signer enforcement.

The candidate must differ from the failed invocation by SHA-256, installer arguments, or both. The launcher rejects an identical hash-and-arguments pair before target contact.

Do not enter speculative switches. A candidate argument must come from vendor documentation, package-owner guidance, a wrapper owned by the package team, or equivalent recorded evidence.

## Controlled pilot sequence

The live lane performs exactly this sequence:

1. Require Northwell network posture.
2. Resolve and hash the candidate from the approved share.
3. Validate Authenticode when requested.
4. Run a fresh narrow `kerberos_smb_task` transport preflight.
5. Run the harmless SMB scheduled-task live cert.
6. Capture a read-only AutoLogon baseline through a transient LocalSystem task.
7. Verify task deletion, task absence, staging deletion, and zero remnants.
8. Require a clean pilot baseline:
   - AutoLogon status is `not_configured`;
   - no existing `NW AutoLogon Setup` uninstall entry is present.
9. Re-run the canonical AutoLogon final-step host-eligibility and package gate using the qualification-only catalog.
10. Execute one candidate through `Invoke-SasValidatedSoftwareDeployment.ps1 -Transport SmbScheduledTask`.
11. Require source and target hashes, LocalSystem execution, result retrieval, package validation, and run-scoped teardown.
12. Capture After state through the same transient SMB task boundary.
13. Require the complete pre-reboot registry posture.
14. Emit a result and, only on success, a qualification receipt.

The workflow does not reboot and does not automatically edit either production catalog.

## Qualification success criteria

A candidate is classified `QUALIFIED_FOR_CANONICAL_SYSTEM` only when all of the following are true:

- the candidate materially differs from the failed invocation;
- one exact authorized FQDN was used;
- fresh SMB preflight passed;
- harmless transport live certification passed;
- the clean baseline was proven;
- the final-step gate passed;
- the installer ran as LocalSystem;
- installer exit code was `0` or `3010`;
- `SetAutoLogon=Autologon_YES`;
- `AutoAdminLogon=1`;
- the `DefaultPassword` value name is present without reading its data;
- `DefaultUserName` matches the workstation-name rule;
- state-collector cleanup passed;
- deployment cleanup passed;
- no repo-owned task or staging remnants remain.

A successful process exit without those postconditions is classified:

```text
CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION
```

## Clean-baseline rule

Do not test multiple candidates serially on the same altered workstation. A second candidate may inherit registry, uninstall, or package state from the first attempt and produce invalid evidence.

Each candidate requires one of:

- a fresh authorized Cybernet pilot;
- a documented reset to a proven clean baseline;
- a disposable lab VM that accurately represents the package context.

The launcher fails closed on a dirty baseline.

## Catalog promotion

Successful qualification writes:

```text
survey/output/runs/autologon-system-qualification/<run>/autologon_system_qualification_receipt.json
```

The receipt records the exact candidate:

- SHA-256;
- package version;
- installer arguments;
- installer-argument reference;
- LocalSystem execution proof;
- required registry postconditions;
- cleanup proof.

Promotion is a separate bounded change. Review the operator-local receipt, then update both production catalogs with the exact qualified hash, version, and arguments. Only that promotion change may set:

```text
install_enabled = true
canonical_system_install_enabled = true
canonical_system_qualification.status = qualified
```

Do not commit operator-local target evidence.

## Terminal classifications

- `QUALIFIED_FOR_CANONICAL_SYSTEM` — candidate met the controlled pre-reboot LocalSystem contract.
- `QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE` — request attempted to repeat the failed hash-and-arguments invocation.
- `QUALIFICATION_BLOCKED_DIRTY_BASELINE` — target already contained AutoLogon state or package evidence.
- `QUALIFICATION_FINAL_GATE_BLOCKED` — profile eligibility, catalog identity, or another mandatory final-step prerequisite failed.
- `QUALIFICATION_TRANSPORT_BLOCKED` — fresh SMB preflight or harmless live certification failed.
- `CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION` — execution completed but the required AutoLogon registry posture was absent.
- `QUALIFICATION_CLEANUP_REVIEW_REQUIRED` — task or staging teardown was not fully proven.
- `QUALIFICATION_FAILED` — another bounded gate failed.

## Proof ceiling

Qualification proves only the candidate’s controlled LocalSystem execution, required **pre-reboot** registry posture, and run-scoped cleanup.

It does not prove:

- reboot behavior;
- automatic sign-in;
- expected current-token access;
- application behavior;
- technician acceptance;
- human actor identity.

Those remain separate runtime gates after catalog promotion and a newly authorized production pilot.
