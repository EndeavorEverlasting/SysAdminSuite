# Plan — H&H CC Reader Topology-Aware Capability Exhaustion + Presentation Projection

Date: 2026-10-06
Status: REMOTE_EXECUTION_PLAN
Invocations: P00 + P01 + P04 + P82
Repository: EndeavorEverlasting/SysAdminSuite
Verified floor at authoring: origin/main@52ba9f9cf2fb291be8d1bb3d2c4e1a72809d5607
Current floor proof: PR #506 / confirmed Kiosk4 micro-USB/OTG seated while Android/PAX client enumeration remained absent
Mutation authority: false unless an existing explicit firmware/update gate separately authorizes a controlled action

## Mission

Turn the last week of CC-reader technical exploration into a deterministic SysAdminSuite program that:

1. exhausts technically credible control/update paths without requiring the operator to babysit probes;
2. treats physical topology, human presence, and operator interruption cost as first-class execution inputs;
3. converts inconclusive/time-limited human-gated attempts into deferred evidence rather than terminal program failure;
4. preserves every closed, proved, deferred, credential-gated, or unproven avenue in a machine-readable capability ledger;
5. factors repeatable behavior into Python/core logic, CMD technician front doors, and the actual TypeScript/UI seam when one exists;
6. projects every meaningful technical win into the existing CC-reader presentation source/deck under the P01 executive-language and P95 cinematic proof contracts;
7. leaves local agents with legwork, not judgment.

This plan supersedes any critical path that still says “wait for USB READY” for the already-tested Admin Box + Kiosk4 OTG configuration.

## P00 doctrine correction — physical topology is execution state

The recurring defect is assuming the Admin Box, reader USB connection, reader LAN connection, operator, and Internet source are co-located.

They are not.

The harness must model physical state explicitly.

Required topology profiles:

- DESK_COMPUTER_AVAILABLE
  - operator keeps normal computer workflow
  - reader may be elsewhere
  - repo engineering, cloud/vendor API work, Drive/reporting, public research, offline fixtures all remain runnable
- DESK_USB_ATTENDED
  - reader physically beside Admin Box
  - USB/service-cable experiments possible
  - network may not be available to the reader
  - operator can see/tap device prompts
- LAB_READER_ON_NETWORK_OPERATOR_ABSENT
  - reader is returned to its normal/convenient LAN/Internet source
  - operator is not continuously watching the terminal
  - device-side prompt-dependent results are inconclusive/deferred, not rejected
- LAB_READER_ON_NETWORK_ATTENDED
  - short bounded visit to observe/tap prompts or menus
  - batch every known attended discriminator into this window
- ADMIN_BOX_RELOCATED_TO_LAB
  - high operator-interruption cost
  - same-network workstation probes become available
  - use only after lower-cost independent lanes are exhausted
- DUAL_TRANSPORT_ATTENDED
  - reader and Admin Box have both a proven client/ADB transport and a common approved network
  - optional/high-cost special case, never an assumed prerequisite

Every live command/probe must declare:
- required_topology
- operator_presence = none | optional | required
- interruption_cost = zero | low | medium | high
- expected_timeout
- independent_successors
- attended_retry_successor
- reopen_condition

A missing topology is not CAPABILITY_ABSENT.

## P01 harness correction — non-terminal probe semantics

The current program is too linear when a probe can encounter a human prompt.

Implement a DAG/orchestrator model.

Required result families:

- PROVEN_POSITIVE
- PROVEN_NEGATIVE
- INCONCLUSIVE_ATTENDED_GATE
- INCONCLUSIVE_TIMEOUT
- DEFERRED_TOPOLOGY_UNAVAILABLE
- DEFERRED_OPERATOR_PRESENCE_REQUIRED
- CREDENTIAL_GATE
- AUTHORITY_GATE
- POLICY_REFUSAL
- NOT_APPLICABLE
- NOT_YET_TESTED

Rules:

1. A timeout is evidence.
2. A timeout must never silently become “capability absent.”
3. If a command could be waiting on a local screen/RSA/pairing/approval dialog, emit an attended-gate result and continue every independent runnable branch.
4. Do not require the operator to sit beside the reader while unrelated engineering/research/API work runs.
5. At the end of an unattended pass, emit one consolidated ATTENDED_WINDOW_MANIFEST containing every action that truly requires a person.
6. Never ask the operator to relocate/surrender the Admin Box until all zero/low-cost independent lanes are exhausted.
7. A single failed branch must not terminate the whole capability program.

Minimum attended-gate catalog:

- Android USB debugging RSA authorization, if ADB client transport ever appears
- Android 11+ Wireless Debugging enable/pairing-code or QR flow, if the actual reader OS supports it and policy permits it
- AirViewer attended Remote View approval
- AirViewer attended Full Remote Control approval
- AirViewer resume-session approval
- any local system/update confirmation dialog discovered by a real probe
- any Wi-Fi/profile change that requires local device UI
- any vendor-tool pairing code or screen token discovered by a real probe

Known unattended-capable prior art must remain separate:
- PAXSTORE Open API terminal/firmware operations when authorized
- PAXSTORE AirViewer unattended mode only when the exact model/role/service is proved configured
- vendor/device-originated OTA/control-plane traffic
- repo/offline fixture validation

## Current evidence floor — do not rediscover

As of main@52ba9f9:

- ADB host tooling: PROVEN / ADB_HOST_READY.
- Admin Box + Kiosk4 confirmed micro-USB/OTG: REJECTED AS DEPLOYMENT TRANSPORT for this configuration after operator-confirmed seating still produced USB_DEVICE_NOT_ENUMERATED.
- USB ADB session on this configuration: not available because no Android/PAX client interface enumerated.
- A80 OTG receptacle existence remains vendor-documented; alternative cable/service-tool/policy explanations remain hypotheses, not deployment dependencies.
- local Connectivity Test / Netstat / Network Settings / generic menu crawl are closed unless new evidence changes device state.
- historical reader IP was not safely reusable and produced DEVICE_MISMATCH in the latest exact-target run.
- USB and LAN capability planes are independent.
- P97 capability frontier remains canonical research history.
- PAXSTORE terminal observation seam exists in SAS.
- PAXSTORE firmware mutation adapter does not yet exist in SAS.
- current target campaign semantics remain governed by existing firmware policy; this plan does not invent a new target or current version.
- open PR #476 owns guest/shared-LAN identity-tranche hardening; do not collide with its owned files without reconciling provider truth first.

## Resolved external prior art and consequences

### A80 network capability

Official PAX A80 material documents Wi-Fi, Bluetooth and Ethernet and Android 6.0/7.1/10.0 variants.

Consequence:
- Wi-Fi co-location is a legitimate hypothesis.
- Do not assume the exact Kiosk4 is configured/authorized for Wi-Fi.
- Do not assume Android 11 wireless pairing exists on this model/fleet.

Source:
https://www.paxtechnology.com/a80
https://www.pax.us/wp-content/uploads/2023/02/A80PCI6.X-Datasheet-6.1.22.pdf

### Android ADB over network

Google documents:
- Android 10 and lower: common Wi-Fi + initial USB ADB session, adb tcpip, then disconnect USB and adb connect.
- Android 11+: direct wireless debugging exists, but pairing requires device-side enablement and QR/pairing code.

Consequence:
- current confirmed OTG non-enumeration blocks the standard Android-10-and-lower bootstrap on this configuration;
- direct wireless pairing is not a primary path unless the actual OS proves >=11 and the setting is permitted;
- an already-listening/vendor-enabled exact-target network ADB service remains a separate observation hypothesis, not permission to scan.

Source:
https://developer.android.com/tools/adb

### PAXSTORE terminal and firmware APIs

Official PAXSTORE Open API SDK documents:
- get terminal by serial/TID with installed firmware/app/OS details;
- push firmware by serial/TID + exact fmName;
- Wi-Fi/cabled-network-only download selection;
- push history;
- push task retrieval;
- suspend/disable unfinished firmware push;
- delete firmware push task;
- typed server outcomes such as terminal missing, firmware missing/offline, and model mismatch.

Consequence:
PAXSTORE API is a first-class production-control hypothesis, not merely a documentation fallback.

Sources:
https://github.com/PAXSTORE/paxstore-openapi-java-sdk/blob/master/docs/TERMINAL_API.md
https://github.com/PAXSTORE/paxstore-openapi-java-sdk/blob/master/docs/TERMINAL_FIRMWARE_API.md

### PAXSTORE AirViewer human-gate behavior

Official AirViewer QRG documents:
- attended view/control requests can require terminal approval and time out after 60 seconds;
- unattended mode is role/model/configuration dependent and can auto-connect after 15 seconds when no one declines.

Consequence:
A remote-view timeout under operator-absent topology is INCONCLUSIVE_ATTENDED_GATE unless unattended eligibility is already proved.

Source:
https://www.pax.us/wp-content/uploads/2024/02/PAXSTORE-AirViewer-QRG-11-05-2023-V1.3.pdf

### Android OTA portability

AOSP documents:
- incremental OTA packages are source-build-bound;
- OTA metadata can bind pre-device and pre/post fingerprints/builds;
- A/B/update_engine payloads are manufacturer/client controlled;
- Verified Boot and rollback protection constrain arbitrary image reuse.

Consequence:
Do not reject reader-to-reader firmware recovery. Instead classify exactly what can be recovered:
- vendor-signed full OTA;
- incremental OTA tied to a source build;
- A/B payload;
- vendor updater cache/object;
- APK;
- generic system partition image;
- device-specific/security/payment partition.

Only then determine whether the artifact is safely reusable across the fleet.

Sources:
https://source.android.com/docs/core/ota/tools
https://source.android.com/docs/core/ota/ab
https://source.android.com/docs/security/features/verifiedboot/avb

## P04 execution order — operator-cost-first

### Tier 0 — zero interruption / execute now

Run in parallel where files do not collide:

A. PAXSTORE API adapter
- extend existing PAXSTORE observe/auth conventions;
- implement read-only terminal inventory first;
- implement firmware preview/status adapter;
- add mutation methods behind existing explicit firmware authority gates;
- fixtures/mocks only for push tests unless live authorization separately exists.

B. Firmware-source/provenance classifier
- classify vendor marketplace object, vendor-signed package, authorized reader-recovered signed OTA, incremental OTA, A/B payload, APK, raw generic partition, device-specific partition, unverified web/torrent artifact;
- SHA256 is identity, not provenance;
- public/torrent source never becomes production-admitted merely because the hash is stable.

C. Reader-to-reader recovery evaluator
- preserve the operator hypothesis that a known-good reader may supply a reusable firmware artifact;
- do not reject the path generically;
- build deterministic read-only probes for package/cache/payload/image discovery once a capable transport exists;
- model same-model/build cohort eligibility and exclusion of device-unique/security/payment state.

D. Capability-ledger + presentation projection contract
- implement a machine-readable ledger as the authoritative summary of every avenue;
- presentation output is a projection from evidence, never an agent-written memory dump.

E. Attended-window planner
- derive all known human-gated experiments from the capability ledger;
- batch them by physical location/topology and minimize operator interruption.

### Tier 1 — reader on network, operator absent

Run only what the topology actually permits.

Examples:
- PAXSTORE/OpenAPI observations and task/status checks;
- vendor cloud/TMS/control-plane observations when credentials exist;
- device last-seen/firmware/app inventory through authorized management plane;
- AirViewer only if unattended eligibility is already proved;
- externally observable phone-home/status evidence already authorized by network policy.

If an operation may be waiting on a local terminal approval:
- bounded timeout;
- write receipt;
- state INCONCLUSIVE_ATTENDED_GATE;
- queue it for attended batch;
- continue independent work.

Do not infer rejection from silence.

### Tier 2 — short attended network-side visit

Before relocating the Admin Box, consolidate every local-screen requirement into one manifest.

Potential experiments, only when applicable:
- inspect actual Android/PayDroid version;
- determine whether Wi-Fi is already configured/available;
- if separately authorized, prove a temporary/approved Wi-Fi topology and restore original network state afterward;
- Android 11+ Wireless Debugging pairing discriminator only if OS >=11 and policy permits it;
- AirViewer attended view approval;
- AirViewer full-control approval as a distinct later capability;
- vendor pairing/approval prompts discovered in Tier 0/1;
- exact screen text for any previously timed-out operation.

Do not repeat already-closed menu crawl.

### Tier 3 — Admin Box relocation to lab / high interruption

This is expensive because it suspends normal operator workstation use.

Run only after Tiers 0–2 have produced an explicit remaining manifest.

At this window:
- refresh exact reader identity/IP rather than trusting historical IP;
- run exact-target same-network probes;
- never broad-scan;
- attempt existing-listener network ADB observation only if the design can prove exact-target identity and can avoid leaving mutation/debug exposure behind;
- correlate management-plane action with permitted network metadata where useful;
- run any same-network protocol/client proof that cannot be performed remotely.

The orchestrator must stop asking for the Admin Box move once every HIGH_COST-required capability is closed, proved, or explicitly deferred by policy/credentials.

### Tier 4 — special service/USB revisit

Only reopen the USB/client path with new evidence:
- known-good data/service cable;
- vendor-defined programming accessory/tool;
- provider documentation showing client/debug path;
- policy change explicitly authorizing a new device-side USB posture.

“Try the same OTG connection again” is not a new discriminator.

## Reader-to-reader firmware spread — required proof tree

The operator explicitly retains the hypothesis that firmware from a known-good reader may be reusable across the 656 remaining campaign readers.

Do not collapse this into “unsafe cloning.”

Implement a proof tree:

1. ARTIFACT_DISCOVERY
   - package/updater cache visible?
   - standard OTA ZIP?
   - A/B payload?
   - APK?
   - raw partition?
   - vendor object/package identifier only?

2. PROVENANCE
   - vendor signature/manifest?
   - source management plane?
   - source terminal/build/model?
   - cryptographic digest?
   - original package metadata?

3. PORTABILITY
   - full vs incremental?
   - source-build precondition?
   - target model/SKU?
   - Android/PayDroid version?
   - same hardware cohort?
   - rollback index/AVB constraints?

4. DEVICE-UNIQUE EXCLUSION
   - do not clone userdata, secrets, merchant provisioning, keys, secure element, TEE/RKI material, IMEI/device identity, payment configuration, or other unique state;
   - distinguish generic signed firmware partitions from device-specific state.

5. SUPPORTED_APPLY_MECHANISM
   - vendor updater;
   - recovery/sideload;
   - update_engine/payload;
   - PAXSTORE/vendor OTA;
   - authorized partner/service tool;
   - another proved supported mechanism.

6. ONE-READER PILOT
   - only after existing SAS identity/current-version/target/authority/recovery gates pass.

7. COHORT EXPANSION
   - derive eligible cohort from actual metadata, never from “all A80s” by assumption.

The end state may be:
- PROVEN_REUSABLE_SIGNED_ARTIFACT
- PROVEN_REUSABLE_FOR_SOURCE_BUILD_COHORT
- PROVEN_VENDOR_OBJECT_ONLY
- PROVEN_NOT_PORTABLE
- INCONCLUSIVE_TRANSPORT_REQUIRED
- INCONCLUSIVE_PRIVILEGE_REQUIRED
- POLICY_REJECTED
- UNKNOWN

## Deterministic code factoring

Application behavior must not live only in agent prompts.

Python owns:
- probe/orchestrator state machine;
- topology + attendance + interruption-cost model;
- capability ledger;
- PAXSTORE/vendor API adapters;
- firmware/provenance/portability classifiers;
- receipts;
- source/package verification;
- presentation projection data.

CMD owns:
- technician/operator Windows front doors;
- one-command invocation;
- terse typed stdout;
- stable exit-code contract;
- zero substantial decision logic.

PowerShell may remain a Windows transport/collector implementation where existing SAS patterns already use it, but policy/state classification stays canonical.

TypeScript:
- first locate the real SAS/app UI boundary;
- consume the same JSON/schema vocabulary;
- do not invent a disconnected TypeScript runtime merely to satisfy a file-extension request;
- if the presentation/dashboard UI is in another canonical repo, emit a versioned contract and route the consumer there.

Suggested front doors are descriptive, not mandates; inspect/reuse naming first:
- Evaluate-HHCCReaderCapabilityProgram.cmd
- Observe-HHCCReaderNetworkControlPlane.cmd
- Inspect-HHCCReaderFirmwareSource.cmd
- Evaluate-HHCCReaderFirmwarePortability.cmd
- Observe-HHCCReaderPaxstoreFirmware.cmd
- Plan-HHCCReaderAttendedWindow.cmd

## Capability ledger contract

Add or extend a canonical schema containing at least:

- capability_id
- capability_name
- control_plane
- required_topology
- operator_presence
- interruption_cost
- authority_requirement
- credential_requirement
- implementation_state
- evidence_state
- latest_result
- latest_receipt
- attempt_count
- attended_retry_required
- next_reopen_condition
- independent_successors
- current_proof_ceiling
- field_value
- fleet_value
- presentation_disposition
- stakeholder_translation
- privacy_classification

The ledger must support computed metrics:
- total avenues modeled;
- technically attempted;
- proved positive;
- proved negative/closed;
- inconclusive attended;
- credential-gated;
- authority-gated;
- topology-deferred;
- implemented but not live-certified;
- fleet-deployment-capable.

Never hardcode a presentation metric when it can be derived from ledger state.

## P01 presentation projection

Existing Drive/P01/P95 artifacts establish that technical experiences are presentation inputs.

Every material capability transition must produce one of:

- PRESENTATION_DELTA_REQUIRED
- PRESENTATION_DELTA_NOT_REQUIRED with a reason

“Material” includes:
- new proof of a control plane;
- closure of an avenue;
- new attended/unattended behavior;
- a new deterministic SAS function;
- package/source acquisition proof;
- a portability result;
- PAXSTORE/API capability proof;
- pilot/update proof;
- a major reduction in operator field effort.

Projection rules:
- internal enum/protocol labels remain in evidence/ledger;
- stakeholder artifact uses Finding -> Consequence -> Next decision;
- no prompt/P-number/harness language on visible slides;
- no raw serial/MAC/IP/credentials;
- no claim exceeds proof.

Required project views:
1. capability exhaustion map;
2. operator-cost ladder showing what was proved without disrupting normal work;
3. update-source portfolio;
4. automation maturity: one-off attempt -> deterministic SAS command -> live proof;
5. fleet leverage: one-reader proof -> eligible cohort -> remaining gates;
6. dead ends retained as avoided future labor, not hidden failures.

Existing presentation source:
CC Reader Firmware Protocol Portfolio — Presentation Source
Existing current executive artifact:
Kiosk4 Firmware Gate — Executive Cinematic v2 — 2026-10-05.pptx

Do not manually rebuild the deck on every low-value test. Accumulate evidence transitions and project coherent scenes from the ledger.

## P82 experiment loop

For every capability:

HYPOTHESIS
-> cheapest safe discriminator
-> execute
-> measure
-> type result
-> persist receipt
-> update capability ledger
-> continue independent successors
-> queue attended/high-cost successor if needed
-> project material impact
-> refine implementation
-> rerun only when there is a new discriminator

A failure or timeout without classification is not completion.

A classified negative result is a project win when it closes a branch and prevents repeated field labor.

## Required tests

Fixture/contract coverage must include at least:

- confirmed OTG seated + no enumeration stays closed for current configuration;
- human-gated probe timeout -> INCONCLUSIVE_ATTENDED_GATE, not PROVEN_NEGATIVE;
- independent branches continue after an attended gate;
- topology mismatch -> DEFERRED_TOPOLOGY_UNAVAILABLE;
- attended-window manifest batches multiple human actions;
- high-cost Admin Box relocation is not selected while lower-cost runnable work remains;
- Android <=10 wireless ADB requires prior USB bootstrap under standard Google flow;
- Android >=11 pairing flow is attended unless already paired/trusted;
- AirViewer 60-second attended timeout classification;
- AirViewer unattended mode remains conditional on model/role/config evidence;
- PAXSTORE terminal observe fixture;
- PAXSTORE firmware preview/history/task fixture;
- mutation refused by default;
- firmware not found/offline/model mismatch;
- signed full OTA metadata;
- incremental OTA source-build match/mismatch;
- A/B payload classification;
- raw-partition artifact not automatically admitted;
- device-unique/security partition excluded;
- capability-ledger metric derivation;
- presentation delta translation contains no internal state tokens/private identifiers;
- no live secrets in receipts.

## Acceptance gates

This successor sprint is complete only when:

1. the topology/attendance/interruption-cost contract is implemented and validated;
2. current #506 OTG negative proof is consumed rather than reopened;
3. one orchestrator can continue independent work after timeout/human-gate results;
4. one attended-window manifest can be generated;
5. PAXSTORE terminal + firmware control adapter exists behind fail-closed gates;
6. reader-to-reader firmware portability is represented as a proof tree, not rejected by assumption;
7. firmware source/provenance is machine-classified;
8. capability ledger derives exhaustion metrics;
9. technical commands/logic are factored into reusable SAS files;
10. TypeScript consumes the canonical contract only at the actual UI boundary;
11. presentation projection rules are wired to material capability transitions;
12. focused tests and existing affected validators pass;
13. git diff --check passes;
14. commit/push/PR evidence is reported;
15. live proof and repository proof are reported separately.

## Forbidden scope

- broad subnet scanning;
- credential attack;
- TLS interception;
- bootloader unlock;
- verified-boot disable;
- root/elevation attempts on the payment reader;
- cloning device-unique/payment/security state;
- firmware mutation without explicit existing authority gates;
- inventing current firmware;
- treating campaign target as observed current firmware;
- torrents/public mirrors as production-admitted provenance;
- re-running closed menu/Netstat/Connectivity work without new evidence;
- re-running the same confirmed OTG path without a new discriminator;
- moving the Admin Box to the lab merely because one low-cost branch is blocked.

## Integration/collision boundaries

- refresh origin/main and active PRs immediately before writing;
- open PR #476 owns guest/shared-LAN identity-tranche hardening; reconcile before touching overlapping reader-probe identity logic;
- reuse current firmware policy, live-execution boundary, artifact/command/validator registries, PAXSTORE observe seam, ADB classifier, and presentation contracts;
- do not create parallel authorities;
- live identifiers/private evidence remain ignored/untracked.

## Final report contract

CHANGED:
PROVED:
LIVE-CERTIFIED:
REPOSITORY-VALIDATED:
CAPABILITY METRICS:
ATTENDED WINDOW QUEUE:
HIGH-COST WORK REMAINING:
PRESENTATION DELTAS:
FILES:
TESTS:
ARTIFACTS:
SKIPPED CHECKS + WHY:
RISKS/GAPS:
GIT STATUS:
COMMIT:
PUSH:
PR:
DEPLOYMENT/PRODUCTION STATE:
NEXT EXACT TRANSITION:

Never claim deployment/production proof from repository tests.

## Cursor/OpenCode execution disposition

Do not return another plan unless provider truth shows this plan is internally inconsistent.

Recover the current repository floor and execute the owned implementation in bounded lanes.

Parallelize safe work:
- Lane A: topology/attendance DAG + capability ledger
- Lane B: PAXSTORE terminal/firmware adapter + fixtures
- Lane C: firmware provenance/reader-to-reader portability classifier
- Lane D: presentation projection contract + tests

Then converge through existing registries/docs/tests and run affected validation.

Live reader work is opportunistic and topology-bound. Do not block repository implementation waiting for the operator to stand beside the reader.

The operator is returning the reader to its lab/network location and retaining normal use of the Admin Box/computer. Treat that as the current physical state.
