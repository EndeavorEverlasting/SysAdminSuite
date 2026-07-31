# AutoLogon S4U field hardening — 2026-07-30

## Status

The repository implementation for the July 30 S4U probe-create hang is now hardened on PR #298.
This file is an operational contract, not a remaining-work checklist.

The field-proven failure was a synchronous `schtasks.exe /Create` call that could block the owning
PowerShell indefinitely before a probe result or normal lifecycle evidence existed. The interrupted
transaction had not entered the AutoLogon installer phase. The same field session also demonstrated
that hand-built recovery snippets created unacceptable operator work and could fail independently
(e.g. multiline positional `Join-Path` prompting).

The supported path must therefore own refresh, branch provenance, interruption recovery, task/run
identity, timeouts, progress, exact cleanup, evidence, and local network transitions.

This handoff contains no live username, password, Wi-Fi secret, AutoLogon secret, or target identifier.

## Supported field path

### Guest / Internet

Use:

```text
sas refresh
```

`Refresh-SasOperatorCommand.ps1` now preserves the intended branch rather than unconditionally
switching the field-ready checkout to `origin/main`:

1. use an explicit `-Ref` when supplied;
2. otherwise use the source checkout's current branch;
3. for a detached field-ready checkout, recover the single `origin/<branch>` ref pointing at HEAD;
4. if that shared tracking ref has advanced, recover the last successful branch from
   `%LOCALAPPDATA%\SysAdminSuite\repo-ref.txt`;
5. fall back to `main` only when no branch provenance exists.

The fetch updates the selected remote-tracking ref without force. Dirty or separately owned
field-ready work is not reset or cleaned. A refreshed checkout is accepted only when its HEAD equals
the fetched remote head and all required operator surfaces exist.

Successful refresh emits:

```text
SAS_OPERATOR_REFRESH_READY
REF: <branch>
HEAD: <sha>
```

### Protected Northwell

For AutoLogon-only deployment use:

```text
sas autologon Remote HOST
```

Do not reconstruct S4U task creation, recovery, cleanup, restart, or state capture manually.

The normal `Remote` action now owns an interrupted-run gate before a new AutoLogon apply. It searches
machine-local SysAdminSuite evidence only for durable probe lifecycle records belonging to the target.

- no recorded interrupted probe run -> continue;
- one or more safely recorded probe-only interrupted runs -> recover each exact task/run, then continue;
- any unfinished run with install or after-state evidence -> fail closed and do not redeploy.

An explicit recovery-only action also exists:

```text
sas autologon Recover HOST
```

### Leave protected Wi-Fi

Use either:

```text
sas leave
```

or double-click:

```text
Switch-Back-To-Previous-Network.cmd
```

The installer also creates:

```text
%LOCALAPPDATA%\SysAdminSuite\bin\sas-leave.cmd
```

The return path is local-only. It requires the operator session's previously recorded network to be
`GUEST_INTERNET`, rejects an approved protected Northwell profile as the destination, requires an
existing saved Windows WLAN profile, uses bounded local `netsh`, verifies the exact previous Wi-Fi
label after the connection request, and updates machine-local operator state. It does not contact or
mutate any deployment target and does not read or store WLAN credentials.

## S4U execution invariants

### Target readiness

Kerberos SMB + Task readiness requires all of the following before S4U staging/task execution:

- domain joined;
- TGT present;
- target `CIFS/<target>` ticket issued;
- target `HOST/<target>` ticket issued;
- TCP 445 reachable;
- ADMIN$ authorized;
- TCP 135 reachable;
- Schedule service running;
- exact scheduled-task read query authorized.

The earlier missing-HOST-ticket failure was a producer/consumer defect and is fixed in the tracked
low-noise transport implementation and contracts.

### Software-source identity

`SasSoftwareSourceIdentity.psm1` is consumed directly by the executable S4U lane.

The approved catalog alias remains the source authority. Runtime canonicalization is accepted only
when the canonical FQDN and approved alias share resolved address evidence. Kerberos then requests
the canonical `CIFS/<fqdn>` SPN and reads the same approved source through the canonical UNC identity.
No credentials or ticket bytes are collected.

### First-install baseline

`SasAutoLogonBaselinePolicy.psm1` is consumed directly by the executable lane.

Allowed first-install states are:

- `not_configured` with no installed AutoLogon package; or
- exact inert `intent_only`: `Autologon_YES` intent, AutoAdminLogon disabled, no user/domain,
  no ForceAutoLogon, no AutoLogonCount, no DefaultPassword value present, no expected-user match,
  and no installed AutoLogon package.

Active, partial, mismatched, password-bearing, or package-present states fail closed.

### Host eligibility

Live targets still require exact operator-local host eligibility authority. The tracked sample policy
must never authorize real hosts, and broad wildcard authorization must not be introduced merely to
clear the final-step gate.

## Bounded task and result lifecycle

`SasBoundedNative.psm1` is the shared timeout primitive. It isolates native work in a child process
and kills that isolated process tree on timeout.

The S4U apply lane bounds every Task Scheduler verb:

- `/Create`
- `/Run`
- `/Delete`
- `/Query`

The restart-completion wrapper uses the same bounded Task Scheduler ownership.

Remote S4U result existence checks and result retrieval are isolated in bounded child PowerShell;
a potentially blocking UNC `Test-Path` no longer sits ahead of the nominal result deadline in the
owning deployment process.

The bounded module also exposes reusable bounded path, directory, file-copy, and SHA-256 primitives
for recovery/operator paths that must touch UNC resources without hanging the owning shell.

Timeouts have explicit classifications such as probe-create, probe-run, result, and cleanup failures.
A timeout is never treated as success.

## Durable task/run identity

Before `schtasks.exe /Create`, the S4U lifecycle evidence records the exact:

- run ID;
- mode;
- target;
- task name;
- S4U principal;
- remote worker path;
- remote result path;
- local result path;
- create/run/retrieve/delete/absence flags;
- current stage and timestamps.

Lifecycle evidence is updated after each transition. A terminal crash no longer requires local
process inspection to rediscover task/run ownership for hardened runs.

Probe failure/timeout remains upstream of installer-worker generation. The install worker is not
created or launched until the probe result proves the expected SID and elevated administrator token.

## Operator-visible progress

The apply + restart lane persists and streams the 22-stage progression. Major checkpoints cover:

1. transport preflight;
2. canonical source resolution;
3. source CIFS ticket;
4. baseline capture;
5. baseline eligibility;
6. final-step gate;
7. source hash;
8. staging/hash verification;
9-12. probe create/run/result/cleanup;
13-16. install create/run/result/cleanup;
17. after-state capture;
18. exact staging cleanup;
19. restart handoff;
20. offline observation;
21. online observation;
22. restart-task cleanup.

`progress_checkpoint.json` and `progress_history.jsonl` make quiet console periods diagnosable from
local evidence without touching the target.

## Exact interrupted-run recovery

`Complete-SasInterruptedAutoLogonS4URecovery.ps1` now owns the exact destructive recovery operation.
It requires protected-network posture and exact recorded target/run/task/local-run identity.

Recovery order is deliberate:

1. prove local evidence never entered install/after-state;
2. bounded-check the exact remote probe result and retrieve it before cleanup when present;
3. bounded-query only the recorded exact task name;
4. if that exact task exists, bounded-delete only that task;
5. independently bounded-query the same name until absence is proven;
6. inventory only the exact recorded S4U run root;
7. refuse unexpected names;
8. remove only that exact run root;
9. independently prove exact run-root absence;
10. prove exact task absence again;
11. write `S4U_PROBE_CREATE_HANG_RECOVERED` local evidence.

The recovery helper never launches AutoLogon and never broadens cleanup to parent SysAdminSuite
directories or unrelated scheduled tasks.

`Recover-SasLatestInterruptedAutoLogonS4U.ps1` is the local discovery/orchestration layer used by the
normal `Remote` deployment. It never enumerates remote scheduled tasks. It discovers ownership only
from durable local S4U probe lifecycle evidence and invokes the exact helper with those recorded values.

## Legacy July 30 interrupted run boundary

The original field hang occurred before pre-create lifecycle identity persistence existed. That old
run therefore cannot be safely auto-discovered from the new lifecycle file because the file did not
exist at the time of the hang.

Field evidence already proved the old installer phase was not entered and the exact old probe task
was absent after the wedged local process was terminated. If its exact staging run root remains, close
that one legacy root using the recorded exact identity from the preserved field evidence and the
tracked exact recovery/cleanup helpers. Do not encode the live target, task GUID, username, or run ID
into tracked source merely to automate a one-time legacy cleanup.

All new hardened runs persist the information required for automatic exact recovery.

## Security and non-regression boundaries

- protected-network gate before target contact;
- named-domain passwordless S4U (`/NP`) model preserved;
- no task password stored;
- no `DefaultPassword` value collection or serialization;
- source identity tied to approved alias + verified canonical identity;
- exact operator-local host eligibility preserved;
- hash, final-step, exact-cleanup, and restart-observation gates preserved;
- no broad task discovery for interruption recovery;
- no automatic fallback after target mutation;
- no clinical-core redeployment merely to reach AutoLogon;
- runtime automatic desktop sign-in observation is not fabricated as a deployment-complete proof;
- terminal crashes resume from recorded evidence instead of reconstructed `try/catch/finally` fragments.

## Validation contracts

The offline/CI harness includes contracts for:

- bounded S4U task verbs;
- bounded remote result probing;
- process-tree termination on native timeout;
- pre-create identity persistence;
- probe-before-installer ordering;
- durable software-source identity consumption;
- exact inert baseline policy consumption;
- exact run-root cleanup scope;
- recovery-before-apply orchestration;
- refusal when interrupted install/after-state evidence exists;
- exact recorded-task delete/verify ordering;
- probe-result retrieval before destructive cleanup;
- branch-preserving, non-force field refresh;
- durable detached-checkout ref provenance;
- local-only saved-profile network return;
- installed and repo-root double-click leave surfaces;
- no live user/target/secret literals.

PR #298 CI on the **current head** remains the merge gate. Never merge based on a remembered green
status from an older SHA.

## Required deployment completion classification

AutoLogon-only deployment is complete only at:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

That classification remains downstream of accepted baseline state, exact target eligibility,
passwordless elevated S4U probe, hash-verified AutoLogon install, required pre-reboot state, exact
S4U cleanup, restart initiation, observed SMB offline/online restart cycle, and restart-task cleanup.
