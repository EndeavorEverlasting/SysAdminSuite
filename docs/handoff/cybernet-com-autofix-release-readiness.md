# Cybernet COM AutoFix release readiness

## Decision

**HOLD - DO NOT MERGE PR #156 YET.**

PR #156 is structurally mergeable, current with `main`, and clean of committed runtime evidence. Static and repository checks pass. The release gate remains incomplete because the required dry run and controlled apply/reboot proof must occur locally on an approved, non-finalized Cybernet showing the known `COM3-COM6` state.

A normal workstation, work box, or admin box cannot satisfy this gate. The 2026-07-10 workstation inspection failed closed with all required backup/summary artifacts absent. That result validates the inspection boundary, not the COM repair behavior.

Mergeability and green CI are not runtime proof.

## Repository and PR state

Recorded during the 2026-07-10 release-hygiene refresh:

```text
repo: EndeavorEverlasting/SysAdminSuite
branch: feat/cybernet-com-port-autofix
PR: #156
base: main at b3143ebb52271c4ac8f52cbae83779e0698f5e31
code/helper head before runtime-status refresh: cde189d7faf7226c4e3d74a8f4241d92cfb1d15a
runtime-status commit: b0e6c7414727093a4b9e74ee29f34a89c41ed7d7
branch relation before this note: ahead of main, 0 commits behind
PR state: open
PR mergeable: true
```

The PR body is the authoritative location for the final head SHA after this documentation commit.

## Release-blocker fixes

The release pass verified and fixed the following boundaries:

- launchers use a Windows principal-role elevation check instead of `net session`
- dry-run rejects every argument and cannot forward `-Apply`, `-Restart`, or `-Force`
- `-Force` may bypass only FINTEK detection after separate approval
- exactly four active ports and the `COM3,COM4,COM5,COM6` failed map remain mandatory
- registry backup validation gates every COM mutation
- QR-pack contracts execute rather than returning a false-green exit
- parser verification uses PowerShell's parser API without shell interpolation
- evidence inspection refuses missing/stale state and cannot report success from a reused path variable

Key commits:

```text
fc8b78aa724580be649ff27e65bd33796f744613  replace net-session elevation detection
80be1d7eec7feadab4d447f92371c36ad7660fc3  lock dry-run argument boundary
377ddc13ea3bdd28f791f785a7c86435f3821ab1  keep mapping invariants mandatory
44efa9f9801ff82143f398cb4154a629dc24b47d  enforce launcher and Force contracts
862a8eb6b75b98835ec2da78ebc3c60a6e908f4f  execute QR-pack contracts
cde189d7faf7226c4e3d74a8f4241d92cfb1d15a  harden parser/evidence readiness helpers
b0e6c7414727093a4b9e74ee29f34a89c41ed7d7  record Cybernet-only runtime gate and field plan
```

## Validation evidence

Targeted contract commands previously passed on the tracked branch surfaces:

```text
python Tests/survey/test_cybernet_com_autofix_contracts.py
PASS: 12 Cybernet COM AutoFix static contracts

python Tests/survey/test_cybernet_com_qr_pack_contracts.py
PASS: 5 Cybernet COM QR pack static contracts
```

GitHub checks on `cde189d7faf7226c4e3d74a8f4241d92cfb1d15a`:

```text
Survey doctrine - run 29133596443 - success
Pester          - run 29133596450 - success
```

The workstation inspection also demonstrated that `scripts/Inspect-CybernetComPortAutoFixEvidence.ps1` fails closed when the latest run lacks required artifacts. It did not establish target eligibility, valid backups, COM mapping behavior, apply behavior, or reboot behavior.

## Proof level

| Proof level | Status |
|---|---|
| Contract proof | Complete |
| Harness proof | Complete for parser/evidence readiness helpers |
| Static test proof | Complete |
| Build proof | Not applicable |
| Launcher/browser proof | Incomplete |
| Command ACK proof | Partial for workstation evidence inspection |
| Behavior observed proof | Partial for fail-closed inspection behavior |
| Live runtime proof | Not reached |

## Evidence hygiene

No runtime `.reg` export, transcript, screenshot, hostname, asset list, full JSON summary, machine-local log, or `autofix_*` directory may be committed.

Expected local-only paths:

```text
C:\Temp\CybernetCOM\autofix_*
COMNameArbiter-before.reg
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
autofix-summary.json
port-mapping-plan.json
autofix-transcript.txt
```

## Missing release gates

All of the following remain required before merge:

1. `scripts/Test-CybernetComPortAutoFixParser.ps1` prints `PARSE OK` on the selected Cybernet.
2. `Run-CybernetComPortAutoFix-DryRun.cmd` runs locally on one approved, non-finalized Cybernet.
3. The dry run detects FINTEK/MultiPortSerial, exactly four active ports, and `COM3-COM6` without `-Force`.
4. All five `.reg` backups exist and are nonempty.
5. `scripts/Inspect-CybernetComPortAutoFixEvidence.ps1` prints `REGISTRY BACKUPS VALIDATED`.
6. `autofix-summary.json` reports `registry_backups.validated: true`.
7. An anonymized tracked dry-run summary is recorded without raw evidence or machine identity.
8. Separately approved apply/reboot proof confirms `COM1-COM4`.
9. `git status --short` remains clean after runtime evidence stays outside the repository.

## Exact field command

From the SysAdminSuite repository root on the local, non-finalized Cybernet:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

Do not pass arguments. Do not run apply. Do not use `-Force` during release-readiness validation.

The complete operator sequence is maintained in:

```text
docs/handoff/cybernet-com-autofix-runtime-proof.md
```
