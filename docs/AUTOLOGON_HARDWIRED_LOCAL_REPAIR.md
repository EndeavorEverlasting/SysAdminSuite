# AutoLogon Hardwired Local Repair

Use this lane when the Admin Box is already on an approved Northwell **DomainAuthenticated non-Wi-Fi** connection, the exact approved SysAdminSuite commit already exists in a clean local checkout, and `C:\SASAL` was previously established as a sealed AutoLogon runtime but is behind that exact local commit.

Ordinary `sas refresh` remains Guest/Internet-only. This lane does **not** turn protected Northwell hardwire into repository-acquisition authority. It performs no remote repository acquisition, no GitHub access, no pull, no clone, and no fetch from a configured remote. The only Git object transfer is from the already-local checkout path into the already-local `C:\SASAL` repository.

## Technician entry point

From the exact already-local clean checkout:

```cmd
Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT
```

`EXPECTED_COMMIT` is the exact refreshed repository commit selected before the workstation moved onto the protected network. The launcher refuses extra arguments and delegates to Windows PowerShell 5.1.

## Admission gates

Before mutating `C:\SASAL` or contacting the target, the hardwired lane requires:

- the source checkout is on a local drive, not UNC/network storage;
- the source is a usable Git worktree with `HEAD == EXPECTED_COMMIT`;
- the source has no tracked or untracked working-tree changes;
- the full current tracked tree can be enumerated from that exact source;
- a prior `sas-autologon-short-runtime/v2` seal exists and proves runtime remotes were removed and protected Git networking was disabled;
- `C:\SASAL` is an existing clean standalone sealed Git runtime;
- `Enable-SasNorthwellVpnNetworkGuard.ps1 -ConfirmVpnPosture` proves an active DomainAuthenticated non-Wi-Fi interface and returns zero target-contact/mutation evidence.

A failure in any gate stops before target contact. No reset, clean, force checkout, or destructive runtime deletion is performed.

## Local-only reseal

After network authority is established, the lane:

1. fetches **only** `EXPECTED_COMMIT` from the already-local source path into `C:\SASAL` using local filesystem Git transport;
2. checks out that exact commit detached;
3. requires the runtime to remain clean;
4. removes every configured runtime remote and verifies none remain;
5. independently enumerates the source and runtime tracked-file sets and requires them to be identical;
6. hashes every tracked runtime file with SHA-256 and immediately re-verifies the resulting seal;
7. writes the standard `sas-autologon-short-runtime/v2` manifest to both the runtime-local `.git` authority and the current-user compatibility location, with truthful hardwired provenance:
   - `preparation_network_classification=PROTECTED_NORTHWELL`
   - `preparation_mode=HARDWIRED_LOCAL_RESEAL`
   - `preparation_git_transport=LOCAL_FILESYSTEM_ONLY`
   - `preparation_remote_git_performed=false`
   - `runtime_remotes_removed=true`
   - `protected_bootstrap_git_network_allowed=false`;
8. writes `%LOCALAPPDATA%\SysAdminSuite\autologon-hardwired-local-reseal.json` as a local preparation receipt;
9. refreshes the installed `sas` shim from the same exact runtime; and
10. enters the existing crash-safe AutoLogon transaction with `C:\SASAL` and `EXPECTED_COMMIT` explicitly supplied.

The full current tracked tree is the repair boundary. This intentionally replaces the old stacked-PR design that copied a previous manifest's file list plus a small hand-maintained list of new files; that approach becomes incomplete as `main` evolves.

## Failure and recovery

The existing crash-safe runner owns deployment evidence. If deployment returns nonzero, the hardwired launcher reports `HARDWIRED_AUTOLOGON_FAILED`, preserves the crash-safe evidence surfaces, and tells the operator **do not blindly rerun**. Review the preserved AutoLogon evidence before any recovery or second deployment attempt.

The hardwired lane never deploys the Cybernet clinical-core applications. It only repairs the local execution runtime and enters the existing AutoLogon-only transaction.

## Proof ceiling

Repository tests and CI can prove routing, local-only Git verbs, sequencing, seal construction, no-remote policy, and PowerShell 5.1 parsing. They cannot prove the Admin Box's live DomainAuthenticated network, source checkout identity, runtime contents, target reachability, S4U application, restart, or automatic sign-in. Those remain field evidence.
