# SAS AndroidProvider M2 Complete-Suite Execution Handoff — PTop Same-LAN Certification

Date: 2026-10-07
Status: REMOTE_JUDGMENT_COMPLETE_LOCAL_IMPLEMENTATION_REQUIRED
Invocations: P01 + P04 + P82
Repository: EndeavorEverlasting/SysAdminSuite
Authoring floor: main@2b63c6afd032c3c36fa6d6e615032fcebeb5cee4
Architecture owner: harness/api/sas-android-provider-boundary.v1.json
Parent implementation plan: docs/plans/sas-android-management-plane-p04-p82-20261007.plan.md

## Execution frame

Repo: EndeavorEverlasting/SysAdminSuite
Sprint: SAS AndroidProvider M2 Complete Suite
Primary local host for live certification: PTop
Secondary/reference host: AdminBox One
Lane goal: implement and locally certify the reusable AndroidProvider suite without redesigning the accepted architecture.

Owned scope:
- generic AndroidProvider runtime, identity, session, typed operations, evidence and cleanup;
- qualified Android Platform-Tools bundle/runtime resolution;
- PTop/AdminBox/technician node readiness;
- H&H CC-reader adapter migration to the generic provider;
- technician/operator front doors;
- focused fixtures, tests, validators, registry wiring and handoff docs;
- authorized live PTop same-LAN certification.

Forbidden scope:
- changing H&H firmware target/acceptance policy;
- treating ADB capability as firmware-mutation authority;
- subnet/port scanning for readers;
- shared/default ADB private keys;
- `adb -a` or remote host-server exposure;
- arbitrary raw-shell technician APIs;
- Developer Options/debugging changes without separate authorization;
- bootloader/fastboot/root/remount/verified-boot weakening;
- second software-deployment engine;
- second device manager;
- broad refactors unrelated to AndroidProvider M2.

Expected artifacts:
- generic provider implementation;
- typed provider/session receipts;
- qualified Platform-Tools manifest and offline-readiness path;
- node-role status/doctor/prepare/probe/inventory CMD/SAS front doors;
- H&H adapter delegation with regression parity;
- PTop live-cert evidence stored local/ignored;
- deterministic tests/fixtures/validators;
- final sprint report with exact proof levels.

Proof ceiling:
- repository and integration proof after tests;
- local-live proof only for operations actually executed against authorized hardware;
- no firmware deployment or production claim unless separately authorized and evidenced.

## P01 — harness/infrastructure completion

Do not create a parallel subsystem. Extend the existing operational harness.

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, the AndroidProvider contract/schema/validator/tests, and the H&H ADB workflow/control-plane/live collector before mutation.
2. Search registries and existing command conventions before adding paths.
3. Add generic provider implementation behind the frozen `sas-android-provider-boundary/v1` contract.
4. Register any new command, validator, artifact, outcome, or launcher through existing registries.
5. Reuse canonical path/runtime/evidence conventions. Local/live evidence remains ignored and never committed.
6. Preserve the guide-to-launcher invariant: technician-facing executable guidance must resolve to repository-owned CMD/SAS front doors.
7. Fail closed on missing runtime, ambiguous device identity, unsupported node role, stale checkout, cleanup failure, or authority gap.

## P04 — implementation partition and one-writer lanes

### Lane A — Provider core
Owner: generic provider implementation.
Extract reusable mechanics from `harness/api/hh_cc_reader_adb_live.py` and the control-plane without moving H&H firmware policy downward.

Required capabilities:
- deterministic Platform-Tools selection;
- client/server version reporting;
- loopback-only ADB server lifecycle;
- device enumeration and typed state normalization;
- exact target selection;
- logical identity binding independent of USB/TCP aliases;
- per-device/provider lease for stateful transport operations;
- typed receipts;
- cleanup/finalization that cannot report success if revert fails.

### Lane B — Node/runtime portability
Owner: management-node readiness and bundle qualification.

Implement one provider contract across:
- `ptop_lab`
- `adminbox_reference`
- `technician_adminbox_field`

Required behavior:
- clone SASS on a supported Windows computer, run tracked preparation, and resolve a qualified SAS-owned Platform-Tools bundle;
- no public Internet requirement at execution time;
- report competing PATH/SDK ADB copies without silently using them;
- keep ADB key material node-local and outside tracked/package artifacts;
- provide explicit READY / MISSING_BUNDLE / HASH_MISMATCH / COMPETING_RUNTIME / UNSUPPORTED_HOST style states.

PTop distinction:
- PTop is currently on the same network as the target CC reader and is the preferred live same-LAN certification host.
- This fact is reachability context only. It does not establish ADB authorization, device identity, or firmware authority.
- PTop may use exact-target LAN ADB only after identity is independently bound and the workload gate authorizes the transport-state transition.

AdminBox One distinction:
- AdminBox One remains the reference/offline field controller.
- It must be able to perform the same provider operations from a sealed/prepared runtime without Internet.
- Do not require PTop-specific LAN topology for AdminBox readiness.

### Lane C — H&H workload migration
Owner: H&H adapter only.

- Route generic runtime/enumeration/session mechanics through AndroidProvider.
- Preserve existing typed H&H outcomes, mutation refusals, Kiosk4-scoped USB finding, exact-target TCP behavior, firmware classification, and policy authority.
- Existing front doors remain compatible.
- `MUTATION_AUTHORIZED=false` remains unchanged unless an existing independent authority promotes it.

### Lane D — Technician surface
Owner: user-facing command surfaces.

Deliver tracked, working-directory-neutral front doors for:
- provider status / doctor;
- runtime prepare / verify;
- exact-target probe;
- read-only inventory;
- exact-target network-ADB certification;
- optional view-only remote display when already supported;
- evidence summary / last-run result.

The technician should never need to locate `adb.exe`, reconstruct raw shell commands, or infer which host/runtime copy to use.

### Lane E — validation and integration
Owner: tests, fixtures, registries, final convergence.

Run and fix, not merely list:
- `python harness/validators/validate-sas-android-provider-boundary.py`
- `python Tests/survey/test_sas_android_provider_boundary_contracts.py`
- `python Tests/survey/test_hh_cc_reader_adb_control_plane_contracts.py`
- `python harness/validators/validate-hh-cc-reader-firmware-policy.py`
- registry/completeness checks after registry edits;
- applicable Pester/PowerShell checks for changed PS code;
- `git diff --check`;
- applicable offline survey floor.

## Complete capability target

The M2 suite is not complete until one cloned SASS checkout can provide these capability families through typed repository-owned surfaces:

1. Host/runtime readiness
   - qualify/select Platform-Tools;
   - start/stop owned loopback ADB server;
   - version/provenance/status;
   - offline readiness;
   - competing-runtime diagnostics.

2. Device discovery and identity
   - USB/PnP evidence;
   - `adb devices -l` classification;
   - unauthorized/offline/ready/multiple-device states;
   - logical identity binding;
   - USB/TCP alias collapse;
   - ambiguity blocking.

3. Read-only inspection
   - build/properties;
   - package inventory;
   - process inventory;
   - interface/address/route inventory;
   - connectivity state;
   - device-policy state;
   - H&H firmware-property adapter/classification.

4. Safe transport management
   - exact-target TCP/IP enable only after prerequisites;
   - exact-target connect;
   - read-only proof over LAN;
   - disconnect;
   - return-to-USB/revert;
   - prove network listener/session cleanup;
   - mark cleanup failure INCOMPLETE.

5. Evidence and resumability
   - typed operation receipts;
   - host/runtime/device/session identity without secrets;
   - exact attempted operation and exit state;
   - cleanup state;
   - local evidence path;
   - exact next action;
   - crash/retry-safe continuation where existing harness patterns support it.

6. Workload adapter
   - H&H CC-reader workflow remains behaviorally compatible;
   - firmware target `2.0.15.260522` remains workload policy, not provider default;
   - provider never promotes technical access into firmware authority.

7. Optional capability surfaces
   - view-only remote display when provider state is READY and existing support is present;
   - keep this optional and separate from core readiness.

## P82 — prototype → measure → refine gates

### Experiment 1: Provider extraction parity
Hypothesis: generic runtime/enumeration extraction can preserve H&H results.
Measure: before/after fixtures and H&H contract tests.
Promote only if semantics are unchanged.

### Experiment 2: Identity/session safety
Hypothesis: logical identity + lease prevents cross-transport ambiguity.
Required fixtures:
- no device;
- unauthorized;
- one ready device;
- multiple ambiguous devices;
- same device visible through USB + TCP aliases;
- concurrent stateful-operation contention;
- cleanup/revert failure.
Promote only if ambiguity blocks and cleanup failure never becomes success.

### Experiment 3: Portable offline readiness
Hypothesis: any prepared supported Windows node can operate after clone/preparation without Internet at execution time.
Required fixtures:
- correct qualified bundle;
- missing bundle;
- wrong hash;
- incomplete component set;
- competing PATH ADB;
- network unavailable.
Promote only when the SAS-owned runtime deterministically wins or readiness fails closed.

### Experiment 4: PTop same-LAN live certification
Use PTop because it is presently on the same network as the CC reader.

Sequence:
1. prove current branch/floor and clean owned worktree;
2. prove PTop node role and qualified runtime;
3. establish target identity from approved/private expected identity and/or vendor properties;
4. prove current ADB state;
5. if USB READY and the existing gate allows it, perform exact-target TCP/IP transition;
6. connect only to the device-derived/authorized IP; never scan;
7. run read-only proof over LAN;
8. disconnect and revert to USB;
9. prove return to USB, listener/session teardown, removal of temporary ADB forward/reverse rules and device payloads, and provider lease release; any failed cleanup proof is `INCOMPLETE`;
10. persist sanitized local receipt.

If USB is not READY, do not invent a bypass. Record the typed blocker. Same-LAN reachability alone is not permission to enable debugging or guess an ADB endpoint.

### Experiment 5: AdminBox parity
Run the same generic provider readiness/probe/inventory flow on AdminBox One using its offline/reference constraints.
Goal: prove host differences are configuration/runtime differences, not separate codepaths/products.

## Definition of done

Do not declare complete until:
- generic provider code exists and H&H-specific host mechanics no longer own the reusable layer;
- one SASS clone can prepare and expose the same typed provider surface on PTop and AdminBox-class nodes;
- operator/technician commands are repository-owned and location-neutral;
- existing H&H ADB tests remain green;
- new provider tests cover ambiguity, aliasing, leases, offline bundle failures and cleanup failure;
- PTop same-LAN live cert is either LIVE_PROVEN with a sanitized receipt or explicitly BLOCKED at the exact hardware/authorization gate;
- AdminBox One reaches at least repository/integration readiness and, when locally available, local-live readiness;
- changed files, test outputs, commit SHA, push/PR state and proof ceiling are reported.

## Mandatory local-agent operating rule

This handoff contains the architecture and decision policy. Do not ask the operator to choose libraries, file layout, state names, transport philosophy, or whether PTop and AdminBox are separate products. Search existing repository patterns and implement the smallest compatible solution.

When a failure occurs: inspect -> diagnose -> fix in owned scope -> rerun the failing gate. Do not convert a skipped/failed check into completion.

## Required final report

COMPLETED:
- exact implemented capability families.

FILES:
- exact created/modified paths.

PROVED:
- exact validation commands and results;
- exact live-cert operations and sanitized outcomes.

SKIPPED:
- exact checks not run and why.

GAPS/RISKS:
- remaining authority/hardware/provider blockers only.

GIT:
- branch, commit(s), push, PR, merge state, final git status.

DEPLOYMENT/PRODUCTION:
- distinguish repository validated, integration validated, local live certified, field/production verified.

NEXT:
- one exact next command or one exact operator-only boundary.

Do not return another architecture proposal. Execute this M2 plan.

## Local implementation checkpoint

The shared provider is implemented in `harness/api/android_provider.py`; the
typed CLI and `Run-SasAndroidProvider.cmd` consume it. The H&H collector delegates
runtime, enumeration, property parsing, read-only calls and transport transactions.
The implementation creates no forward/reverse rules or device payloads; these
cleanup obligations therefore remain vacuously satisfied for its current operations.

P82 admission and measured decisions:

| Hypothesis | Comparator / falsifier | Measurement | Decision |
| --- | --- | --- | --- |
| Generic extraction preserves H&H classification | Existing five H&H fixture groups; any changed classification rejects extraction | Existing suite plus mocked live-collector inventory/transport journeys | KEEP; host fallback/acquisition are deliberately tightened |
| Bound identity and exclusive ownership prevent ambiguous mutation | Unbound aliases, duplicate USB identity, competing process, failed revert | Behavioral negative controls plus complete transport positive control | KEEP after rooted ZIP, unbound cleanup and account-scoped lease findings were repaired |
| One prepared runtime supports all node roles offline | Missing/corrupt/extra files or PATH copy must never win | Qualified archive fixtures across all three roles, no network acquisition | KEEP at repository proof; physical AdminBox observation remains unproven |
| PTop can certify exact LAN ADB | USB READY and qualified runtime are mandatory admission | Local host asset verification and PnP enumeration only | BLOCK: qualified bundle absent; no Android/ADB interface enumerated |

Local evidence belongs under ignored `survey/output/android-provider/`:
`validation.json`, `offline-floor.log`, `local-readiness.json`, and timestamped
operation receipts. These files are private and must not be committed.

Remaining live gate: prepare an approved official local archive, attach the
intended already-debug-enabled/authorized device over its supported USB path,
and supply approved private stable identity. Resolve current source admission
before the typed probe/inventory/certification front door. Do not infer an IP,
enable debugging, scan the LAN or change firmware. AdminBox One requires its
own host/device observation using the same provider and offline source seal.

Hosted review reconciliation: clean owned default checkouts now fast-forward
only when strictly behind, verify equality, and restart the CLI before product
execution. Preparation hashes and extracts the same immutable archive snapshot.
Transport requires a separate private resolved organization/site/equipment
authority packet through `--profile-file`; node role and identity never supply
those approvals. Outcome registration includes probe and TCP certification.
Dedicated offline review suites cover each repaired boundary; physical source
admission and device operations remain outside fixture proof.
Further adapter review preserved failed cleanup as `INCOMPLETE`, retained a
lease through every H&H inventory read, and separated explicit connection
refusal from timeout/error/inconclusive results. An independent sibling runtime
attestation now detects replacement of both bundle and colocated manifest;
attended rollback preserves the previous matching attestation. Trusted local
host storage remains the security boundary.
Final review corrected H&H admission failures into sanitized typed receipts
with nonzero exits, preserved uncertain transaction cleanup as `INCOMPLETE`,
redirected missing-runtime guidance to qualified local preparation, isolated
the adapter test lease, and aligned profile docs and Windows hash input.
