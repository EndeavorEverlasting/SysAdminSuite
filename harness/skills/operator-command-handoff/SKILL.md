# Operator Command Handoff Skill

## Trigger

Load this skill **before emitting, executing, or asking an operator to run any SysAdminSuite-owned snippet, command, launcher, CMD file, PowerShell block, or `sas` subcommand**. This skill composes existing authorities; it does not replace the canonical path, repository freshness, operator execution route, or network-intent implementations.

## Protected AutoLogon window fast path

A live protected-network window is an execution resource. Do not spend it on repository synchronization when the requested operation is AutoLogon `Remote` and a locally sealed runtime can already satisfy the operation.

The fast path is allowed only when all of the following are true:

- the requested command is the canonical AutoLogon `Remote` lane for one explicit authorized target;
- the starting posture is already **PROTECTED NORTHWELL**, whether provided by approved hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN;
- the installed/sealed AutoLogon route is locally available and its v2 manifest, prepared commit, local-filesystem-only transport, removed-remotes posture, SHA-256 tracked-file seal, and protected bootstrap validate without remote Git;
- the runtime satisfies the selected accepted deployment floor/capability for the operation. For the contiguous-progress capability, a sealed `Run-AutoLogon-ContiguousProgress.cmd` plus `scripts\SasAutoLogonProgress.psm1` is acceptable compatibility evidence for runtimes prepared before continuity moved into the common crash-safe runner;
- the repository-owned protected-network gate admits the current path.

When those conditions hold, execute the sealed crash-safe AutoLogon front door **immediately from the existing protected posture**. Do not transition to `InternetSync`, do not run `git fetch`, do not run `sas refresh`, and do not disconnect/reconnect VPN merely to satisfy the standard repository-backed sequence. The runtime/bootstrap remains responsible for target safety and durable evidence.

If local protected-window proof is missing or stale, fail quickly and preserve the network window. Report the exact missing runtime/floor proof. Do not automatically leave VPN/hardwire/WAB or start a freshness detour. The standard repository-backed sequence applies only after the operator is no longer intentionally preserving that protected window.

This fast path is setup-agnostic: machine-wide universal `sas`, current-user portable `sas`, hardwire, WAB, and authenticated VPN are equivalent only when their existing repository authorities prove the same protected runtime and network gates. Do not hard-code one workstation path, username, adapter name, VPN product, or Wi-Fi profile.

## Non-negotiable sequence

For repository-backed commands and for AutoLogon when the protected-window fast path is not admissible, every operator command follows this order:

1. **Canonical path** — resolve and enter the machine/profile-owned SysAdminSuite development authority before repository maintenance, and capture the starting network posture before any transition. Never assume the current directory and never promote a convenient clone. A registered sealed/runtime front door may execute elsewhere later, but it does not replace this canonical development/freshness authority.
2. **Repository freshness** — before a repository-owned command, refresh remote truth and safely converge only the proven clean/owned/healthy behind-only canonical default-branch checkout. Repository synchronization is an `InternetSync` subtransaction: enter/prove Guest/Internet using the repository-owned network authority, run the required Git refresh (`git fetch --all --prune --tags`) and any proven-safe `git pull --ff-only`, then return to the recorded starting network posture before selecting the product command's network intent.
3. **Starting network + required intent** — from the recorded/restored starting posture, resolve the product command's network intent and use the repository-owned network-aware front door for any required transition. The starting network is evidence and the return target; do not erase it from the handoff.
4. **Execute the canonical front door** — after path, freshness/runtime-currentness, and product-network admission are proven, execute the registered launcher/command and preserve its exit code and durable evidence.
5. **Restore the starting network when the workflow changed it** — restoration is part of the transaction, not an optional cleanup note. A failed required restore prevents promotion of the command to success.

A bare product snippet that starts at step 4 is invalid unless it is the explicitly admitted protected AutoLogon window fast path above.

## Canonical path gate

Read `harness/skills/canonical-path-resolution/SKILL.md`, `harness/api/canonical-path-registry.json`, and `harness/workflows/canonical-path-resolution.yaml` first.

On Windows development profiles, resolve the OS Desktop Known Folder and compose `<Desktop>\Dev\SysAdminSuite`; do not hard-code a remembered username or OneDrive path. On Windows Admin Box production/use, `C:\SASAL` is a distinct sealed runtime authority and does not replace the canonical development checkout.

Before a repository-backed operator snippet can continue:

- `Set-Location` must first target the proven canonical development path for repository maintenance/currentness proof;
- capture starting network classification/label/authority **before** any InternetSync or product-network transition;
- exact Git top-level and supported origin must be proven for the development checkout;
- Git I/O health must be proven;
- dirty, diverged, missing, unhealthy, or separately owned state fails closed before the product command;
- a second mutable clone is not a fallback;
- a registered sealed/runtime front door is selected only after canonical development freshness and its own runtime-currentness authority are proved, except for the locally admitted protected AutoLogon window fast path.

## Freshness gate

Read `harness/workflows/repository-freshness-before-launch.yaml` before selecting or handing out a repository-backed command.

For a canonical development checkout, the atomic handoff must:

1. preserve the already-captured starting network posture;
2. enter/prove `InternetSync` through the repository-owned network authority before remote Git I/O; do not ask the operator to switch first and only record the starting network afterward;
3. run `git fetch --all --prune --tags` against the configured remote;
4. resolve the actual remote default branch rather than assuming remembered `main` state;
5. compare local HEAD/tracking/default-remote state;
6. preserve dirty/diverged/unhealthy or separately owned work;
7. use `git pull --ff-only` only when the canonical default-branch checkout is clean, owned, healthy, and strictly behind;
8. prove the executing/deployment source HEAD is the selected current repository commit;
9. return to the recorded starting network posture after the InternetSync freshness subtransaction before applying the product command's own network intent. If that required return fails, stop before product execution.

Installed `sas`, a remembered command, a prior successful run, or a GitHub merge is command evidence only. None by itself proves a workstation checkout or sealed runtime is current. The protected-window exception relies on the sealed runtime's own local manifest/seal/capability proof instead of claiming repository freshness.

### Sealed `C:\SASAL` runtime

`C:\SASAL` must not run remote Git merely to prove currentness. On Guest/Internet, the repository-owned `sas refresh` / `scripts/Refresh-SasOperatorCommand.ps1` flow builds the isolated `field-ready` tree from refreshed remote truth, refreshes the installed `sas` dispatcher, stages `C:\SASAL` through local-filesystem transfer, strips remotes, and writes `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json` with `prepared_commit` plus the SHA-256 tracked-file seal.

On the protected network, `scripts/SasPortableLauncher.ps1` / `Resolve-SasPreparedAutoLogonRuntime` is the runtime-currentness authority for the portable lane, while the universal field platform resolves the same machine-local runtime and protected bootstrap. The v2 manifest must prove prepared commit, Guest/Internet preparation classification, `LOCAL_FILESYSTEM_ONLY` transport, removed remotes, no protected bootstrap Git permission, complete SHA-256 seal, and the protected bootstrap.

If the protected-window fast path is being used, do not demand a new remote refresh simply because the machine is currently protected. Compare the locally proven prepared runtime to the selected accepted deployment floor/capability. If that proof is insufficient, stop without changing networks and state exactly what must be refreshed later on Guest/Internet.

## Network intent and restoration gate

Read `scripts/SasNetworkIntent.psm1` and use `scripts/Invoke-SasNetworkAwareField.ps1` / the installed network-aware `sas` front door instead of hand-writing WLAN or VPN transitions.

Repository intents are:

- `InternetSync` -> **GUEST / INTERNET**, for remote repository synchronization such as `sas refresh`;
- `ProtectedNorthwell` -> **PROTECTED NORTHWELL**, satisfied by approved hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN;
- `LocalOnly` -> **ANY / UNCHANGED**, and SysAdminSuite must not change the network;
- `CommandSpecific` -> command-owned admission with no generic network transition.

Required behavior:

- capture the starting classification/label/authority before changing anything, including before the freshness `InternetSync` transition;
- when the protected AutoLogon fast path is admitted, the starting protected posture is also the execution posture and there is no freshness transition to restore;
- otherwise freshness has its own `InternetSync` transition/return subtransaction; after it returns to the captured posture, resolve the product command's separate intent;
- automatic switching is saved-WLAN-profile-only and must be proven after the switch;
- do not guess or automate VPN lifecycle when no repository-proven VPN adapter exists;
- do not disable a protected wired adapter merely to reach InternetSync;
- when the network-aware wrapper switched WLANs, `Restore-SasNetworkIntent` must run in `finally` and restore the recorded starting profile;
- if restoration fails, the overall command is not successful even if the child command returned zero;
- when the operator must perform a manual VPN/hardwire transition, the handoff must state the required return posture after the command; do not claim automatic restoration;
- `%LOCALAPPDATA%\SysAdminSuite\bin\sas-leave.cmd` / `Switch-Back-To-Previous-Network.cmd` is the repository-owned local return path when an eligible saved Guest/Internet return bookmark exists. Do not invent a replacement disconnect/reconnect sequence.

## Atomic operator handoff

When the current environment cannot execute on the workstation, emit **one copy-paste PowerShell block** for the first executable field gate. Do not distribute path relocation, starting-network capture, InternetSync freshness, product-network transition, product execution, or required restoration as disconnected snippets that can be run out of order.

For an already-protected AutoLogon window, that one block must attempt the local sealed-runtime fast path first and must not perform remote Git or network switching. A fast-path rejection may report the later Guest/Internet refresh action, but must not execute it while preserving the protected window.

The block must fail closed on every material native nonzero exit. `$ErrorActionPreference = 'Stop'` is not sufficient for native commands by itself; check `$LASTEXITCODE`.

Prefer the repository-owned launcher/network-aware wrapper over embedding product or network logic in the handoff. The handoff may perform canonical-path and freshness proof around that front door, but it must not become a second implementation of `SasNetworkIntent.psm1` or `Refresh-SasOperatorCommand.ps1`.

## Procedure

1. Identify whether this is an already-protected AutoLogon `Remote` window. If yes, attempt only local sealed-runtime/capability/network admission and execute immediately when proven; otherwise fail fast without changing network posture.
2. For all other cases, resolve and enter the machine/profile canonical development authority with `canonical-path-resolution`; capture the starting network posture immediately afterward and before any transition.
3. Prove repository freshness with `repository-freshness-before-launch`; perform remote Git I/O only under the `InternetSync` network contract and return to the captured starting posture afterward.
4. If the selected execution route is a sealed runtime such as `C:\SASAL`, prove/update that runtime through its owning `sas refresh` / seal-manifest path; never substitute remote Git inside the runtime.
5. Select the canonical command from `harness/api/harness-command-registry.json` and route it through `operator-execution-route` when a registered front door exists.
6. Classify the product command's network intent from the recorded/restored starting posture.
7. Use the network-aware field wrapper for `InternetSync` and `ProtectedNorthwell` transitions; do not hand-code WLAN/VPN switching.
8. Execute the command only after the applicable path/freshness or protected-window runtime proof plus product network admission are proven.
9. Restore any automatically changed network in the same transaction. A restore failure is a failed handoff outcome.
10. Report the starting network, fast-path or freshness disposition, required product network, command exit, final restore disposition, selected repository/runtime identity when applicable, and durable evidence path.
11. Never ask the operator to run a second corrective snippet for a prerequisite that should have been included in the original handoff.

## Required agent-facing integrations

The following agent-facing owners must route to this skill when they are about to emit an operator command:

- `harness/workflows/fresh-agent-intake.yaml`;
- `harness/skills/canonical-path-resolution/SKILL.md`;
- `harness/skills/operator-execution-route/SKILL.md`;
- `.claude/skills/field-workflow/SKILL.md`;
- `.claude/skills/repository-sprint/SKILL.md`.

## Expected outputs

- canonical development path and role when repository maintenance is required;
- current/default remote identity and freshness disposition when repository maintenance is required;
- selected accepted deployment floor/capability;
- starting network classification/label/authority;
- protected-window fast-path disposition or freshness `InternetSync` transition/return disposition;
- sealed/runtime currentness and prepared commit when applicable;
- required product network intent;
- product transition method or already-satisfied protected posture;
- canonical command/front door;
- child exit code;
- final network restore disposition;
- durable evidence path when applicable;
- one exact continuation only for a genuinely unproven user-only/field-only gate.

## Proof ceiling

This skill proves handoff composition and ordering. Repository/static/CI validation cannot prove a physical workstation's current path, remote reachability, active WLAN/VPN/hardwire state, protected target access, sealed runtime bytes, or successful live restoration; those remain runtime evidence produced by the existing path, freshness, refresh/seal, network-intent, and product authorities.