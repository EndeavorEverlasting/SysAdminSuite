# Operator Command Handoff Skill

## Trigger

Load this skill **before emitting, executing, or asking an operator to run any SysAdminSuite-owned snippet, command, launcher, CMD file, PowerShell block, or `sas` subcommand**. This skill composes existing authorities; it does not replace the canonical path, repository freshness, operator execution route, or network-intent implementations.

## Non-negotiable sequence

Every operator command follows this order:

1. **Canonical path** — resolve and enter the machine/profile-owned SysAdminSuite development or runtime authority. Never assume the current directory and never promote a convenient clone.
2. **Repository freshness** — before a repository-owned command, refresh remote truth and safely converge only the proven clean/owned/healthy behind-only canonical default-branch checkout. The required Git refresh is `git fetch --all --prune --tags`; the only automatic convergence is `git pull --ff-only` after the repository freshness contract proves it safe.
3. **Starting network + required intent** — capture the current network posture before any transition, resolve the command's network intent, and use the repository-owned network-aware front door for any transition. The starting network is evidence and the return target; do not erase it from the handoff.
4. **Execute the canonical front door** — after path, freshness, and network admission are proven, execute the registered launcher/command and preserve its exit code and durable evidence.
5. **Restore the starting network when the workflow changed it** — restoration is part of the transaction, not an optional cleanup note. A failed required restore prevents promotion of the command to success.

A bare product snippet that starts at step 4 is invalid.

## Canonical path gate

Read `harness/skills/canonical-path-resolution/SKILL.md`, `harness/api/canonical-path-registry.json`, and `harness/workflows/canonical-path-resolution.yaml` first.

On Windows development profiles, resolve the OS Desktop Known Folder and compose `<Desktop>\Dev\SysAdminSuite`; do not hard-code a remembered username or OneDrive path. On Windows Admin Box production/use, `C:\SASAL` is a distinct sealed runtime authority and does not replace the canonical development checkout.

Before a repository-owned operator snippet can continue:

- `Set-Location` must target the proven canonical path or the registered runtime/front door;
- exact Git top-level and supported origin must be proven for a development checkout;
- Git I/O health must be proven;
- dirty, diverged, missing, unhealthy, or separately owned state fails closed before the product command;
- a second mutable clone is not a fallback.

## Freshness gate

Read `harness/workflows/repository-freshness-before-launch.yaml` before selecting or handing out a repository-owned command.

For a canonical development checkout, the atomic handoff must:

1. run `git fetch --all --prune --tags` against the configured remote;
2. resolve the actual remote default branch rather than assuming remembered `main` state;
3. compare local HEAD/tracking/default-remote state;
4. preserve dirty/diverged/unhealthy or separately owned work;
5. use `git pull --ff-only` only when the canonical default-branch checkout is clean, owned, healthy, and strictly behind;
6. prove the executing HEAD is the selected current repository commit before product invocation.

Installed `sas`, a remembered command, a prior successful run, or a GitHub merge is command evidence only. None proves the workstation checkout or sealed runtime is current.

## Network intent and restoration gate

Read `scripts/SasNetworkIntent.psm1` and use `scripts/Invoke-SasNetworkAwareField.ps1` / the installed network-aware `sas` front door instead of hand-writing WLAN or VPN transitions.

Repository intents are:

- `InternetSync` -> **GUEST / INTERNET**, for remote repository synchronization such as `sas refresh`;
- `ProtectedNorthwell` -> **PROTECTED NORTHWELL**, satisfied by approved hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN;
- `LocalOnly` -> **ANY / UNCHANGED**, and SysAdminSuite must not change the network;
- `CommandSpecific` -> command-owned admission with no generic network transition.

Required behavior:

- capture the starting classification/label/authority before changing anything;
- automatic switching is saved-WLAN-profile-only and must be proven after the switch;
- do not guess or automate VPN lifecycle when no repository-proven VPN adapter exists;
- do not disable a protected wired adapter merely to reach InternetSync;
- when the network-aware wrapper switched WLANs, `Restore-SasNetworkIntent` must run in `finally` and restore the recorded starting profile;
- if restoration fails, the overall command is not successful even if the child command returned zero;
- when the operator must perform a manual VPN/hardwire transition, the handoff must state the required return posture after the command; do not claim automatic restoration;
- `%LOCALAPPDATA%\SysAdminSuite\bin\sas-leave.cmd` / `Switch-Back-To-Previous-Network.cmd` is the repository-owned local return path when an eligible saved Guest/Internet return bookmark exists. Do not invent a replacement disconnect/reconnect sequence.

## Atomic operator handoff

When the current environment cannot execute on the workstation, emit **one copy-paste PowerShell block** for the first executable field gate. Do not distribute path relocation, fetch/pull, network transition, product execution, or required restoration as disconnected snippets that can be run out of order.

The block must fail closed on every material native nonzero exit. `$ErrorActionPreference = 'Stop'` is not sufficient for native commands by itself; check `$LASTEXITCODE`.

Prefer the repository-owned launcher/network-aware wrapper over embedding product or network logic in the handoff. The handoff may perform canonical-path and freshness proof around that front door, but it must not become a second implementation of `SasNetworkIntent.psm1`.

## Procedure

1. Resolve the machine/profile and canonical development/runtime authority with `canonical-path-resolution`.
2. Prove repository freshness with `repository-freshness-before-launch` before trusting a repo-owned command surface.
3. Select the canonical command from `harness/api/harness-command-registry.json` and route it through `operator-execution-route` when a registered front door exists.
4. Classify its network intent before product execution. Preserve the starting network posture.
5. Use the network-aware field wrapper for `InternetSync` and `ProtectedNorthwell` transitions; do not hand-code WLAN/VPN switching.
6. Execute the command only after path + freshness + network admission are proven.
7. Restore any automatically changed network in the same transaction. A restore failure is a failed handoff outcome.
8. Report the starting network, required network, transition disposition, command exit, restore disposition, and durable evidence path.
9. Never ask the operator to run a second corrective snippet for a prerequisite that should have been included in the original handoff.

## Required agent-facing integrations

The following agent-facing owners must route to this skill when they are about to emit an operator command:

- `harness/workflows/fresh-agent-intake.yaml`;
- `harness/skills/canonical-path-resolution/SKILL.md`;
- `harness/skills/operator-execution-route/SKILL.md`;
- `.claude/skills/field-workflow/SKILL.md`.

## Expected outputs

- canonical path and role;
- current/default remote identity and freshness disposition;
- selected repository commit;
- starting network classification/label/authority;
- required network intent;
- transition method or manual-transition blocker;
- canonical command/front door;
- child exit code;
- network restore disposition;
- durable evidence path when applicable;
- one exact continuation only for a genuinely unproven user-only/field-only gate.

## Proof ceiling

This skill proves handoff composition and ordering. Repository/static/CI validation cannot prove a physical workstation's current path, remote reachability, active WLAN/VPN/hardwire state, protected target access, or successful live restoration; those remain runtime evidence produced by the existing path, freshness, network-intent, and product authorities.
