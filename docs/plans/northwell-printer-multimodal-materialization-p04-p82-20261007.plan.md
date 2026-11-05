# Plan — Northwell Printer Multimodal Session Materialization (P04 + P82)

Date: 2026-10-07  
Status: `ARCHITECTURE_FROZEN_FOR_LOCAL_IMPLEMENTATION`  
Repository floor at authoring: `main@2b63c6afd032c3c36fa6d6e615032fcebeb5cee4`  
Canonical research owner: `docs/research/northwell-printer-session-materialization-p97-20261007.md`

## Execution frame

**Repo:** `EndeavorEverlasting/SysAdminSuite`  
**Planning branch:** `docs/printer-multimodal-materialization-p97-p04-p82-20261007`  
**Lane:** Northwell printer standard-user session materialization  
**Mission:** keep the proven SYSTEM-wide printer registration path unchanged while making user-session delivery deterministic across privileged users, standard users, no-user-at-deploy time, future logons, driver-readiness gaps, and bounded emergency fallback.

**Owned implementation surfaces:**
- Northwell printer materialization/classification logic
- printer evidence contracts and closed outcomes
- deferred logon task lifecycle
- generated Common Startup fallback lifecycle
- focused fixtures/tests/validators
- Northwell printer documentation needed to expose the new semantics

**Forbidden scope:**
- weakening Windows printer security policy
- changing Northwell print servers, queues, or AD policy
- direct-IP printer installation
- Health & Hospitals or other-organization behavior
- unrelated software-deployment/ScanSnap work
- live identifiers or local runtime evidence committed to Git
- replacing the canonical machine-wide SYSTEM `/ga` engine
- introducing a second printer assignment authority

**Proof ceiling before live certification:** repository architecture + static/fixture validation only. No implementation may claim the standard-user defect is repaired until an authorized target proves it.

## Architecture already decided

Cursor/local agents do not choose among competing architectures. Implement this state machine.

### Plane A — machine authority

`M0 SYSTEM_GA_REGISTER` is mandatory.

Success requires:
- canonical Northwell organization/site selection;
- exact approved target hostname and shared queue identity;
- SYSTEM execution;
- `PrintUIEntry /ga`;
- requested-queue HKLM per-computer proof.

A downstream session failure does not erase M0 success.

### Plane B — user-session authority

After M0, resolve the actual session state:

1. User already logged on -> attempt `M1 ACTIVE_SESSION_DIRECT`.
2. Nobody logged on -> return a typed next-logon state and use `M2 NATIVE_GA_NEXT_LOGON` as the first future-session observation unless the operator explicitly chooses a pre-staged fallback.
3. If M1/M2 standard-user materialization fails -> classify driver readiness versus session-delivery failure.
4. Proven driver gap -> `M3 DRIVER_READINESS_BOOTSTRAP`, then retry M1/M2.
5. Driver ready + native/current-session materialization still unreliable -> `M4 DEFERRED_LOGON_TASK`.
6. M4 unavailable/blocked and bounded one-session rescue is appropriate -> `M5 COMMON_STARTUP_ONE_SHOT`.
7. Durable endpoint fallback required and M4 is unavailable/empirically failed -> `M6 COMMON_STARTUP_PERSISTENT`.

Never auto-escalate to M5/M6 from an unclassified failure.

## P82 — Hypothesis / Build / Measure / Critique / Decide ladder

Each experiment is a closed iteration. Preserve prior proof; do not redo M0 merely because a later discriminator fails.

### E0 — reproduce the privilege split without mutating policy

**Hypothesis:** the observed failure is real and separable from machine registration.

**Build:** a read-only/session-safe evidence capture around one already-authorized target + queue.

**Measure:**
- M0 HKLM state
- current interactive user SID/account
- whether that exact user token is local/domain administrator
- queue connection state in HKU/HKCU
- exact active-user task registration/run result when M1 is invoked
- installed printer driver identity and queue/driver association where observable
- read-only snapshot of relevant printer policy
- timestamped result code

**Critique:** if standard and privileged accounts do not differ under the same machine/queue state, do not preserve the privilege hypothesis.

**Decide:** branch to E1/E2 based on evidence, not intuition.

### E1 — task/session-token discriminator

**Hypothesis:** the standard-user failure happens before or during InteractiveToken execution rather than in printer-driver acquisition.

**Build:** instrument the existing M1 path; do not replace it.

**Measure:**
- exact SID selected
- task registration success
- task launch success
- task last-result/state if available
- whether `PrintUIEntry /in` ran in the target user's context
- HKU/HKCU before/after

**Critique:** command invocation or task creation is not user-session proof.

**Decide:**
- task/session failure -> `BLOCKED_SESSION_TASK`; repair that path before driver work;
- task ran but user connection absent -> E2.

### E2 — driver-readiness discriminator

**Hypothesis:** privileged success primes/stages a required print driver that a standard user cannot initially install.

**Build:** read-only capture plus controlled account-order experiment where authorized.

**Measure:**
- installed driver name/package facts before standard-user attempt
- `RestrictDriverInstallationToAdministrators` and relevant Point-and-Print policy state, read-only
- standard-user M1/M2 result before privileged intervention
- privileged-session result on the same target/queue
- driver state after privileged success
- standard-user retry result without changing printer assignment

**Critique:** "admin worked" alone is insufficient to blame a driver.

**Decide:**
- evidence shows driver became ready and retry succeeds -> promote driver-readiness hypothesis to E3;
- no driver delta or retry still fails -> continue session-delivery diagnosis.

### E3 — safe driver bootstrap prototype

**Hypothesis:** staging/installing the exact approved driver under admin/SYSTEM authority makes later standard-user materialization succeed without weakening policy.

**Build:** only after exact approved driver/package/server source is deterministically known.

**Measure:**
- source identity/hash/version/model where available
- privileged staging/install result
- post-stage driver presence
- unchanged security policy snapshot
- standard-user M1/M2 retry
- HKU/HKCU proof

**Critique:** do not treat a guessed INF or policy relaxation as a successful prototype.

**Decide:**
- repeatable success -> M3 admitted as a prerequisite repair;
- source unknown -> `DRIVER_STAGE_SOURCE_REQUIRED`;
- stage succeeds but user still fails -> driver gap is not sufficient; move to E4/E5.

### E4 — native next-logon discriminator

**Hypothesis:** Windows native `/ga` behavior is sufficient for a standard user at a clean future logon.

**Build:** prove M0 with no target user logged on, then log on with an authorized standard account.

**Measure before any helper:**
- exact M0 receipt identity
- fresh session SID/account
- HKU/HKCU connection state
- driver readiness
- optional real requested-document print if operationally appropriate

**Critique:** never install a fallback before observing native behavior; doing so destroys the discriminator.

**Decide:**
- native success -> `NATIVE_GA_STANDARD_USER_PROVEN`; no persistent fallback needed;
- native failure with driver ready -> E5.

### E5 — deferred logon task

**Hypothesis:** a machine-owned logon-triggered task can reliably materialize only already-authorized queues inside every applicable interactive user context.

**Build:** M4 with fixture-first lifecycle and exact receipt binding.

**Measure:**
- creation authority
- trigger/principal/logon semantics
- queue assignment digest/binding
- each user invocation
- HKU/HKCU proof
- evidence-write success
- cleanup/retirement result

**Critique:** prove more than one standard-user logon before calling it an all-user fallback.

**Decide:** M4 becomes preferred durable fallback only after two sequential eligible standard-user sessions succeed on an authorized target.

### E6 — Common Startup one-shot

**Hypothesis:** Common Startup can provide a reliable emergency next-session bootstrap while preserving machine authority and self-cleaning only after verified success.

**Build:** M5 generated from a synthetic tracked template and a local/untracked exact assignment.

**Measure:**
- Common Startup path resolution
- M0 receipt binding
- user identity
- before/after HKCU/HKU state
- success/failure receipt
- launcher/payload deletion state after success
- artifact preservation after failure

**Critique:** if it deletes before proof, loses failure evidence, or is described as persistent all-user delivery, the experiment fails.

**Decide:** admit only as bounded bridge/recovery.

### E7 — persistent Common Startup emergency fallback

**Hypothesis:** if M4 is unavailable, a persistent idempotent Common Startup materializer can service sequential standard-user logons without becoming a second assignment authority.

**Build:** M6 only after M4 has a concrete unavailable/failed disposition.

**Measure:** two or more sequential standard-user sessions, per-user proof, no-op behavior when already connected, cleanup by machine authority.

**Critique:** persistent Startup is less governable than M4 and must not become default merely because it is easy.

**Decide:** retain as last-resort mode or reject it if M4 proves sufficient.

## P04 factoring

### Launch order

1. **L0 — Contract floor and result model**
2. **L1 — Read-only privilege/driver/session classifier**
3. **L2 — M4 deferred logon-task implementation**
4. **L3 — M5/M6 Common Startup implementations**
5. **L4 — Orchestrator integration + technician UX**
6. **L5 — Static/fixture convergence**
7. **L6 — Authorized live P82 certification**
8. **L7 — Documentation/retirement cleanup after live result**

One writer owns overlapping printer runtime surfaces. Test/fixture work may be prepared in parallel only when it does not write files owned by the active implementation lane.

### L0 — contract floor

**Goal:** freeze the state machine before runtime changes.

Prefer a new machine-readable policy/contract if current evidence policy cannot express the dimensions cleanly. Candidate:
- `harness/api/northwell-printer-materialization-policy.json`
- `schemas/harness/northwell-printer-materialization-policy.schema.json`
- focused validator/test registration using existing harness conventions

It must encode:
- M0-M6 mode IDs
- allowed transitions
- required inputs/proofs
- closed result codes
- proof ceilings
- policy-change prohibition
- one-shot versus persistent distinction
- cleanup completeness rule
- organization/use-case binding

Do not put live queue/server/host values in this contract.

### L1 — classifier and evidence

Search/reuse current printer helpers before creating new ones.

Candidate implementation owner:
- `mapping/Resolve-NorthwellPrinterMaterializationMode.ps1` or the nearest existing canonical surface if a classifier already exists.

Inputs should be typed evidence, not free-form prose:
- machine registration receipt
- active users/SIDs
- user privilege class
- per-user connection state
- driver readiness facts
- relevant read-only policy snapshot
- prior deferred artifact state

Output:
- selected next mode or blocking result
- reason code
- proof references
- no mutation

### L2 — deferred logon task

Candidate owner:
- `mapping/Invoke-NorthwellPrinterDeferredLogonMaterialization.ps1`

Requirements:
- created by machine authority after M0
- no stored password
- bounded to exact already-approved queue assignment
- executes in eligible interactive user context
- idempotent
- writes evidence
- explicit retire/uninstall operation
- failure and cleanup outcomes closed
- no policy mutation

Prefer Task Scheduler lifecycle over Startup as primary fallback.

### L3 — Common Startup

Candidate surfaces:
- tracked synthetic template under `mapping/Templates/`
- generator/stager such as `mapping/Install-NorthwellPrinterCommonStartupMaterializer.ps1`
- cleanup surface paired with the installer

Requirements common to M5/M6:
- resolve Common Startup rather than assume `C:\Users\Public`
- local/untracked generated assignment
- exact M0 receipt binding
- user-context `/in` only for queues already machine-registered
- HKCU/HKU proof
- durable machine-local receipt
- no live values in Git
- idempotent connection check
- SYSTEM/admin cleanup path

M5:
- self-delete only after verified success + evidence flush

M6:
- remains installed; does not self-delete on first success
- explicit cleanup/retirement required

### L4 — orchestration

Integrate into the existing canonical finalizer/operator flow; do not create another top-level mapping engine.

Expected behavior:
- existing happy path remains unchanged when M1 succeeds
- no-user state is typed rather than overclaimed
- unclassified standard-user failure stops and reports the next discriminator
- deferred fallback staging is explicit and auditable
- technician front door remains short
- batch mapping delegates to the same state/materialization implementation

Only after contracts are stable should documentation such as:
- `START-HERE-NORTHWELL-PRINTER-MAPPING.md`
- `mapping/README.md`
- `.claude/skills/field-workflow/SKILL.md`
be updated to match the implementation.

### L5 — static/fixture convergence gates

At minimum:

1. Windows PowerShell 5.1 parser passes for every changed `.ps1`.
2. Existing focused printer Pester suites remain green.
3. New tests prove M0 is mandatory before M1-M6.
4. Tests reject:
   - direct IP
   - `Add-Printer -ConnectionName` as authority
   - password-backed tasks
   - live queue/host data in tracked templates
   - policy writes to printer security settings
   - self-delete before success proof
   - calling M5 persistent all-user delivery
   - cleanup failure promoted as success
5. Fixture tests cover:
   - privileged + standard-user split
   - standard-user task failure
   - driver missing/ready
   - no-user state
   - native next-logon success/failure
   - M4 staged/success/failure/cleanup
   - M5 success/self-delete and failure/preserve
   - M6 repeated-user idempotency and cleanup
6. Existing use-case registry and evidence-policy validators remain green.
7. Harness registry validation and text policy pass for any new machine-readable contract.
8. `git diff --check` passes.

Use a temporary fixture directory to emulate Common Startup during tests. Do not touch the host's real all-users Startup folder in CI/static tests.

### L6 — live certification gate

No live claim before this lane.

Authorized live proof should preserve one target/queue and test the smallest useful matrix:

| Case | Account/session | Expected discriminator |
| --- | --- | --- |
| A | privileged interactive user | known-good comparison |
| B | standard interactive user | reproduce/repair current-session behavior |
| C | no user -> standard logon | native M2 proof |
| D | standard user 1 under M4 | deferred user proof |
| E | standard user 2 under M4 | all-user durability proof |
| F | M5, if still needed | one-shot + post-proof cleanup |
| G | M6, only if M4 failed/unavailable | persistent fallback proof |

A real requested document observed printing after the canonical workflow remains the highest proof level, but HKLM and HKU/HKCU evidence remain required to prove the architecture's specific layers.

## Evidence model

A run result should preserve at least:

- schema/version
- use_case_id + organization/site context
- target identity
- canonical queue set or safe digest/reference
- M0 evidence reference and machine-proof state
- active user accounts/SIDs
- privilege classification
- current-user before/after connections
- driver identity/readiness facts
- printer policy snapshot or digest
- selected mode
- reason/result code
- task/helper lifecycle state
- cleanup state
- timestamps
- proof level + proof ceiling
- references to detailed local logs

Raw live assignment values and runtime evidence remain local/untracked under the established printer evidence boundary.

## Collision map

- **Printer runtime surfaces:** single writer; L1-L4 are serialized unless file ownership is explicitly partitioned.
- **Harness registries/schemas:** contract-floor owner first; later lanes consume rather than rewrite.
- **Docs:** updated after runtime semantics settle to avoid documenting unimplemented behavior.
- **ScanSnap PRs #512/#514:** unrelated; do not touch software-deployment surfaces.
- **Historical printer branches:** evidence/reference only. They are heavily behind current main and are not implementation bases.

## Definition of done

Repository implementation is complete only when:

- M0 remains unchanged as the machine authority.
- Standard-user failure is classified, not treated as generic mapping failure.
- Driver readiness has a safe no-policy-relaxation path.
- M4 exists as the preferred durable deferred fallback.
- M5 exists as a self-deleting one-shot bridge with post-proof deletion only.
- M6 is separate if retained.
- one-shot versus durable all-user semantics are regression-tested.
- all relevant focused and harness contracts pass.
- exact-head CI is green.
- live certification is clearly labeled as performed or still pending.

Production-repaired is a higher state and requires authorized live proof. A green PR alone cannot claim it.
