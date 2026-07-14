# Cybernet COM AutoFix release readiness

## Decision

**HOLD - DO NOT MERGE UNTIL THE TARGETED CHECKS AND ONE CONTROLLED CYBERNET PROOF ARE REVIEWED.**

PR #165 is the clean release-integration lane for the Cybernet COM repair tools. It supersedes PR #156, which remains useful only as development history. Mergeability and green static checks are not live runtime proof.

## Repository and PR state

```text
repo: EndeavorEverlasting/SysAdminSuite
branch: feat/cybernet-com-port-release
PR: #165
base: main at fbbb669b0ae5e6e5281988e735e486f36e1b1c0b
head: current PR head; use GitHub PR metadata as the authoritative SHA
branch relation at clean-base creation: ahead of main, 0 commits behind
PR state: open
```

The current PR body records the latest head SHA, review fixes, checks, and branch relation after each update.

## Shipped repo surfaces

```text
Run-CybernetComPortHelp.cmd
Run-CybernetComPortAutoFix-DryRun.cmd
Run-CybernetComPortAutoFix.cmd
Run-CybernetComPortQrPack.cmd
scripts/Start-CybernetComPortAutoFix.ps1
scripts/Invoke-CybernetComPortAutoFix.ps1
scripts/Test-CybernetComPortAutoFixParser.ps1
scripts/Inspect-CybernetComPortAutoFixEvidence.ps1
scripts/Show-CybernetComPortHelp.ps1
```

The QR pack is version `1.1.0` and exposes the guarded AutoFix launcher as step 12.

## Enforced boundaries

- technician launchers reject arguments rather than forwarding arbitrary switches;
- elevation is handled by a tracked PowerShell helper that waits for the elevated child and propagates its exit code;
- launchers honor the host's configured PowerShell execution policy;
- `-Force` remains available only through direct, separately approved script use and cannot bypass the four-port or COM3-COM6 invariants;
- exactly four active `Communications Port` devices and the `COM3,COM4,COM5,COM6` failed map are mandatory;
- COM Name Arbiter and all four active-device `Device Parameters` keys must export successfully to nonempty `.reg` files before mutation;
- a failed `reg.exe add` COM Name Arbiter reset stops before any `PortName` write;
- already-correct COM1-COM4 runs are accepted as no-op evidence and do not falsely require backup files;
- no remote execution, admin-box target mutation, SmartLynx/final app installation, or USB/COM driver replacement is included.

## Validation contract

The dedicated `Cybernet COM AutoFix` workflow runs:

```powershell
python .\Tests\survey\test_cybernet_com_autofix_contracts.py
python .\Tests\survey\test_cybernet_com_arbiter_reset_contract.py
pwsh -NoProfile -File .\tools\Test-Pester5Suite.ps1 -TestPath .\Tests\Pester\CybernetComPortAutoFixReadiness.Tests.ps1
.\scripts\Test-CybernetComPortAutoFixParser.ps1
.\scripts\Show-CybernetComPortHelp.ps1 -Topic status
```

The authoritative check result is the latest workflow run attached to PR #165. The broader repository Pester workflow is tracked separately and must not be mistaken for live target proof.

## Proof levels

| Proof level | Status |
|---|---|
| Contract proof | Implemented in dedicated Python contracts |
| Parser proof | Implemented through the parser helper and focused workflow |
| Readiness-helper proof | Implemented in focused Pester tests |
| Technician help smoke | Implemented in focused workflow |
| Dry-run proof on eligible Cybernet | Not reached |
| Registry backup proof on eligible Cybernet | Not reached |
| Controlled apply/reboot proof | Not reached |
| COM1-COM4 persistence proof | Not reached |

## Evidence hygiene

Never commit runtime `.reg` exports, transcripts, screenshots, hostnames, asset lists, full JSON summaries, machine-local logs, or `autofix_*` directories.

Expected local-only paths include:

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

1. Select exactly one approved, non-finalized Cybernet with the known COM3-COM6 state.
2. Confirm the parser helper prints `PARSE OK`.
3. Run the dry-run launcher without arguments.
4. Confirm FINTEK/MultiPortSerial, exactly four active ports, and the COM3-COM6 map without `-Force`.
5. Confirm all five `.reg` backups are nonempty.
6. Confirm the evidence inspector prints `REGISTRY BACKUPS VALIDATED`.
7. Record an anonymized dry-run summary without raw machine identity.
8. Separately approve and run apply/reboot.
9. Confirm COM1-COM4 persists after reboot before final app binding.
10. Keep `git status --short` clean because runtime evidence remains outside the repo.

## Exact dry-run commands

### Command Prompt

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

### PowerShell

```powershell
& .\Run-CybernetComPortAutoFix-DryRun.cmd
```

### Bash on Windows

```bash
cmd.exe /d /c Run-CybernetComPortAutoFix-DryRun.cmd
```

Run without arguments. This lane performs evidence capture and planning only; apply and `-Force` are not part of release-readiness validation.

The full operator sequence is maintained in `docs/handoff/cybernet-com-autofix-runtime-proof.md`.
