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

When the admin workstation does not already have a usable checkout, use the tracked root bootstrap:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Bootstrap-SysAdminSuiteAutoLogon.ps1 -ComputerName AUTHORIZED_SHORT_HOST -ConfirmVpnPosture
```

The bootstrap resolves the Windows Desktop **known folder** instead of hardcoding a physical OneDrive path. Its durable default checkout is therefore the redirected-or-local equivalent of:

```text
Desktop\dev\SysAdminSuite
```

If the durable checkout is missing, it clones the official repository there. If a Git checkout already exists, it preserves the current branch and local work, fetches `origin/main`, and creates a detached field worktree under `%LOCALAPPDATA%\SysAdminSuite\field-proof-worktrees`. An existing non-Git `SysAdminSuite` folder is never overwritten. `-ExpectedCommit` may be supplied by a field runbook to pin the exact fetched `origin/main` commit before deployment begins.

The bootstrap then activates the repository VPN guard and launches `Run-AutoLogonCrashSafe.cmd`. It does not embed a live target or credential and does not weaken any host, recovery, baseline, restart, or completion gate owned by the canonical AutoLogon lane.

## Protected network

On site, the approved direct protected network is `NSLIJHS-WAB`. VPN use is supported only when the repository VPN bootstrap has produced and activated fail-closed `/32` evidence for an active non-Wi-Fi `DomainAuthenticated` profile. Ordinary Internet Wi-Fi does not authorize the target operation.

Run these read-only surfaces before mutation when diagnosis is needed:

```powershell
sas repo
sas context
sas network
sas next
```

`SAS_NETWORK_GUARD_CONFIG` is the highest-priority network policy override. Otherwise the executing checkout owns its local policy; a stale `SAS_REPO_ROOT` cannot supersede a valid policy beside the executing module.

## Closed historical interrupted transaction

The previously recovered probe-only transaction is conclusively closed machine-local historical evidence. It must not be rerun.

Required closed-state facts are:

- recovery status: `COMPLETED`
- recovery classification: `S4U_PROBE_CREATE_HANG_RECOVERED`
- installer phase entered: false
- AutoLogon installer launched by recovered transaction: false
- exact task absent after cleanup: true
- exact run root absent: true

The exact historical run/task identifiers and recovery path remain in ignored machine-local evidence. The normal `Remote` command discovers only approved local durable evidence, skips a completed recovery record, and returns `NO_INTERRUPTED_PROBE_RUN_FOUND` when no newer unfinished safe probe-only transaction remains. `sas autologon Recover HOST` remains recovery-only and never installs AutoLogon.

## Transaction behavior

`sas autologon Remote HOST` performs one transaction:

1. Proves protected Northwell network posture.
2. Preserves `requested_target`, resolves a unique canonical FQDN, proves at least one address, and records resolution evidence.
3. Proves exact local host-policy eligibility for the canonical FQDN before recovery or apply.
4. Acquires one atomic per-canonical-target operator lock.
5. Stops without applying if durable terminal deployment evidence already exists.
6. Discovers and deduplicates approved local S4U probe evidence, including physical paths and subst aliases.
7. Skips terminal pilot and completed recovery records.
8. Fails closed on install or after-state evidence.
9. Recovers only an exact safely recorded unfinished probe-only transaction against the canonical target.
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
| Protected network | `NSLIJHS-WAB` or separately proven approved VPN |
| Final target | Exact canonical FQDN from machine-local target resolution evidence |
| Host eligibility | `host_eligibility_proven = true` |
| Status | `COMPLETED` |
| Classification | `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` |
| Human-observed sign-in | Separate optional observation; never inferred |
