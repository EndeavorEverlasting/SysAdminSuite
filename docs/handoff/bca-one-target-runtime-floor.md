# BCA One-Target Runtime Floor

```text
[SAS | P01 runtime floor | scope: handoff/docs | proof: repository readiness only]
```

## Purpose

Record the repository floor required before the live Admin-VM → one Cybernet BCA proof sprint may contact a target.

This document is coordination evidence only. It does not authorize live installation, claim application behavior, or replace technician acceptance.

## Required merge floor

| Order | PR | Branch | Role |
|---|---|---|---|
| 1 | [#229](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/229) | `agent/windows-native-smb-bca-deployment` | Windows-native SMB + Task Scheduler approved-package install path for catalog ID `bca` |
| 2 | [#233](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/233) | `docs/cybernet-software-deployment-tutorial` | Cybernet software-deployment tutorial stacked on #229 |

Preferred runtime commit identity:

1. `#229` merged to `main`
2. `#233` retargeted or merged after `#229`
3. required checks green on the exact runtime commit
4. clean local worktree or isolated worktree based on that floor

## Exact-SHA exception rule

If live proof is authorized before merge, the exception must name the exact implementation and documentation SHAs and must not claim qualification of `main`.

Observed heads at floor-readiness update time (re-query before use):

- implementation hint: PR #229 head previously green and mergeable while draft
- documentation hint: PR #233 head stacked on the implementation branch

Hints are not current truth. Re-query GitHub before runtime.

## Runtime proof ceiling after merge

Still separate from this floor:

- one approved admin VM controller
- exactly one authorized Cybernet
- package ID `bca` only
- dry-run plan proof, then explicit human live release
- installer result + cleanup + technician-observed shortcut/application behavior for Level 6

## Forbidden until separately authorized

- multi-target batch
- other packages
- reboot / post-reboot proof
- uninstall / fleet acceptance
- credential embedding, WinRM/firewall/GPO weakening, AutoLogon, personal-data mutation

## Next safe repository action

Mark #229 ready when checks are green, merge it when authority exists, then land #233 and only afterward start the one-target live proof on an approved admin VM.
