# P97 — SysAdminSuite AndroidProvider Reference Architecture

Date: 2026-10-07
Status: `P97_COMPLETE_REMOTE_REFERENCE_ARCHITECTURE`
Repository: `EndeavorEverlasting/SysAdminSuite`
Floor at research start: `main@9a0d2756f77d0b41582c70bc6fa68ac1fd3829af`
Canonical contract produced by this sprint: `harness/api/sas-android-provider-boundary.v1.json`

## Capability researched

How SysAdminSuite should generalize its existing H&H CC-reader ADB work into a reusable Android management provider for PTop, AdminBox 1, and technician AdminBoxes without reinventing ADB, weakening field safety, or forcing CC-reader firmware policy into a generic transport layer.

The local starting point is already strong:

- `harness/api/hh_cc_reader_adb_control_plane.py` owns typed host/USB/device/identity/inventory/network/view states.
- `harness/api/hh_cc_reader_adb_live.py` owns the current live Platform-Tools and read-only collector.
- `harness/api/hh_cc_reader_capability_orchestrator.py` already owns topology-aware capability orchestration.
- `docs/HH_CC_READER_ADB_ADMIN_BOX_WORKFLOW.md` already states that SysAdminSuite + Admin Box are the control plane and ADB is a transport.
- the existing software-deployment and sealed-runtime contracts already provide offline distribution, artifact binding, receipts, and protected-network posture.

Therefore the local gap is **not** "build an Android device manager." The local gap is a reusable AndroidProvider seam beneath existing workloads.

## Reference set and evidence identities

| Reference | Evidence identity | License / posture | Why selected |
| --- | --- | --- | --- |
| AOSP ADB | current AOSP `packages/modules/adb` developer internals + adb(1) docs | Apache-2.0 project | Canonical client/server/adbd and SmartSocket/Transport architecture |
| Android ddmlib / Trade Federation | Android source/reference docs for DDMLIB device abstraction and Tradefed host-driven `ITestDevice` lifecycle | AOSP / Apache-2.0 | Mature host-side device abstraction, state, cleanup and test-device lifecycle |
| DeviceFarmer STF | `DeviceFarmer/stf@be79c0c9546ceb2da761c9ff2ada29d68c1f5f23` | Apache-2.0 | Host provider + per-device worker/fleet architecture and provider contention lessons |
| DeviceFarmer adbkit | `DeviceFarmer/adbkit@29a21ccdf21cbe76d3fbfecec2a1892c172b0452` | Apache-2.0 | Typed client over the ADB server, device tracking, remote-server support, USB/TCP duplicate-device warning |
| Genymobile scrcpy | `Genymobile/scrcpy@19871982cefb9de4c981c2314dfda2ac81564b48` | Apache-2.0 | Host/device component version binding, separate streams, tunnel cleanup/fallback, shell privilege ceiling |
| Appium node-adb-client | `appium/node-adb-client@4549760ca6f79f0f7dae5d41b2b1d1502774e20d` | Apache-2.0 | Proof that backend/connection-type abstraction can exist independently of the CLI |

No source code from these projects is copied by this sprint. We emulate mechanisms and contracts.

## Reference matrix

### AOSP ADB

Evidence class: **OBSERVED_IMPLEMENTED / canonical upstream**

AOSP describes three components: Client, host Server, and device-side `adbd`. Clients including the normal `adb` client and DDMLIB connect to the host Server through the SmartSocket interface; the Server communicates with devices through Transports and multiplexes streams. The adb(1) documentation describes localhost port 5037 as the default host/server endpoint and `-a` as the explicit option that widens listening to all interfaces.

Sources:

- https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/internals.md
- https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md

**ADOPT**

- ADB is a backend/transport substrate, not SAS itself.
- One SAS Android provider may own one deterministic local ADB server/toolchain.
- A future SAS client can use the host-server seam without changing workload contracts.
- Keep the server loopback-only by default.

**REJECT**

- Exposing raw ADB server port 5037 to field networks merely to make remote orchestration convenient.
- Reimplementing adbd authentication, USB transport, or packet framing before a measured need exists.

### Android ddmlib / Trade Federation

Evidence class: **OBSERVED_IMPLEMENTED / canonical Android tooling pattern**

DDMLIB exposes device objects and explicit device state instead of requiring every caller to parse raw `adb devices` text. Trade Federation builds host-driven device/test lifecycles around an `ITestDevice` abstraction, with setup/cleanup responsibilities separated from test intent.

Sources:

- https://source.android.com/reference/tradefed/com/android/ddmlib/IDevice
- https://source.android.com/docs/core/tests/tradefed/architecture/device-manager

**ADOPT**

- Stable provider/device abstraction above ADB commands.
- Explicit device/session state.
- Workload intent remains above provider mechanics.
- Cleanup belongs to the lifecycle, not to optional operator memory.

**ADAPT**

- SAS is an operations platform, not a test harness. Reuse the abstraction/lifecycle pattern, not Tradefed's test-case semantics.

### DeviceFarmer STF

Evidence class: **OBSERVED_IMPLEMENTED from source/deployment topology**

STF models provider processes attached to ADB hosts and creates device-specific workers. Its deployment guidance also exposes an important failure mode: multiple provider owners on one host can compete for devices.

Source:

- https://github.com/DeviceFarmer/stf/tree/be79c0c9546ceb2da761c9ff2ada29d68c1f5f23

**ADOPT**

- One Android-provider authority per host.
- Per-device session/lease ownership for stateful work.
- Host/provider health is distinct from individual device health.

**REJECT**

- Recreating STF's distributed fleet infrastructure now.
- Shared/default ADB private-key material. SAS nodes require node-local key material; private keys never enter Git.

### DeviceFarmer adbkit

Evidence class: **OBSERVED_IMPLEMENTED**

adbkit is a typed client to the ADB server and supports device tracking plus normal ADB functions without requiring callers to parse the CLI for each operation. Its documentation warns that after switching a device to TCP, the same physical device can appear twice (USB and TCP), which can cause incorrect simultaneous targeting.

Source:

- https://github.com/DeviceFarmer/adbkit/tree/29a21ccdf21cbe76d3fbfecec2a1892c172b0452

**ADOPT**

- Transport endpoint is an alias, not logical device identity.
- USB + TCP representations of one physical device must collapse to one bound target.
- Event-driven device tracking is a legitimate future backend capability.

**ADAPT**

- Keep Python/PowerShell/CMD SAS ownership. Do not import a Node runtime simply because adbkit proves the pattern.
- Direct server-client work is M4, not M2, unless P82 measurements show current CLI orchestration is materially deficient.

### Genymobile scrcpy

Evidence class: **OBSERVED_IMPLEMENTED**

scrcpy uses a host client plus a device-side server launched under Android's shell context. It separates video, audio, and control channels. Its client and device server require exact version agreement because their internal protocol may change. It also uses explicit ADB reverse/forward tunnel mechanics and fallbacks.

Sources:

- https://github.com/Genymobile/scrcpy/blob/19871982cefb9de4c981c2314dfda2ac81564b48/doc/develop.md
- https://github.com/Genymobile/scrcpy/blob/19871982cefb9de4c981c2314dfda2ac81564b48/app/src/adb/adb_tunnel.c

**ADOPT**

- If SAS ever packages a coupled device-side helper, bind host/device versions exactly.
- Treat view, audio, and control as separate capabilities/authority surfaces.
- Tunnel creation implies tunnel cleanup proof.

**ADAPT**

- Remote view remains an optional Android workload/provider extension, not the core AndroidProvider contract.

**REJECT**

- Treating shell-context tricks or hidden Android APIs as generic production authority.
- Turning scrcpy control capability into default technician control authority.

### Appium node-adb-client

Evidence class: **OBSERVED_IMPLEMENTED, secondary precedent**

This project implements a direct-to-device client and explicitly separates connection types; its USB implementation is one backend and the project describes TCP as another possible backend.

Source:

- https://github.com/appium/node-adb-client/tree/4549760ca6f79f0f7dae5d41b2b1d1502774e20d

**ADAPT**

- Preserve a replaceable backend seam.

**REJECT NOW**

- Owning direct USB/authentication/protocol implementation. It raises security/maintenance cost without solving a current SAS blocker.

## Solved baseline vs local gap

| Capability slice | Disposition | Evidence |
| --- | --- | --- |
| Official Platform-Tools acquisition/cache | **ALREADY_SOLVED_INTERNALLY** | `hh_cc_reader_adb_live.py`, prepare launcher |
| Typed host/USB/ADB device classification | **ALREADY_SOLVED_INTERNALLY** | H&H ADB classifier + fixtures |
| Device identity binding | **ALREADY_SOLVED_INTERNALLY** | H&H private expected identity/vendor-property seam |
| Exact-target TCP ADB prove/revert | **ALREADY_SOLVED_INTERNALLY** | H&H tcpip cert path |
| View-only remote-display classification | **ALREADY_SOLVED_INTERNALLY** | H&H remote-view cert |
| Topology/operator-presence capability DAG | **ALREADY_SOLVED_INTERNALLY** | CC-reader capability orchestrator |
| Offline package/deployment infrastructure | **ALREADY_SOLVED_INTERNALLY** | SAS authorized deployment / sealed runtime / software deployment owners |
| Generic Android provider boundary | **PROJECT_SPECIFIC_GAP — CLOSED BY CONTRACT THIS SPRINT** | `sas-android-provider-boundary.v1.json` |
| Generic reusable Android provider implementation | **PROJECT_SPECIFIC_GAP — M2** | Factor existing H&H primitives; no new device manager |
| Host-provider singleton/session lease | **AVAILABLE_TO_EMULATE_EXTERNALLY — M2** | STF pattern |
| Transport-alias collapse | **AVAILABLE_TO_EMULATE_EXTERNALLY — M2** | adbkit warning + existing SAS identity model |
| Event-driven SmartSocket backend | **EVIDENCE_GAP / CONDITIONAL M4** | Technically proven externally; local benefit unmeasured |
| Distributed fleet provider | **EVIDENCE_GAP / CONDITIONAL M5** | External precedent exists; current demand/authority not proven |

## Judgment frozen for downstream agents

1. **SysAdminSuite is the management plane.**
2. **AndroidProvider is the replaceable Android capability boundary.**
3. **ADB is the current backend, not the product architecture.**
4. **Use the existing ADB CLI backend for M2.** A direct SmartSocket backend is not M2 work.
5. **One Android provider authority per management host.**
6. **ADB server remains loopback-only by default.** Do not use `adb -a` as a field architecture.
7. **Each management node uses node-local ADB key material.** Never commit or share a default private key.
8. **Logical device identity is independent of ADB serial/USB/TCP endpoint.** USB and TCP aliases for one reader collapse to one logical target.
9. **Capability, authority, and proof are orthogonal.** Technical support never grants permission.
10. **Typed SAS operations are public; raw shell is internal plumbing.** Technician workflows do not expose arbitrary shell as the normal front door.
11. **Cleanup is a terminal gate.** Stateful transport changes, tunnel rules, and temporary device payloads require cleanup proof; failure is `INCOMPLETE`.
12. **CC-reader firmware remains a workload with its existing policy owner.** The generic provider never grants firmware mutation.
13. **The Kiosk4 USB OTG failure is scoped to that observed configuration.** It does not disable AndroidProvider or ADB globally.
14. **Field AdminBoxes are offline-first.** Qualification/acquisition occurs before protected-network execution; field success may not depend on Google/GitHub access.
15. **Do not build distributed fleet fan-out yet.** First prove the reusable single-target provider.

## P82 promotion decisions

### Candidate A — generic provider contract

Hypothesis: extracting the invariants above without altering runtime behavior will remove architectural judgment from the implementation sprint while preserving current H&H semantics.

Measure:
- semantic validator passes;
- current H&H adapter remains the named workload adapter;
- no mutation authority appears in the generic contract;
- current backend remains `adb_cli`.

Decision: **PROMOTE to M1**.

### Candidate B — direct SmartSocket backend now

Hypothesis: replacing CLI invocation now would materially improve the management plane.

Current measurement: no repository evidence demonstrates CLI parsing/process startup/event latency as a blocking problem.

Decision: **REJECT NOW / retain as M4 experiment**.

Admission condition for a future P82 experiment:
- same representative workload;
- `adb_cli` baseline;
- wall-clock, process-start count, parse failures, event latency and cleanup failures;
- candidate must materially improve operation without weakening identity, policy, or cleanup.

### Candidate C — distributed fleet provider now

Hypothesis: multi-device concurrent workers are needed now.

Current measurement: the active technician workflow is exact-target and the repository has no measured provider-contention or concurrent-device bottleneck.

Decision: **DEFER to M5**.

## Prioritized development gap

**M2 — reusable AndroidProvider implementation factored from existing H&H primitives.**

The downstream implementation must not design architecture. It must:
- extract generic host/runtime/session/device primitives;
- preserve the existing H&H adapter as a workload consumer;
- reuse existing offline SAS distribution;
- add management-node role/readiness surfaces;
- preserve all existing typed states and safety gates;
- validate through the existing H&H ADB regression suite plus the new AndroidProvider contract tests.

The exact lane ownership and acceptance gates live in:
`docs/plans/sas-android-management-plane-p04-p82-20261007.plan.md`.

## Proof ceiling

This P97 sprint proves external precedent and a repository-level design decision. It does not prove any live reader transport, technician AdminBox installation, PTop management readiness, field network behavior, firmware mutation authority, or firmware result.
