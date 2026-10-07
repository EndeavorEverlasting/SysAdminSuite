# ScanSnap live-cert status (Admin Box 1)

**Updated:** 2026-10-06 after PR #510 and operator multimodal correction  
**Control host:** `LPW003ASI173` (Admin Box 1)  
**Lab target:** `CheexMcClappeth` (PTop)  
**Priority field targets:** `WRH250STR001`, `WRH250STR002`  
**Durable continuation:** `docs/SCANSNAP_MULTIMODAL_DEPLOYMENT.md`

## Proven

| Gate | State | Evidence |
|---|---|---|
| Package implementation on main | INTEGRATED | PR #507 / `2610c4f4` |
| Access classifier follow-up on main | INTEGRATED | PR #510 / `1b2b86bd` |
| WhatIf no mutation | VALIDATED | 20261006_224231 / 224237 CSVs |
| Home PTop reachability | OBSERVED | hostname/IP responded in prior exact-target probes |
| Precise home access class | VALIDATED | hostname=`AUTH_DC_UNAVAILABLE`; IP=`LOGON_FAILURE` |
| Installer bound | BOUND | ScanSnap Home 4.1.0.5 / `WinSSHomeInstaller_4_1_0.exe` SHA256 `A297B84628334F88BE24559C9D2C164E07BC8D952149FE439A19FB3A53CBDDC8`; source Ricoh offline CDN `w-410` |
| PTop `INSTALLATION_DETECTED` | NOT YET | lab auth/package not cleared |
| Field deployment | NOT YET | not attempted |

## Unattended deployment requirement

The production contract is remote and unattended. The technician must be able to deploy to an authorized hostname even when the workstation's physical location is unknown or inaccessible and nobody is present at its console.

Target-side clicks, interactive approval, local console access, or user presence are not acceptable prerequisites for the normal Northwell deployment path. Hostname/FQDN resolution, protected-network authority, remote administrative access, SYSTEM execution, and post-install detection are the intended control-plane mechanisms.

The PTop lab is only testing whether the same unattended remote-management shape can be exercised at home. A home-lab authentication limitation must not weaken this production invariant.

## Correct interpretation of the home result

The prior home run did **not** establish that PTop could not be found. It established:

- Admin Box 1 was `LPW003ASI173`;
- the PTop candidate responded as `CheexMcClappeth` / runtime IPv4 `192.168.1.79`;
- no Northwell domain controller was reachable from the home LAN;
- hostname SMB failed as `AUTH_DC_UNAVAILABLE`;
- IP SMB failed as `LOGON_FAILURE`.

The remaining lab question is therefore controller-side remote identity resolution/addressability + remote local-admin SMB auth, not physical discovery, user-assisted pairing, or broad machine discovery.

The current home IPv4 is runtime evidence only; do not make DHCP state the durable identity contract.

## Priority correction

PTop is a diagnostic prototype target, not a release gate.

The business-critical targets are:

- `WRH250STR001`
- `WRH250STR002`

After one bounded, materially informative home attempt, move to the protected Northwell/VPN path when available even if PTop remains uncertified.

## Package-source correction

For this application, the installer is acquired from the web / authoritative vendor source, not the internal Northwell software directory used by some other deployments.

Package acquisition and target deployment are separate operations:

1. Internet-capable Admin Box obtains and qualifies the exact package.
2. Manifest freezes SHA256 + silent + detection evidence.
3. The bounded package is staged from Admin Box to targets over the selected authorized transport.

Do not block on the internal software server for ScanSnap unless new client evidence explicitly changes the source contract.

## Durable execution modes

See `docs/SCANSNAP_MULTIMODAL_DEPLOYMENT.md`.

Current intended modes:

- `LAB_LOCAL` — exact PTop prototype; local admin auth; diagnostic only.
- `NORTHWELL_PROTECTED` — Northwell LAN/WAB using existing network-authority + low-noise transport contracts.
- `NORTHWELL_VPN` — authenticated DomainAuthenticated VPN using the same target deployment path.
- `UNKNOWN_BLOCKED` — fail closed.

## Next execution

1. In parallel where execution adapters permit:
   - qualify/bind the official ScanSnap package;
   - run one final fully unattended, controller-side PTop resolution/auth prototype.
2. If PTop cannot reach `ADMIN_SHARE_READY` after the bounded experiment, preserve the typed receipt and stop spending the critical path on home auth.
3. Connect to the authorized Northwell protected/VPN path.
4. WhatIf the exact field targets.
5. Once package + transport gates are green, deploy live until each target reaches `INSTALLATION_DETECTED`.
6. Promote any successful prototype behavior into the durable CMD/operator surface and tests.

## Proof ceiling

Current repository proof reaches implementation + tests + typed home WhatIf classification. It does **not** yet prove a ScanSnap installation on PTop or either field target.
