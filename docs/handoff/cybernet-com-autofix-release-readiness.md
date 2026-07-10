# Cybernet COM AutoFix release readiness

## Decision

**HOLD - DO NOT MERGE PR #156 YET.**

PR #156 is structurally mergeable, current with `main`, and clean of committed runtime evidence. The release gate is not complete because the required local Windows dry-run and controlled runtime proof have not been performed on an approved, non-finalized Cybernet with the known `COM3-COM6` state.

Mergeability is not runtime proof.

## Repository and PR state

Recorded during the release-hygiene pass on 2026-07-10:

```text
repo: EndeavorEverlasting/SysAdminSuite
branch: feat/cybernet-com-port-autofix
head before this note: b7c0ea21448625e2a87d49a0dc7704428ab0288a
base: main at b3143ebb52271c4ac8f52cbae83779e0698f5e31
branch relation: 27 commits ahead, 0 behind
PR state: open
PR mergeable: true
```

## Validation evidence

Current-head GitHub checks completed successfully before this documentation-only release note:

```text
Survey doctrine - run 29128688172 - success
Pester          - run 29128688175 - success
```

Targeted static validation already recorded against the current AutoFix implementation and contract blobs:

```text
scripts/Invoke-CybernetComPortAutoFix.ps1
blob: 651bf31da507177d70f13bb63bb0c841bb75459d

Tests/survey/test_cybernet_com_autofix_contracts.py
blob: 37c458f1776ba44dff8d28f2e383898e8dcecd88

python Tests/survey/test_cybernet_com_autofix_contracts.py
PASS: 11 Cybernet COM AutoFix static contracts

python Tests/survey/test_cybernet_com_qr_pack_contracts.py
EXIT 0
```

The exact local commands requested for this sprint could not be re-executed from the connector-only environment because it could not clone the repository and did not provide a local Windows shell. The following command therefore remains an explicit local validation item rather than an inferred pass:

```bash
bash ./tests/survey/run_offline_survey_tests.sh
```

## Evidence hygiene

The PR changed-file list contains only launchers, tracked scripts, tests, configuration, documentation, and the offline test runner.

No committed PR file is a runtime `.reg` export, transcript, screenshot, hostname capture, asset list, `autofix_*` evidence directory, or machine-local log.

Expected runtime names appear only as contracts, documentation, and generated-output paths. They must remain outside git:

```text
C:\Temp\CybernetCOM\autofix_*
COMNameArbiter-before.reg
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
autofix-summary.json
autofix-transcript.txt
```

## Missing release gates

All of the following remain required before merge:

1. PowerShell parser check passes on Windows.
2. `Run-CybernetComPortAutoFix-DryRun.cmd` runs locally on an approved, non-finalized Cybernet.
3. The dry run detects the intended FINTEK / four-port / `COM3-COM6` state without `-Force`.
4. All five `.reg` backups exist and are nonempty.
5. `autofix-summary.json` reports `registry_backups.validated` as `true`.
6. Controlled apply and reboot proof confirms `COM1-COM4` only if separately approved under the runtime-proof lane.
7. `git status --short` remains clean after runtime artifacts are left outside the repository.

Do not merge merely because static checks and GitHub checks pass.

## Exact field command

From the SysAdminSuite repository root on the local, non-finalized Cybernet:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Do not run apply and do not use `-Force` as part of release-readiness validation.
