# P04 — Northwell Printer Runtime-to-Production Convergence

Date: 2026-10-09  
Status: `ACTIVE_SUCCESSOR_PROGRAM`  
Repository floor: `main@aca56860031166a0180d241340352acbe470f33f`  
Supersedes implementation-base use of PR #515 / branch `docs/printer-multimodal-materialization-p97-p04-p82-20261007`; preserves its design artifacts as carried-forward context on this branch.

## 1. LAUNCH ORDER

One prompt panel goes into one new chat.

1. **P1 — Contract Floor + Result Model**
2. **P2A — Classifier + Driver-Readiness Instrumentation**  
   Parallel with P2B after P1 is integrated.
3. **P2B — Deferred Materializer Primitives (M4/M5/M6)**  
   Parallel with P2A after P1 is integrated.
4. **P3 — Integration + Exact-Head CI Convergence**
5. **P4 — Authorized Northwell Live P82 Certification**
6. **P5 — Field Runtime Deployment**
7. **P6 — Production Verification + Closeout**

Final convergence order is fixed:
`P1 -> [P2A || P2B] -> P3 -> P4 -> P5 -> P6`.

No lane may promote its proof ceiling into a later lane's claim.

## 2. COMPACT COORDINATION PREAMBLE

### Current provider truth

- Repository: `EndeavorEverlasting/SysAdminSuite`
- Current main at this factoring pass: `aca56860031166a0180d241340352acbe470f33f`
- PR #515 is still open and mergeable but is 15 commits behind current main.
- Since #515 was authored, main gained a separate site-specific Agilant HQ printer subsystem and expanded shared printer-routing registries.
- The new Agilant path is deliberately different from Northwell: local TCP, site-bound, interactive-admin, preinstalled-driver semantics.
- Therefore the Northwell materialization program must not modify, inherit from, or generalize the Agilant path.
- Historical August printer branches are reference only, not implementation bases.

### Canonical design authority

Preserve:
- `docs/research/northwell-printer-session-materialization-p97-20261007.md`
- `docs/plans/northwell-printer-multimodal-materialization-p04-p82-20261007.plan.md`
- `docs/handoff/northwell-printer-multimodal-materialization-cursor-20261007.md`

The architecture remains:
- M0 `SYSTEM_GA_REGISTER` mandatory;
- M1 active-session direct materialization;
- M2 native next-logon observation;
- M3 evidence-gated driver readiness;
- M4 deferred logon task preferred durable fallback;
- M5 Common Startup one-shot bridge;
- M6 Common Startup persistent last-resort fallback.

### Shared collision owners

The following are shared and must have one owner at a time:
- `harness/api/printer-mapping-use-case-registry.json`
- `harness/api/harness-artifact-registry.json`
- `harness/api/harness-command-registry.json`
- `harness/api/harness-outcome-registry.json`
- `harness/api/harness-validator-registry.json`
- `harness/api/operational-harness-manifest.json`
- `.claude/skills/field-workflow/SKILL.md`
- `START-HERE-NORTHWELL-PRINTER-MAPPING.md`
- `mapping/README.md`
- existing Northwell finalizer/operator/bootstrap/launcher surfaces
- CI workflow files that already watch Northwell printer behavior

P1 owns shared contract registration. P2A/P2B consume those authorities read-only. P3 owns all shared integration surfaces.

### Forbidden scope across all lanes

- Do not alter Agilant HQ local TCP product behavior.
- Do not route Health & Hospitals into Northwell.
- Do not weaken Point-and-Print or print-driver security policy.
- Do not invent direct-IP Northwell mapping.
- Do not introduce `Add-Printer -ConnectionName` as Northwell authority.
- Do not store user credentials/passwords.
- Do not commit live queue/server/target data or runtime evidence.
- Do not rewrite M0 SYSTEM `/ga` machine registration.
- Do not create a second top-level printer engine.
- Do not use a green test/PR as live-cert, deployment, or production proof.

## 3. FACTORED SPRINTS

### P1 — Contract Floor + Result Model

**Primary ownership:** harness spine / floor.

**Mission:** make M0-M6, transitions, proof requirements, result classifications, cleanup semantics, and organization binding machine-readable before runtime mutation begins.

**Owned scope:**
- new Northwell materialization policy/schema when no equivalent exists;
- focused validator/tests;
- minimal Northwell use-case registry binding if required;
- operational-harness registration needed for the new contract.

**Forbidden scope:**
- runtime mapping/finalizer scripts;
- Agilant files;
- field skill/docs;
- live execution.

**Expected artifacts:**
- `harness/api/northwell-printer-materialization-policy.json`
- `schemas/harness/northwell-printer-materialization-policy.schema.json`
- focused validator + contract tests
- registry wiring only where structurally required

**Acceptance gates:**
- schema closes unknown mode/result values;
- M0 is prerequisite to M1-M6;
- M5 one-shot and M6 persistent semantics are distinct;
- policy weakening is forbidden;
- cleanup failure cannot equal success;
- Northwell use-case ID is explicit;
- printer use-case and harness registry validators remain green.

**Proof ceiling:** implemented and locally/integration validated contract only.

### P2A — Classifier + Driver-Readiness Instrumentation

**Primary ownership:** conventional application logic / read-only evidence.

**Safe parallel:** yes, with P2B after P1.  
**Collision boundary:** must not modify P2B files or P3-owned shared integration files.

**Mission:** classify standard-user failure deterministically before choosing M3/M4/M5/M6.

**Owned scope:**
- new classifier/resolver surface;
- read-only active-user privilege classification;
- read-only HKU/HKCU state capture;
- read-only driver identity/readiness and printer-policy snapshot;
- typed result/evidence output;
- classifier-focused tests/fixtures.

**Forbidden scope:**
- actual driver staging/install;
- deferred task/Startup staging;
- finalizer/operator orchestration;
- shared registries after P1.

**Required outcomes include:** task/session failure, driver-not-ready, driver-source-required, native-next-logon pending, unclassified failure.

**Acceptance gates:**
- no mutation in classifier mode;
- admin-success alone never proves driver cause;
- exact SID/account binding;
- queue/receipt binding to prior M0 proof;
- policy snapshot is evidence only;
- PS5.1 parse + focused Pester/fixture tests pass.

**Proof ceiling:** classifier implemented and integration-ready, not live-cause proven.

### P2B — Deferred Materializer Primitives (M4/M5/M6)

**Primary ownership:** conventional application logic / lifecycle primitives.

**Safe parallel:** yes, with P2A after P1.  
**Collision boundary:** must not modify P2A classifier files or P3-owned shared integration files.

**Mission:** implement the bounded deferred delivery mechanisms without deciding when to select them.

**Owned scope:**
- M4 logon-triggered Task Scheduler lifecycle;
- M5 Common Startup one-shot generator/stager/cleanup;
- M6 persistent Common Startup fallback if retained by policy;
- shared helper(s) private to these modes;
- synthetic templates;
- primitive-focused fixtures/tests.

**M4 requirements:**
- requires matching M0 proof;
- no stored password;
- executes only approved queue set;
- user-context materialization;
- HKU/HKCU proof;
- idempotent;
- explicit uninstall/retirement;
- cleanup failure typed incomplete.

**M5 requirements:**
- Common Startup known-folder resolution;
- local/untracked assignment;
- self-delete only after connection proof + durable receipt;
- preserve artifact on failure.

**M6 requirements:**
- persistent and idempotent;
- never self-delete after first success;
- machine-authority retirement.

**Acceptance gates:**
- no host real Common Startup mutation during tests;
- synthetic/temp surrogate only in CI;
- no live values tracked;
- no password-backed task;
- no security-policy mutation;
- PS5.1 parse + focused tests pass.

**Proof ceiling:** primitives implemented and fixture-validated, not selected/integrated/live-proven.

### P3 — Integration + Exact-Head CI Convergence

**Primary ownership:** integration seam / validation / docs.

**Hard dependencies:** P1 + P2A + P2B.

**Mission:** integrate the parallel implementation lanes into the one canonical Northwell workflow and prove exact-head repository convergence.

**Owned scope:**
- existing active-user/resilient finalizers;
- operator wrapper and operator result model;
- quick/batch/bootstrap dependencies;
- universal launcher required-runtime file set;
- Northwell evidence policy;
- shared harness registries only when real operator-facing artifacts/commands require them;
- field workflow skill;
- Northwell start-here/tutorial/map docs;
- Northwell-specific CI trigger coverage.

**Important integration rule:** keep the Agilant site override intact and prove cross-organization/site isolation.

**Expected behavior:**
- M1 happy path remains fast;
- no-user state is explicit;
- standard-user failure routes through classifier;
- M3 is selected only from driver evidence;
- M4 is preferred durable fallback;
- M5/M6 require eligible typed disposition;
- quick and batch share the same authority;
- bootstrap refuses a runtime missing newly required materializer files.

**Validation order:**
1. PS5.1 parse changed scripts.
2. new focused tests.
3. existing Northwell active-user/shareless/mapping/universal/reversibility/operator tests.
4. printer use-case validator + survey contracts.
5. harness registry/schema validators.
6. changed workflows.
7. `git diff --check`.
8. broad Pester/harness regression.
9. exact-head hosted CI/reviews.

**Proof ceiling:** implementation + integration validated at exact PR head. Still not live Northwell repair.

### P4 — Authorized Northwell Live P82 Certification

**Primary ownership:** runtime proof.

**Hard dependency:** exact P3 candidate head, integration green.

**Mission:** determine the actual privilege-dependent failure cause and certify only the modes needed on one authorized Northwell target/queue.

**Execution order:**
- E0 reproduce privilege split;
- E1 task/session-token discriminator;
- E2 driver-readiness discriminator;
- E3 exact approved driver stage only if E2 proves it;
- E4 native no-user -> standard-user next logon;
- E5 M4 across two sequential eligible standard-user sessions;
- E6 M5 only if still needed;
- E7 M6 only if M4 unavailable/failed and persistent fallback remains required.

**Evidence must separate:**
- M0 HKLM proof;
- exact user SID/account and privilege class;
- HKU/HKCU before/after;
- driver/policy evidence;
- task/helper lifecycle evidence;
- cleanup result;
- optional physical document output.

**Failure handling:** repair only defects attributable to the candidate, rerun the narrow failed discriminator, and preserve prior valid evidence.

**Proof ceiling:** controlled live certification on the observed target/users only. Not yet deployed field runtime unless candidate was already the installed released runtime.

### P5 — Field Runtime Deployment

**Primary ownership:** release / deployment.

**Hard dependencies:** P4 pass + implementation PR merged to current main.

**Mission:** make the repaired capability available through the existing installed SysAdminSuite field platform without inventing another installer.

**Reuse existing authority:**
- `Install-SasOperatorCommand.cmd`
- `scripts/Install-SasUniversalFieldLauncher.ps1`
- installed sibling `sas.cmd` + `Map-NorthwellPrinter.cmd`
- existing repository freshness / `sas refresh` / bootstrap runtime currentness contracts.

**Deployment proof:**
- refreshed current main;
- implementation merge commit identified;
- installed field front door refreshed on authorized controller(s);
- installed launcher/bootstrap provenance proven;
- printer bootstrap selects a clean runtime containing the required implementation;
- prepared/runtime commit equals intended released main commit or satisfies the repository's explicit immutable-floor contract;
- no target mutation required merely to prove installation.

**Proof ceiling:** deployed field tooling/runtime. Does not prove a production user has successfully used it.

### P6 — Production Verification + Closeout

**Primary ownership:** production proof / reporting.

**Hard dependency:** P5 deployment proof.

**Mission:** prove the deployed released path in normal Northwell use and close the original defect.

**Minimum production acceptance:**
- launch through the installed technician front door, not a developer script;
- M0 machine registration proven;
- at least one real standard-user session reaches the correct materialization outcome;
- for durable all-user claim, two sequential eligible standard-user sessions prove the released mechanism;
- a real requested document is observed printing where operationally appropriate;
- temporary artifacts/tasks are left in the policy-defined durable state or retired cleanly;
- exact deployed commit/runtime and evidence paths are recorded.

**Closeout outcomes:**
- `PRODUCTION_VERIFIED`
- `DEPLOYED_LIVE_GAP_REMAINS`
- `ROLLBACK_REQUIRED`
- another closed typed result from the implemented contract

**Proof ceiling:** production verified only for the observed released use case. Do not infer entire-fleet certification without separate rollout evidence.

## 4. SUPPORTING FACTORING LEDGER

### Topics found

- **Feature/application logic:** M1-M6 classification and delivery.
- **Harness spine:** materialization policy/schema/validator.
- **Agent harness:** existing field-workflow and printer-use-case routing; strengthen, do not create a duplicate skill unless deterministic routing cannot express the new state.
- **Integration:** finalizer/operator/bootstrap/universal launcher.
- **Validation:** focused Pester/fixtures + current printer-use-case contracts + broad regression.
- **Docs/reporting:** Northwell only after implementation settles.
- **Runtime proof:** P82 target matrix.
- **Release/PR hygiene:** retire stale #515 implementation-base role; current-main successor only.
- **Deployment:** universal field platform refresh.
- **Production:** installed-front-door observation.
- **Blocked/unsafe:** security-policy relaxation, direct-IP Northwell mapping, guessed driver source, cross-org inheritance.

### Harness factoring

**Keep/reuse:**
- printer-mapping use-case registry and validator;
- Field Workflow skill;
- printer-mapping use-case routing skill/workflow;
- operational-harness registries;
- evidence provenance rules;
- existing Northwell evidence policy.

**Create only if absent:**
- one materialization policy/schema;
- one focused validator;
- machine-readable result schema only if existing result artifacts cannot safely carry closed M0-M6 semantics.

**Do not create:**
- a new generic printer skill;
- a new cross-organization printer engine;
- one global command per internal mode unless an operator actually needs to invoke it independently.

### Application-logic factoring

- M0 remains existing `Invoke-NorthwellPrinterState.ps1`.
- P2A owns classification/read-only evidence.
- P2B owns deferred-delivery primitives.
- P3 alone owns changes to current finalizers/operator/bootstrap routing.
- P5 uses existing field installer/runtime lifecycle.

### Parallel safety

Only P2A and P2B are approved as a parallel group. They must use separate branches/worktrees and disjoint owned files. P3 is the collision owner and convergence point.

## 5. RECOMMENDED EXECUTION ORDER

Confirmed unchanged:

`P1 -> [P2A || P2B] -> P3 -> P4 -> P5 -> P6`

This ordering converts the previously missing states in order:

`designed -> implemented -> integration validated -> live certified -> deployed -> production verified`.
