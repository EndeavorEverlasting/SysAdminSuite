# AutoLogon Field Deployment Completion

## Supported use case

The five clinical-core applications are already deployed to the authorized Cybernet and are out of scope for this lane. The supported AutoLogon-only product command is:

```powershell
sas autologon Remote WPJ075OPR046
```

The operator-supplied short hostname is preserved in evidence and canonicalized before eligibility and mutation to:

```text
wpj075opr046.nslijhs.net
```

The FQDN form is also supported:

```powershell
sas autologon Remote wpj075opr046.nslijhs.net
```

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

## Closed July 30 transaction

The July 30 interrupted probe transaction is conclusively closed historical evidence. It must not be rerun.

- Outer run: `autologon-s4u-deployment-20260730-235817-96572c6f`
- Inner run: `autologon-kerberos-s4u-20260730-195817-595ccbb2`
- Exact task: `SysAdminSuite-AutoLogonS4UProbe-ed0ca89170fc4136b266f77ff49bab06`
- Completed classification: `S4U_PROBE_CREATE_HANG_RECOVERED`
- Installer phase entered: false
- AutoLogon installer launched by recovered transaction: false
- Exact task absent after cleanup: true
- Exact run root absent: true

The normal `Remote` command discovers only approved local durable evidence, skips this completed recovery record, and should return `NO_INTERRUPTED_PROBE_RUN_FOUND` when no newer unfinished safe probe-only transaction remains. `sas autologon Recover HOST` remains recovery-only and never installs AutoLogon.

## Transaction behavior

`sas autologon Remote HOST` performs one transaction:

1. Proves protected Northwell network posture.
2. Preserves `requested_target`, resolves a unique canonical FQDN, proves at least one address, and records resolution evidence.
3. Applies exact local host authorization to the canonical identity through the existing hardened engine.
4. Discovers and deduplicates approved local S4U probe evidence, including physical paths and subst aliases.
5. Skips terminal pilot and completed recovery records.
6. Fails closed on install or after-state evidence.
7. Recovers only an exact safely recorded unfinished probe-only transaction.
8. Invokes the hardened AutoLogon S4U apply exactly once.
9. Requires the clean intent-only baseline before mutation.
10. Stages and hash-verifies the approved AutoLogon package.
11. Uses the passwordless elevated S4U task without interactive credentials or a stored task password.
12. Captures post-install state without collecting the `DefaultPassword` value.
13. Verifies exact task and staging cleanup.
14. Creates one bounded SYSTEM restart task, observes SMB leave and return, and verifies restart-task cleanup.
15. Persists `autologon_field_deployment_result.json` and the inner restart-complete result.

Do not manually reboot during the supported restart wrapper. Do not blindly rerun after any failure once apply or target mutation has begun. Use `sas context` and `sas next`; inspect the persisted evidence path shown there.

A pre-apply failure with `target_mutation_performed = false` may be repaired and rerun once. A post-apply or ambiguous mutation state must be recovered from durable evidence rather than starting a second deployment.

## Terminal classification

Successful system deployment requires:

```text
status = COMPLETED
classification = AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
autologon_applied = true
pre_reboot_autologon_ready = true
automatic_reboot_performed = true
restart_offline_observed = true
restart_online_observed = true
restart_task_cleanup_verified = true
target_mutation_performed = true
final_target = wpj075opr046.nslijhs.net
```

`AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` proves AutoLogon application and the bounded restart cycle. It does not prove human-observed interactive desktop sign-in. A human observation may be recorded separately after terminal deployment success.

## Field-certification report

Record the machine-local outer result path emitted by the command. Do not commit live evidence or credentials.

| Field | Required value |
|---|---|
| Requested command | `sas autologon Remote WPJ075OPR046` |
| Protected network | `NSLIJHS-WAB` or separately proven approved VPN |
| Final target | `wpj075opr046.nslijhs.net` |
| Status | `COMPLETED` |
| Classification | `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` |
| Human-observed sign-in | Separate optional observation; never inferred |
