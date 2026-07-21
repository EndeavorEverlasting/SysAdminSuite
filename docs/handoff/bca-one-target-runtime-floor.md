# BCA One-Target Runtime Floor

```text
[SAS | P01 runtime floor | scope: handoff/docs | proof: repository readiness only]
```

## Purpose

Record the repository floor required before the live Admin-VM → one Cybernet BCA proof sprint may contact a target.

This document is coordination evidence only. It does not authorize live installation, claim application behavior, or replace technician acceptance.

## Required merge floor

| Order | PR | Branch | Role | Merge SHA |
|---|---|---|---|---|
| 1 | [#229](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/229) | `agent/windows-native-smb-bca-deployment` | Windows-native SMB + Task Scheduler approved-package install path for catalog ID `bca` | Merged 2026-07-20 |
| 2 | [#233](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/233) | `docs/cybernet-software-deployment-tutorial` | Cybernet software-deployment tutorial stacked on #229 | Merged 2026-07-20 |

All merge-floor PRs are merged to `main`.

## Additional landed lanes

| Order | PR | Branch | Role | Merge SHA |
|---|---|---|---|---|
| 3 | [#235](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/235) | `feat/low-noise-port-fallback-contract-v2` | Low-noise port-fallback contract floor (schema, fixtures, routing, authority boundaries) | `dfb637e` |
| 4 | [#236](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/236) | `feat/low-noise-network-preflight-v2` | Low-noise network-preflight application integration (decision service, preflight integration) | `d7f75da` |

## Superseded lanes

| PR | Disposition |
|---|---|
| [#144](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/144) | Closed as superseded by #235 and #236. Historical branch `sprint/low-noise-port-policy` preserved. Useful port-fallback classification behavior salvaged into dedicated application module. |

## Final `main` at convergence

```text
d7f75da feat(survey): integrate bounded port fallback decisions (#236)
dfb637e feat(survey): establish low-noise port fallback contract floor (#235)
```

Proof level per lane:
- **#229:** Repository contract + fixture proof + live controller/target execution proof; installer result, CSV retrieval, cleanup, and technician-observed behavior for one Cybernet
- **#233:** Documentation consistency + operator usability proof
- **#235:** Contract proof + harness-routing proof + static/fixture proof + CI proof
- **#236:** Contract proof + harness proof + static/Pester proof + fixture/loopback E2E

No merged lane independently proves fleet deployment completion.

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
