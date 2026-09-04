# AutoLogon Field Deployment Completion

## Supported use case

The five clinical-core applications are already deployed to the authorized Cybernet and are out of scope for this lane. The supported AutoLogon-only product command is:

```powershell
sas autologon Remote AUTHORIZED_SHORT_HOST
```

The operator-supplied short hostname is preserved in machine-local evidence and canonicalized before eligibility and mutation to its exact authorized FQDN, for example:

```text
authorized-host.example.net
```

The exact FQDN form is also supported:

```powershell
sas autologon Remote authorized-host.example.net
```

Live target names, exact run IDs, task IDs, usernames, and evidence paths belong only in ignored operator-local state and field evidence. They must not be committed to tracked documentation or fixtures.

## Clean acquisition and field launch

When the admin workstation does not already have a trusted short runtime, use the tracked root bootstrap:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Bootstrap-SysAdminSuiteAutoLogon.ps1 -ComputerName AUTHORIZED_SHORT_HOST
```

The bootstrap uses `C:\SASAL` as the stable short execution runtime. It resolves `git.exe` explicitly from PATH or standard Git for Windows locations, validates the official SysAdminSuite origin, fetches only `origin/main`, and pins the runtime to the exact fetched commit before any field transaction begins. `-ExpectedCommit` may be supplied to require an exact known `origin/main` commit.

A long, redirected, copied, backup, dirty, or even non-Git legacy `SysAdminSuite` folder is **not** required to be execution authority. When such a folder is available, the bootstrap may retain it only as a bounded machine-local evidence/configuration fallback through `SAS_REPO_ROOT`. A local `Config\sas-network-guard.local.json` there may be exposed to the shared network guard through `SAS_NETWORK_GUARD_CONFIG`; that policy still has to match the workstation's current network evidence and is never an authorization bypass.

If `C:\SASAL` is absent, the bootstrap clones the official repository there. If it already exists, it must be a usable Git worktree with the approved origin and a clean working state. An unrelated, malformed, or dirty `C:\SASAL` is never reset, cleaned, deleted, or overwritten automatically.

The bootstrap validates the crash-safe runner, on-site launcher, and canonical network-gate PowerShell surfaces, then launches `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`. The child deployment output, offline evidence recovery, and stable latest-run pointer remain under `%LOCALAPPDATA%\SysAdminSuite`, so terminal closure does not erase the operator's diagnostic trail.

`-ConfirmVpnPosture` remains accepted only for compatibility with older command cards. It is an acknowledgement and does **not** grant network authority or write an allowlist.

## Protected network

Protected-network admission is owned only by the canonical AutoLogon field transaction through `Confirm-SasNorthwellNetwork.ps1` and the shared `SasNetworkGuard` policy. The supported bootstrap does not run `Enable-SasNorthwellVpnNetworkGuard.ps1` as a mandatory pre-step and does not equate the presence of a VPN with authorization.

On site, the approved direct protected network includes `NSLIJHS-WAB`. A VPN or wired path may also pass only when the canonical shared guard proves the current Windows/network evidence against an approved local policy. Ordinary Internet/guest connectivity, an arbitrary active Ethernet interface, or VPN presence alone does not authorize target contact or mutation.

Run these read-only surfaces before mutation when diagnosis is needed:

```powershell
sas repo
sas context
sas network
sas next
```

`SAS_NETWORK_GUARD_CONFIG` is the highest-priority local network-policy override when explicitly set by the supported bootstrap. Otherwise the executing checkout owns its local policy, with `SAS_REPO_ROOT` retained only as the documented fallback for a legacy evidence/configuration root.

## Closed historical interrupted transaction

The previously recovered probe-only transaction is conclusively closed machine-local historical evidence. It must not be rerun.

Required closed-state facts are:

- recovery status: `COMPLETED`
- recovery classification: `S4U_PROBE_CREATE_HANG_RECOVERED`
- installer phase entered: false
- AutoLogon installer launched by recovered transaction: false
- exact task absent after cleanup: true
- exact run root absent: true

The exact historical run/task identifiers and recovery path remain in ignored machine-local evidence. The normal `Remote` command discovers only approved local durable evidence, skips a completed recovery record, and returns `NO_INTERRUPTED_PROBE_RUN_FOUND` when no newer safe recovery candidate remains. `sas autologon Recover HOST` remains recovery-only and never installs AutoLogon.

A terminal pilot result is not automatically equivalent to a completed or safe-to-ignore transaction. Recovery v3 admits **only the exact safe terminal Probe-create timeout shape**: terminal and nested Probe classifications must both be `S4U_PROBE_CREATE_TIMEOUT`, run/target/task identity must match, outer staging cleanup must already be verified, and installer/after-state/reboot proof must be absent. Every other terminal pilot result remains excluded from discovery and refused by exact interrupted recovery.

### Exact Probe-create timeout continuation

A field transaction that has already passed transport, source resolution, source ticketing, baseline capture/eligibility, final-step admission, source hashing, and staging/hash verification can still stop at the bounded Probe Task Scheduler create. When the nested S4U result is exactly `S4U_PROBE_CREATE_TIMEOUT` and the outer field result reports `AUTOLOGON_FIELD_POST_APPLY_REVIEW_REQUIRED`, that state is **recovery-required, not deployment-complete and not permission for a blind rerun**.

Stay on the same approved protected Northwell authority and run the existing recovery-only lane first:

```powershell
sas autologon Recover AUTHORIZED_SHORT_HOST
```

The recovery must remain bound to the recorded run, target, and GUID-unique Probe task. It may query the exact task, delete it only when necessary, verify exact task absence, clean only the recorded Probe-only remote run root, and verify that installer, after-state, reboot, and automatic-sign-in evidence are absent. It must never launch the AutoLogon installer.

For this post-apply-review continuation, accept only `status=COMPLETED` with `classification=INTERRUPTED_PROBE_RUNS_RECOVERED`. `NO_INTERRUPTED_PROBE_RUN_FOUND` is a stop-and-inspect result here: it proves no candidate was admitted for recovery, not that the recorded post-apply run was safely closed, because an incompatible terminal candidate can be filtered out before recovery. The field wrapper preserves `AUTOLOGON_FIELD_POST_APPLY_REVIEW_REQUIRED` until exact interrupted Probe recovery succeeds.

Only after that completed exact recovery may the operator make **exactly one supported AutoLogon retry**:

```powershell
sas autologon Remote AUTHORIZED_SHORT_HOST
```

Do not inflate the S4U create timeout, create a second ad-hoc task, reinstall the clinical core, manually reboot, switch to a second Admin Box, or replay inner S4U/task fragments merely because the bounded create call timed out. The supported continuation is durable-evidence recovery first, then one normal product retry.

## Transaction behavior

`sas autologon Remote HOST` performs one transaction:

1. Proves protected Northwell network posture.
2. Preserves `requested_target`, resolves a unique canonical FQDN, proves at least one address, and records resolution evidence.
3. Proves exact local host-policy eligibility for the canonical FQDN before recovery or apply.
4. Acquires one atomic per-canonical-target operator lock.
5. Stops without applying if durable terminal deployment evidence already exists.
6. Discovers and deduplicates approved local S4U probe evidence, including physical paths and subst aliases.
7. Skips completed recovery records and all terminal pilot results except the exact safe `S4U_PROBE_CREATE_TIMEOUT` recovery-v3 shape.
8. Fails closed on install or after-state evidence.
9. Recovers only an exact safely recorded probe-only transaction against the canonical target, including the admitted terminal Probe-create-timeout case when every v3 guard passes.
10. Invokes the hardened AutoLogon S4U apply exactly once.
11. Requires the clean intent-only baseline before mutation.
12. Stages and hash-verifies the approved AutoLogon package.
13. Uses the passwordless elevated S4U task without interactive credentials or a stored task password.
14. Captures post-install state without collecting the `DefaultPassword` value.
15. Verifies exact task and staging cleanup.
16. Creates one bounded SYSTEM restart task, observes SMB leave and return, and verifies restart-task cleanup.
17. Persists the outer `autologon_field_deployment_result.json` as the canonical terminal artifact and retains the inner restart-wrapper result as supporting evidence.

Do not manually reboot during the supported restart wrapper. Do not blindly rerun after any failure once apply or target mutation has begun. Use `sas context` and `sas next`; inspect the persisted evidence path shown there.

A pre-apply failure with `target_mutation_performed = false` may be repaired and rerun once. A post-apply, concurrently locked, or ambiguous mutation state must be recovered from durable evidence rather than starting a second deployment.

## Terminal classification

Successful system deployment requires:

```text
status = COMPLETED
classification = AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
host_eligibility_proven = true
autologon_applied = true
pre_reboot_autologon_ready = true
automatic_reboot_performed = true
restart_offline_observed = true
restart_online_observed = true
restart_task_cleanup_verified = true
target_mutation_performed = true
final_target = <exact authorized canonical FQDN>
```

`AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` proves AutoLogon application and the bounded restart cycle. It does not prove human-observed interactive desktop sign-in. A human observation may be recorded separately after terminal deployment success.

## Field-certification report

Record the machine-local outer result path emitted by the command. Do not commit live evidence or credentials.

| Field | Required value |
|---|---|
| Requested command | `sas autologon Remote AUTHORIZED_SHORT_HOST` |
| Protected network | canonical shared guard PASS on current approved Northwell network/VPN evidence |
| Final target | Exact canonical FQDN from machine-local target resolution evidence |
| Host eligibility | `host_eligibility_proven = true` |
| Status | `COMPLETED` |
| Classification | `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` |
| Human-observed sign-in | Separate optional observation; never inferred |
