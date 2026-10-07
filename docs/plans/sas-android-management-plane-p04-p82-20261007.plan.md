# Plan — SAS Android Management Plane M2 Implementation

Date: 2026-10-07
Status: `REMOTE_JUDGMENT_COMPLETE_LOCAL_LEGWORK_READY`
Invocations: **P97 + P04 + P82**
Repository: `EndeavorEverlasting/SysAdminSuite`
Remote planning branch: `feat/sas-android-provider-boundary-20261007`
Floor used for judgment: `main@9a0d2756f77d0b41582c70bc6fa68ac1fd3829af`
Architecture contract: `harness/api/sas-android-provider-boundary.v1.json`
Prior art: `docs/research/sas-android-provider-p97-reference-architecture-20261007.md`

## Mission

Turn PTop, AdminBox 1, and technician AdminBoxes into roles of one reusable SysAdminSuite Android management platform by factoring the **already-proven H&H ADB mechanics** beneath a generic AndroidProvider boundary.

This is an implementation sprint. The architecture has been decided remotely. The local agent owns legwork, experiments, refactoring, validation, and live certification where the local environment has the required machine/device access. It does **not** own architecture selection.

## P04 runtime-partition result

The current ChatGPT/provider runtime can inspect and mutate the remote GitHub repository but cannot execute the local Windows/USB/AdminBox runtime.

Current-runtime work completed:
- canonical P97/P04/P82 prompt resolution;
- remote repository refresh/collision check;
- external prior-art investigation;
- architecture judgment;
- generic provider contract + schema;
- semantic validator + regression contract;
- durable reference architecture;
- this local execution plan.

Local-only work belongs to `LOCAL_AGENT_RUNTIME` because it requires local filesystem, Windows process, PowerShell/CMD, Platform-Tools, sealed runtime, PTop/AdminBox or reader access.

Provider access is not a host. Do not move GitHub-searchable judgment back to Cursor.

### Parallelism disposition

Repository search found **no SysAdminSuite-local implementation of TokenCorridor's `prompt_parallel_dispatch.py` / planning-runtime-partition contract**. Do not invent a competing orchestration subsystem merely to satisfy P04 form.

The M2 dependency graph has width >= 2 after the shared extraction boundary:
- Lane B (node/offline bundle) can proceed independently of Lane C's H&H adapter factoring once Lane A exposes the provider primitives.
- Documentation/fixtures can run independently after interfaces are frozen.

Current remote runtime cannot autonomously launch Cursor/OpenCode workers, therefore implementation parallelism is:

`PARALLEL EXECUTION: DEGRADED — no local-agent execution adapter is exposed to this runtime.`

`AUTONOMY_GAP: Cursor should use its repository-proven isolated worktree/subagent mechanism if available; otherwise execute lanes serially on one owned branch. The operator is not a scheduler beyond providing this one handoff.`

Do not create a new agent runner in this sprint.

## Frozen architecture — do not reopen

These are accepted decisions, not prompts for discussion.

1. **SysAdminSuite is the management plane.**
2. **AndroidProvider is the reusable Android capability boundary.**
3. **ADB is the current backend beneath AndroidProvider.**
4. **CC-reader firmware is a workload above AndroidProvider.**
5. **M2 uses the existing `adb.exe`/Platform-Tools backend.**
6. Direct SmartSocket or direct USB/protocol clients are **not M2**.
7. One AndroidProvider authority owns a host's ADB runtime/session state.
8. ADB server stays **loopback-only** by default; do not use `adb -a` as field architecture.
9. Each management node has node-local ADB authentication material; never commit/share a default ADB private key.
10. PTop, AdminBox 1 and technician AdminBoxes are **roles of one node contract**, not separate products.
11. AdminBox/reference and technician-field roles are **offline-first at execution time**.
12. Platform-Tools is a qualified bundle, not a loose `adb.exe`.
13. Effective runtime selection is deterministic; PATH/SDK competitors are reported but may not silently win.
14. ADB serial, USB transport id and TCP endpoint are aliases/evidence, not logical device identity.
15. USB and TCP aliases for the same device collapse to one logical target.
16. Ambiguous identity blocks stateful operations.
17. Technical capability, operation authority, and proof level are orthogonal.
18. A provider supporting an operation never grants authority to execute it.
19. Public technician/API surfaces are typed operations; arbitrary raw shell is internal plumbing, not the routine front door.
20. Any stateful transport change has cleanup/revert as part of success. Cleanup failure = `INCOMPLETE`.
21. Existing H&H typed states and mutation refusals remain canonical until tests prove a safe migration.
22. Kiosk4 USB OTG non-enumeration is scoped to the observed Kiosk4 configuration. Never globalize it into "ADB unavailable."
23. Existing SAS software deployment/sealed-runtime mechanisms own offline distribution. Do not build another deployment engine.
24. Existing CC-reader capability orchestrator owns topology-aware capability exploration. Do not build another device manager.
25. Remote view is optional capability/workload. It is not AndroidProvider core.
26. No firmware push, app install, reboot, settings mutation, privilege escalation, bootloader/fastboot action, or Developer Options change is authorized by this sprint.

## Read first

Mandatory:
- `AGENTS.md`
- `CODEBASE_MAP.md`
- `harness/api/sas-android-provider-boundary.v1.json`
- `schemas/harness/sas-android-provider-boundary.schema.json`
- `docs/research/sas-android-provider-p97-reference-architecture-20261007.md`
- `harness/validators/validate-sas-android-provider-boundary.py`
- `Tests/survey/test_sas_android_provider_boundary_contracts.py`

Existing implementation owners to factor:
- `harness/api/hh_cc_reader_adb_control_plane.py`
- `harness/api/hh_cc_reader_adb_live.py`
- `Tests/survey/test_hh_cc_reader_adb_control_plane_contracts.py`
- `docs/HH_CC_READER_ADB_ADMIN_BOX_WORKFLOW.md`
- `Prepare-HHCCReaderAdbHost.cmd`
- `Probe-HHCCReaderAdb.cmd`
- `Capture-HHCCReaderAdbInventory.cmd`
- `Certify-HHCCReaderAdbTcpip.cmd`
- `Certify-HHCCReaderRemoteView.cmd`
- `Evaluate-HHCCReaderAdbControlPlane.cmd`

Reuse:
- approved software/deployment manifest owners;
- sealed runtime / portable operator owners;
- canonical path registry;
- artifact/validator/outcome registries;
- SAS command routing and CMD launcher conventions;
- network authority/low-noise owners.

Search before adding any new helper.

## Target call stack

The target factoring is:

```text
technician / workload command
        |
        v
workload adapter
  H&H CC reader today
  future Android workloads later
        |
        v
SAS AndroidProvider
  - node/runtime readiness
  - device enumeration
  - logical identity binding
  - session lease
  - typed operations
  - cleanup/revert
  - typed receipts
        |
        v
ADB CLI backend (M2)
        |
        +-- SAS-owned qualified Platform-Tools
        +-- local ADB server / loopback
        +-- USB or exact-target TCP transport
        |
        v
Android adbd
```

Workloads consume provider operations. They do not search PATH or download their own ADB runtime.

## Expected provider primitives

Names are semantic requirements. Reuse repository naming conventions; do not create duplicate APIs simply to match these spelling examples.

### Runtime / host
- resolve management-node role;
- resolve qualified Android Platform-Tools bundle;
- report owned runtime + competing PATH/SDK copies;
- ensure/start local ADB server through the owned runtime;
- report server/client version;
- report field-offline readiness;
- expose no remote ADB server listener by default.

### Device / identity
- enumerate devices/transports;
- normalize raw device state into typed SAS state;
- select exactly one intended target;
- normalize transport aliases;
- bind logical identity from private expected identity/vendor properties;
- block stateful work on ambiguity.

### Session
- acquire provider/device lease before stateful transport operations;
- execute typed observe operations;
- execute separately authorized transport-state operations;
- collect command/result metadata without persisting secrets/live identity in Git;
- always enter cleanup;
- release lease only after cleanup state is recorded.

### Read-only Android operations required for M2 parity
At minimum preserve the existing H&H observation coverage:
- properties/build;
- package inventory;
- process inventory;
- interface/address/route observation;
- connectivity observation;
- device-policy observation.

Do not expand raw command authority merely because ADB offers more commands.

### Transport-state operations required for M2 parity
Preserve existing exact-target network ADB certification:
- only after prior ready/bound prerequisites;
- exact device-derived/authorized target only;
- no subnet scan;
- return to USB and prove listener/session cleanup;
- failed revert remains incomplete.

## Management-node roles

### PTop / `ptop_lab`
Purpose: lab/prototype/compatibility certification.

M2 acceptance:
- generic provider can evaluate node/runtime readiness;
- Platform-Tools bundle can be resolved deterministically;
- live Android device is optional for repository completion;
- if a local Android test target is available and authorized, produce a sanitized live receipt separately.

PTop is not a field-release prerequisite.

### AdminBox 1 / `adminbox_reference`
Purpose: reference controller.

M2 acceptance:
- can become provider-ready from the SAS-owned runtime;
- no public Internet dependency after preparation;
- reports exact runtime/version/provenance;
- existing H&H front doors remain usable.

### Technician AdminBox / `technician_adminbox_field`
Purpose: portable field controller.

M2 acceptance:
- can be provisioned with the qualified provider runtime by existing SAS deployment/package mechanisms;
- field execution does not fetch Google/GitHub;
- technician uses tracked CMD/SAS front door;
- provider status clearly states READY vs missing bundle vs conflicting runtime vs unsupported host;
- no private ADB key is shared through Git/package source.

## P04 lane ownership

### Lane A — generic provider extraction
**Host:** local agent runtime
**Dependencies:** remote M1 contract only
**Owned:** new/refactored generic Android provider Python/PowerShell internals; focused unit/fixture tests.
**Forbidden:** changing CC firmware policy, firmware mutation, new distributed orchestration, direct ADB protocol client.

Tasks:
1. Map reusable functions in `hh_cc_reader_adb_live.py` and classifier.
2. Extract the smallest generic host/runtime/device/session primitives.
3. Leave H&H-specific firmware/package/version classification above the generic seam.
4. Add a host-level provider/session lock/lease for stateful operations using existing repo patterns if one exists; otherwise implement the smallest local lock that cannot leak secrets and is released crash-safely.
5. Keep ADB server loopback-only.
6. Do not rotate/delete existing operator ADB keys automatically.

**Completion gate:** generic provider can represent runtime, enumerate/classify device states, bind target input to the workload adapter, and emit typed receipts without changing H&H results.

### Lane B — management-node/offline runtime
**Dependencies:** Lane A provider runtime interface can be known; package work can begin in parallel with later adapter factoring.
**Owned:** node-role readiness, qualified Platform-Tools bundle manifest, existing SAS deployment/offline distribution integration.
**Forbidden:** second software-deployment engine, field Internet bootstrap.

Tasks:
1. Reuse SAS package/provenance mechanism for the complete Windows Platform-Tools runtime.
2. Freeze source/version/hash/component manifest.
3. Implement provider readiness for all three roles.
4. Prove `technician_adminbox_field` can resolve a pre-staged runtime with network unavailable.
5. Detect/report PATH/SDK competitors without silently switching to them.
6. Keep node-local ADB key material outside tracked/package artifacts.

**Completion gate:** sanitized offline fixture proves field-node provider readiness without network acquisition.

### Lane C — H&H adapter migration
**Dependencies:** Lane A stable.
**Owned:** H&H ADB adapter delegation/reuse only.
**Forbidden:** outcome renames or policy change without explicit failing regression requiring it.

Tasks:
1. Route generic runtime/enumeration/session work through AndroidProvider.
2. Preserve H&H version-domain/package/device-policy interpretation in the workload layer.
3. Preserve existing command front doors.
4. Preserve the current Kiosk4 OTG-scoped finding.
5. Preserve network ADB exact-target + revert semantics.
6. Preserve `MUTATION_AUTHORIZED=false` unless another existing authority owner independently promotes it.

**Completion gate:** existing H&H ADB contract suite passes unchanged or changes only to reflect factoring, never semantic relaxation.

### Lane D — technician surface
**Dependencies:** Lanes A/B interfaces.
**Owned:** smallest repository-native Android provider status/doctor/prepare/probe surface.
**Forbidden:** generic arbitrary shell console, GUI-first replacement for CMD.

Tasks:
1. Inspect current `sas` command routing and CMD conventions.
2. Add the smallest discoverable generic Android provider front door.
3. If operator guidance is added, obey guide-to-launcher invariant.
4. Ensure every front door is working-directory and username neutral.
5. Emit typed result + evidence location + exact next action.

Conceptual user outcome (not mandated syntax):
- node/provider status;
- runtime prepare/status;
- exact target probe;
- read-only inventory.

**Completion gate:** a technician does not need to locate `adb.exe` or reconstruct raw commands.

### Lane E — validation/convergence
**Dependencies:** all mutated lanes.
**Owned:** validators, fixtures, registry/index updates, docs, final integrated proof.
**Forbidden:** papering over failures.

Tasks:
1. Run new AndroidProvider validator/tests.
2. Run existing H&H ADB suite.
3. Run relevant operational-harness registry/completeness gates after registry edits.
4. Run offline survey floor if changed surfaces trigger it and runtime supports it.
5. Run PowerShell/Pester gates for any changed PS files where available.
6. Inspect failures, fix in owned scope, rerun.
7. Record skipped live/Windows checks exactly.

## Collision map

- `hh_cc_reader_adb_control_plane.py` — **Lane C owns** workload-adapter changes.
- `hh_cc_reader_adb_live.py` — **Lane A owns** extraction until a generic provider owner exists; Lane C consumes afterward.
- command/validator/artifact registries — **Lane E owns** final edits.
- shared package/deployment owners — **Lane B owns** only bounded Android-runtime integration; do not rewrite generic deployment.
- `AGENTS.md` — forbidden unless a demonstrated governance defect blocks M2.
- CC firmware policy — forbidden.

One writer owns each shared file.

## P82 prototype ladder

Do not implement M2 in one rewrite.

### P82-1 — runtime/provider extraction

**Hypothesis:** current CC-specific ADB host/runtime mechanics can move behind a generic provider without changing observable H&H classification.

**Build:** extract only runtime resolution + server/device enumeration.

**Measure:**
- new provider focused tests;
- existing H&H ADB test suite;
- fixture outputs before/after for current states.

**Decision:**
- KEEP if H&H semantics stay identical and generic code loses CC-specific policy.
- REFINE if generic seam still imports firmware/version policy.
- REVERT if factoring changes safety or typed results without necessity.

### P82-2 — identity/session lifecycle

**Hypothesis:** provider lease + logical identity aliases eliminate cross-transport ambiguity without weakening current exact-target behavior.

**Build:** normalize aliases and session/cleanup receipt around existing operations.

**Measure:**
- no-device / unauthorized / ready fixture;
- multiple device ambiguity;
- same logical device represented by USB+TCP;
- cleanup/revert failure;
- concurrent provider/stateful-operation contention fixture.

**Decision:** promote only if ambiguity blocks safely and cleanup failure cannot be reported as success.

### P82-3 — offline node readiness

**Hypothesis:** existing SAS package/runtime mechanisms can prepare a technician AdminBox without Internet at execution time.

**Build:** qualified offline Platform-Tools bundle + node readiness.

**Measure:**
- pristine offline field fixture;
- missing bundle;
- corrupt/incomplete component manifest;
- wrong hash;
- competing PATH ADB;
- correct owned runtime;
- network acquisition disabled.

**Decision:** field role reaches READY only from the qualified local bundle.

### P82-4 — H&H adapter convergence

**Hypothesis:** H&H can consume AndroidProvider without behavioral regression.

**Build:** delegate generic primitives.

**Measure:** full existing H&H ADB contracts plus new provider contracts.

**Decision:** only promote if current typed outcomes, mutation refusal, OTG scope, exact-target TCP and revert requirements remain intact.

### Explicitly deferred P82 experiments

**SmartSocket/direct server client:** do not prototype until measured CLI process/parse/event overhead becomes material.

**Fleet parallel workers:** do not prototype until representative concurrent-device demand/provider contention is measured.

**Remote raw ADB server:** rejected as architecture, not an experiment target.

## Acceptance gates

### A — architecture
- contract validator passes;
- no second device-manager architecture;
- workloads consume provider; provider consumes ADB backend.

### B — offline management node
- technician field role has no public Internet runtime prerequisite;
- Platform-Tools bundle has source/version/hash/component/provenance evidence;
- corrupt/missing bundle fails closed.

### C — security
- host ADB server defaults loopback;
- no shared tracked private ADB key;
- arbitrary raw shell not routine technician API;
- capability never grants authority.

### D — identity
- ADB serial/TCP endpoint cannot become logical identity by assumption;
- multi-device ambiguity blocks;
- USB+TCP aliases of one bound target normalize correctly.

### E — lifecycle
- stateful transport operation uses lease;
- cleanup/revert is part of completion;
- cleanup failure cannot become success.

### F — H&H compatibility
- `python Tests/survey/test_hh_cc_reader_adb_control_plane_contracts.py` passes;
- firmware mutation semantics are unchanged;
- Kiosk4 USB finding stays configuration-scoped.

### G — evidence
Final report distinguishes:
- designed;
- implemented;
- repository validated;
- integration validated;
- local live certified;
- field/production verified.

Never promote a lower proof.

## Required validation order

At minimum:

```text
python harness/validators/validate-sas-android-provider-boundary.py
python Tests/survey/test_sas_android_provider_boundary_contracts.py
python Tests/survey/test_hh_cc_reader_adb_control_plane_contracts.py
python harness/validators/validate-hh-cc-reader-firmware-policy.py
```

After registries/indexes are changed:

```text
python harness/validators/validate-harness-registries.py
python Tests/survey/test_operational_harness_completeness_contracts.py
```

If practical for the changed scope:

```text
bash tests/survey/run_offline_survey_tests.sh
git diff --check
python scripts/check-repo-text-policy.py --cached
```

Run applicable PowerShell/Pester tests for any PowerShell changes.

A skipped check requires a reason.

## Live-cert boundary

Repository completion does not require touching a production CC reader.

When local authorized hardware is available, live certification may prove only the exact operation authorized in that context.

Do not:
- enable Developer Options to make ADB appear;
- broaden from exact target to subnet scanning;
- install/reboot/update a reader merely to prove the provider;
- treat PTop success as production-reader success;
- treat current Kiosk4 USB failure as provider failure.

Live receipts stay ignored/private per existing repository policy.

## Definition of done for the Cursor sprint

M2 is complete only when:

1. a reusable AndroidProvider implementation exists behind the contract;
2. PTop/AdminBox/reference/technician node roles resolve deterministically;
3. field role works from a qualified offline runtime;
4. H&H adapter consumes/reuses the generic seam;
5. existing H&H front doors remain valid or delegate compatibly;
6. generic technician front door exists for provider status/readiness;
7. identity aliases and session cleanup rules are implemented;
8. focused + regression + applicable harness tests pass;
9. exact changed files, test output, skipped checks and proof ceiling are reported;
10. changes are committed/pushed/PR'd or integrated per refreshed provider truth.

## Cursor final-response contract

Return:

- **COMPLETED WORK**
- **CREATED/MODIFIED FILES**
- **EXISTING MECHANISMS REUSED**
- **DUPLICATE MECHANISMS AVOIDED/REMOVED**
- **P82 ITERATIONS** — hypothesis → build → measured result → decision
- **VALIDATION** — exact command + pass/fail
- **SKIPPED CHECKS + WHY**
- **LIVE CERTIFICATION** — exact device/host/topology and proof ceiling, if any
- **UNRESOLVED GAPS/RISKS**
- **ARTIFACT / RECEIPT PATHS**
- **BRANCH / PR / COMMIT / GIT STATUS**
- **DEPLOYMENT / PRODUCTION STATE**
- **NEXT USEFUL COMMAND OR DECISION**

Do not ask the operator to choose architecture already frozen above.

## Exact first local action

Refresh provider truth, resolve the canonical local SysAdminSuite development path through repository authority, create/use one isolated implementation branch/worktree, then inspect the read-first set and begin **P82-1 runtime/provider extraction**.

Do not begin by rewriting this plan.
