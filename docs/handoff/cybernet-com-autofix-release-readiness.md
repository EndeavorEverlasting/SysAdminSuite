# Cybernet COM AutoFix release readiness

## Decision

**HOLD - DO NOT MERGE PR #156 YET.**

PR #156 is structurally mergeable, current with `main`, and clean of committed runtime evidence. Static and repository checks pass on the final code/test head, but the release gate is incomplete because the required local Windows dry-run and controlled runtime proof have not been performed on an approved, non-finalized Cybernet with the known `COM3-COM6` state.

Mergeability and green CI are not runtime proof.

## Repository and PR state

Recorded during the release-hygiene pass on 2026-07-10:

```text
repo: EndeavorEverlasting/SysAdminSuite
branch: feat/cybernet-com-port-autofix
code/test head before this note: 862a8eb6b75b98835ec2da78ebc3c60a6e908f4f
base: main at b3143ebb52271c4ac8f52cbae83779e0698f5e31
branch relation: ahead of main, 0 commits behind
PR state: open
PR mergeable: true
```

## Release-blocker fixes

The release pass verified unresolved review findings against the current code and fixed the findings that remained valid:

```text
fc8b78aa724580be649ff27e65bd33796f744613  replace net-session elevation detection
80be1d7eec7feadab4d447f92371c36ad7660fc3  reject dry-run arguments and elevate safely
377ddc13ea3bdd28f791f785a7c86435f3821ab1  keep four-port and COM3-COM6 invariants mandatory
44efa9f9801ff82143f398cb4154a629dc24b47d  enforce launcher and Force boundaries in contracts
38a08019f754392d9a13cf003ee8e7e874dcbd1e  document the locked dry-run and Force boundary
862a8eb6b75b98835ec2da78ebc3c60a6e908f4f  make the QR-pack command execute real contracts
```

Current behavior:

- Both AutoFix launchers use a Windows principal-role elevation check.
- The dry-run launcher rejects every argument, does not forward `%*`, and invokes the PowerShell script without `-Apply`, `-Restart`, or `-Force`.
- `-Force` may bypass only FINTEK detection after lead confirmation.
- Exactly four active ports and the `COM3,COM4,COM5,COM6` failed map remain mandatory invariants.
- Registry backup validation still gates all COM mutation.

## Validation evidence

GitHub checks completed successfully on the final code/test head:

```text
Survey doctrine - run 29129717426 - success
Pester          - run 29129717410 - success
```

Targeted contract commands were executed against reconstructed branch files from the current connector blobs:

```text
python Tests/survey/test_cybernet_com_autofix_contracts.py
PASS: 12 Cybernet COM AutoFix static contracts

python Tests/survey/test_cybernet_com_qr_pack_contracts.py
PASS: 5 Cybernet COM QR pack static contracts
```

Relevant current blobs:

```text
Run-CybernetComPortAutoFix.cmd
acd59508b7008bfb28e7a41bca403341a740a732

Run-CybernetComPortAutoFix-DryRun.cmd
4589937a356ff94fabdcbc15eb47290f65e4e2c4

scripts/Invoke-CybernetComPortAutoFix.ps1
c6e06d83d45c52d23fe2720af6bb7034e289e9bd

Tests/survey/test_cybernet_com_autofix_contracts.py
61221d9e82446ce28dd7f559ea5e8141c04564e8

Tests/survey/test_cybernet_com_qr_pack_contracts.py
09e2cfcca4d13eb84477983c2cb441cba6dc4995
```

The connector-only execution environment could not produce a complete local checkout, so this broader command remains an explicit skipped check rather than an inferred pass:

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

1. `scripts/Test-CybernetComPortAutoFixParser.ps1` prints `PARSE OK` on Windows.
2. `Run-CybernetComPortAutoFix-DryRun.cmd` runs locally on an approved, non-finalized Cybernet.
3. The dry run detects the intended FINTEK / four-port / `COM3-COM6` state without `-Force`.
4. All five `.reg` backups exist and are nonempty.
5. `scripts/Inspect-CybernetComPortAutoFixEvidence.ps1` verifies all required backup files are nonempty and `autofix-summary.json` reports `registry_backups.validated` as `true`.
6. Controlled apply and reboot proof confirms `COM1-COM4` under the separately approved runtime-proof lane.
7. `git status --short` remains clean after runtime artifacts are left outside the repository.

Do not merge merely because static checks and GitHub checks pass.

## Exact field command

From the SysAdminSuite repository root on the local, non-finalized Cybernet:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Do not run apply and do not use `-Force` as part of release-readiness validation.
