# AutoLogon Hardwired Local Repair

Use this lane only when all repository acquisition already happened earlier, an exact detached SysAdminSuite worktree is present on the Admin Box, the operator is now on an approved DomainAuthenticated non-Wi-Fi Northwell connection, and the sealed `C:\SASAL` runtime must be repaired before AutoLogon deployment.

This is not a replacement for `sas refresh`. Normal repository acquisition and remote Git remain Guest/Internet-only. The hardwired repair lane performs **no Git command, no GitHub access, and no remote repository access**. It copies the paths from the previous sealed runtime manifest plus the four explicitly declared files introduced by this repair lane, verifies source/runtime SHA-256 parity with .NET, refreshes the installed `sas` shim, records an explicit hardwired-repair manifest, and then enters the existing crash-safe AutoLogon-only transaction.

## Entry point

From the exact detached local worktree:

```cmd
Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT
```

The command fails before runtime copy or target contact unless:

- the source is a local drive path;
- the source `.git/HEAD` metadata resolves directly to the full expected detached commit without invoking Git;
- the previous `autologon-short-runtime.json` exists and proves the runtime had its remotes removed and protected Git network disabled;
- a live DomainAuthenticated non-Wi-Fi Windows network profile is present;
- the existing network-guard bootstrap creates exact local interface authority without target contact.

## Repair boundary

The repair step:

1. reads the previous sealed tracked-file list;
2. adds only `Run-AutoLogonHardwiredLocalRepair.cmd`, `scripts/Invoke-SasAutoLogonHardwiredLocalRepair.ps1`, `Tests/survey/test_autologon_hardwired_local_repair_contracts.py`, and `docs/AUTOLOGON_HARDWIRED_LOCAL_REPAIR.md`, which are the tracked files introduced by this stacked repair lane;
3. refuses any path that escapes either the source root or `C:\SASAL`;
4. copies each bounded file from the already-local source worktree;
5. verifies SHA-256 parity between source and runtime;
6. refreshes the user-local `sas` shim from that same source;
7. writes `sas-autologon-short-runtime/hardwired-repair-v1` with `preparation_git_transport=NONE`, `preparation_remote_git_performed=false`, the exact runtime content commit, and an explicit marker that stale runtime Git metadata is ignored;
8. records no target contact or target mutation during repair.

Only after those gates pass does the command launch `Invoke-SasAutoLogonCrashSafeFieldRun.ps1` against `C:\SASAL` with the exact expected commit.

## Why stale `C:\SASAL` Git metadata is not rewritten

This repair lane intentionally performs no Git command and does not edit Git object/ref state by hand. The old runtime `.git` metadata may therefore still describe the previous sealed commit. That metadata is not deployment authority in this lane. The new manifest records `runtime_content_commit`, the complete SHA-256 content seal, and `runtime_git_metadata_ignored=true`; the crash-safe runner receives the exact expected commit explicitly.

## Proof ceiling

A successful repair marker proves only local runtime-content convergence and hardwired network authority. AutoLogon deployment is complete only when the existing field transaction reaches its normal restart-complete terminal classification. The repair lane never deploys the five clinical-core applications.

## Recovery

If the deployment terminal closes after target work may have started, do not blindly rerun. Use the existing local evidence surfaces first, including `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json` and `sas evidence`, then continue from the recorded transaction state.
