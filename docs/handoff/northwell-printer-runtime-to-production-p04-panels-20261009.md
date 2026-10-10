# Northwell Printer Runtime-to-Production — P04 Copy Panels

Use in this exact order. One panel goes into one new chat. Do not combine parallel lanes into one branch.

Canonical plan:
`docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md`

Canonical architecture:
- `docs/research/northwell-printer-session-materialization-p97-20261007.md`
- `docs/plans/northwell-printer-multimodal-materialization-p04-p82-20261007.plan.md`

---

## Panel 1 — P1 Contract Floor + Result Model

```text
EXECUTE THE REPO SPRINT. DO NOT REPLAN THE ARCHITECTURE.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P1
Lane: Northwell printer materialization contract floor
Suggested branch: feat/printer-materialization-contract-20261009
Base: refreshed current main
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Encode the already-decided M0-M6 Northwell materialization state machine as a closed repository contract before runtime behavior changes.

MANDATORY PREFLIGHT
Read AGENTS.md, CODEBASE_MAP.md, current printer use-case registry/validator, Northwell evidence policy, operational harness registries, and both canonical architecture documents. Refresh provider truth. Record repo path/worktree, branch/head, origin/main, status, open printer PRs, owned files, forbidden files, validators, and proof ceiling.

OWNED SCOPE
- new Northwell materialization policy/schema if no equivalent exists
- focused validator and contract tests
- minimal Northwell use-case registry binding only if structurally required
- operational harness registration needed for the new contract

FORBIDDEN SCOPE
- mapping/finalizer/operator runtime scripts
- Agilant HQ local TCP files or semantics
- H&H behavior
- field skill/docs
- live execution
- security-policy relaxation

CONTRACT MUST ENCODE
M0 SYSTEM_GA_REGISTER
M1 ACTIVE_SESSION_DIRECT
M2 NATIVE_GA_NEXT_LOGON
M3 DRIVER_READINESS_BOOTSTRAP
M4 DEFERRED_LOGON_TASK
M5 COMMON_STARTUP_ONE_SHOT
M6 COMMON_STARTUP_PERSISTENT

Require M0 before M1-M6. Keep M5 one-shot distinct from M6 persistent. Close result codes. Make cleanup failure incomplete. Bind the contract to northwell.shared-printer.organization-default. Reject cross-organization inheritance, direct-IP Northwell fallback, stored passwords, and printer-policy weakening.

REUSE
Prefer current harness schema/validator/registry conventions. Do not create a new generic printer skill or command for every internal mode.

VALIDATION
Run schema/validator unit tests first, then printer-mapping use-case validator + survey contracts, harness registry validation when touched, text policy, git diff --check, and relevant hosted CI.

GIT
Commit coherent contract changes, push, open a PR against refreshed main, inspect exact-head checks/reviews, repair owned failures, and report mergeability/behind state.

PROOF CEILING
Contract implemented and integration validated only. No runtime repair claim.

FINAL RESPONSE
Report files, validators/results, PR/commit state, unresolved contract questions, and the exact dependency signal that allows P2A/P2B to start.
```

---

## Panel 2A — P2A Classifier + Driver-Readiness Instrumentation

```text
EXECUTE THE REPO SPRINT. ARCHITECTURE IS FROZEN. THIS LANE IS READ-ONLY TOWARD PRINTER STATE.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P2A
Lane: classifier + driver-readiness evidence
Suggested branch: feat/printer-materialization-classifier-20261009
Hard dependency: P1 contract merged or exact dependency head explicitly selected
Safe parallel: P2B only
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Implement deterministic classification of standard-user materialization failures before any deferred fallback is selected.

OWNED SCOPE
- new classifier/resolver surface
- exact interactive-user SID/account and privilege classification
- HKU/HKCU connection-state capture
- read-only driver identity/readiness capture
- read-only relevant printer-policy snapshot
- typed reason/result/evidence output
- classifier fixtures/tests

FORBIDDEN SCOPE
- actual driver staging/install
- M4/M5/M6 staging
- existing finalizer/operator/bootstrap orchestration
- shared registries after P1
- P2B files
- Agilant files

REQUIRED SEMANTICS
Do not infer "driver issue" from admin success alone. Distinguish:
- task/session execution failure
- driver not ready
- exact driver source required
- native next-logon pending
- user connection absent despite task execution
- unclassified standard-user failure

All classifications must bind to prior matching M0 machine-registration evidence. No mutation.

VALIDATION
PS5.1 parse; focused classifier Pester/fixture tests; negative tests for mutation/policy writes; existing Northwell active-user tests where applicable; git diff --check.

GIT
Push one bounded PR. Do not touch P2B or P3-owned shared integration files.

PROOF CEILING
Classifier implementation/fixture proof only. The actual Northwell root cause remains unproven until P4.

FINAL RESPONSE
Report exact classifier inputs/outputs, tests, files, branch/PR/commit, and the stable interface P3 should consume.
```

---

## Panel 2B — P2B Deferred Materializer Primitives

```text
EXECUTE THE REPO SPRINT. ARCHITECTURE IS FROZEN. IMPLEMENT PRIMITIVES ONLY; DO NOT OWN SELECTION/ORCHESTRATION.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P2B
Lane: M4/M5/M6 deferred materializer primitives
Suggested branch: feat/printer-deferred-materializers-20261009
Hard dependency: P1 contract merged or exact dependency head explicitly selected
Safe parallel: P2A only
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Implement bounded lifecycle primitives for the preferred deferred logon task and the two Common Startup fallbacks.

OWNED SCOPE
- M4 Task Scheduler logon materializer primitive
- M5 Common Startup one-shot generator/stager/cleanup
- M6 persistent Common Startup primitive if retained by contract
- synthetic templates and private helpers
- primitive fixtures/tests

FORBIDDEN SCOPE
- classifier logic
- finalizer/operator/bootstrap integration
- shared registries after P1
- Agilant files
- real Common Startup mutation in tests
- live infrastructure in Git

M4
Require matching M0 proof. No password. Execute only approved queue set in eligible user context. Verify HKU/HKCU. Be idempotent. Emit lifecycle evidence. Support explicit retirement. Cleanup failure is incomplete.

M5
Resolve Windows Common Startup through a known-folder/repository-safe authority rather than C:\Users\Public. Generated assignment is local/untracked. Self-delete only after successful user connection proof and durable receipt write. Preserve artifacts on failure.

M6
Persistent/idempotent. Never self-delete after first user. Explicit machine-authority cleanup.

VALIDATION
Use temp/synthetic Startup directories only. PS5.1 parse. Focused lifecycle tests for install/run/no-op/failure/cleanup. Reject passwords, policy changes, live data, pre-M0 execution, and early self-delete. git diff --check.

GIT
Push one bounded PR with disjoint ownership from P2A. Do not integrate into current finalizer yet.

PROOF CEILING
Primitive fixture proof only. No claim that Northwell requires or successfully uses these modes.

FINAL RESPONSE
Report primitive interfaces, lifecycle evidence format, cleanup semantics, tests, branch/PR/commit, and exact P3 integration points.
```

---

## Panel 3 — P3 Integration + Exact-Head CI

```text
EXECUTE THE REPO CONVERGENCE SPRINT. THIS IS THE COLLISION OWNER.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P3
Lane: Northwell materialization integration + CI convergence
Suggested branch: fix/printer-materialization-integration-20261009
Hard dependencies: P1 + P2A + P2B
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Integrate the contract, classifier, and deferred primitives into the one canonical Northwell printer workflow, reconcile current main, and produce an exact-head candidate suitable for live P82 certification.

REFRESH FIRST
Current main includes an independent Agilant HQ local TCP site override. Preserve it. Reconcile provider truth, open PRs, and exact dependency heads before mutation.

OWNED SHARED SURFACES
- current active-user/resilient finalizers
- operator wrapper/result model
- quick/batch/bootstrap dependency lists
- universal launcher required-runtime set
- Northwell evidence policy
- shared registries only where real operator-facing artifacts/commands need registration
- field workflow skill and Northwell docs
- Northwell CI triggers

REQUIRED BEHAVIOR
- M0 remains existing SYSTEM /ga + HKLM authority
- M1 happy path remains fast
- no-user state is typed
- standard-user failure invokes classifier
- M3 only follows evidence
- M4 is preferred durable fallback
- M5/M6 require eligible typed disposition
- quick and batch use same materialization authority
- bootstrap refuses runtimes missing required new files
- Agilant HQ behavior remains site-isolated and unchanged
- H&H remains discovery-required

VALIDATION ORDER
1. PS5.1 parse all changed printer scripts
2. new focused suites
3. existing Northwell active-user/shareless/mapping/universal/reversibility/operator tests
4. printer use-case validator + survey contracts
5. harness registries/schemas
6. changed workflows
7. git diff --check
8. broad Pester/harness regression
9. exact-head hosted CI and review threads

Repair failures within owned scope and rerun. Do not hand back a merely green branch if safe PR convergence remains.

GIT
One convergence PR against refreshed main. Record exact dependency reconciliation. Do not merge merely to call the sprint complete if P4 live-cert is intentionally required before merge; state the chosen release gate explicitly.

PROOF CEILING
Implementation and integration validated. No live Northwell repair yet.

FINAL RESPONSE
Report files, exact-head tests/CI, review state, mergeability, candidate SHA, live-cert readiness, skipped checks, and the single exact P4 handoff.
```

---

## Panel 4 — P4 Authorized Northwell Live P82 Certification

```text
EXECUTE THE LIVE CERTIFICATION SPRINT. DO NOT SUBSTITUTE STATIC TESTS FOR RUNTIME EVIDENCE.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P4
Lane: authorized Northwell controlled live certification
Hard dependency: exact P3 candidate head is integration-green
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Determine the actual privilege-dependent failure cause and certify only the modes required on one authorized Northwell target/queue.

BEFORE MUTATION
Prove exact candidate runtime, organization/site use case, approved target hostname, approved shared queue, network authority, machine-registration state, and available test identities. Preserve prior valid evidence and do not redo it without invalidation.

P82 ORDER
E0 reproduce privilege split
E1 task/session-token discriminator
E2 driver-readiness discriminator
E3 exact approved driver stage only if E2 proves it
E4 clean no-user -> standard-user native next-logon observation
E5 M4 with sequential eligible standard-user sessions
E6 M5 only if still needed
E7 M6 only if M4 unavailable/failed and persistent fallback remains required

FOR EACH ITERATION
HYPOTHESIS -> BUILD -> MEASURE -> CRITIQUE -> DECIDE

EVIDENCE
Keep M0 HKLM proof, exact SID/account + privilege class, HKU/HKCU before/after, driver/policy observations, task/helper lifecycle, cleanup, and optional physical output separate.

RULES
- Never weaken printer security policy.
- Never guess a driver source.
- Never install M5/M6 before native behavior is observed when that would destroy the discriminator.
- For an all-user durability claim, prove at least two sequential eligible standard-user sessions under the durable mechanism.
- Repair only demonstrated candidate defects and rerun the narrow failed gate.

GIT
If live evidence exposes an implementation defect, patch on the candidate branch/PR under normal review and rerun affected static + live gates. If no code defect exists, do not create noise commits.

PROOF CEILING
Controlled live certification for the observed target/users. Not deployed released runtime unless the candidate was already the released installed runtime.

FINAL RESPONSE
Report every P82 iteration actually performed, result/evidence paths, exact candidate SHA, root-cause conclusion or remaining blocker, modes admitted/rejected, and whether P5 release is authorized.
```

---

## Panel 5 — P5 Field Runtime Deployment

```text
EXECUTE THE RELEASE/DEPLOYMENT SPRINT. DEPLOYMENT IS NOT THE SAME THING AS MERGE OR LIVE CERT.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P5
Lane: released field runtime deployment
Hard dependencies: P4 passed + implementation PR merged to current main
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Make the certified capability available through the existing installed SysAdminSuite field platform on the authorized controller(s).

REUSE EXISTING DEPLOYMENT AUTHORITY
- Install-SasOperatorCommand.cmd
- scripts/Install-SasUniversalFieldLauncher.ps1
- installed sibling sas.cmd and Map-NorthwellPrinter.cmd
- repository freshness + sas refresh / bootstrap runtime-currentness contracts

DO NOT
Create a new printer installer, copy developer checkout scripts ad hoc into Startup, or call a merged PR "deployed."

DEPLOYMENT GATES
- refresh provider truth/current main
- identify implementation merge commit
- prove canonical repo checkout current
- install/refresh the universal field launcher using the repository-owned path
- prove installed launcher/bootstrap provenance
- prove printer bootstrap selects a clean runtime containing required materialization files
- prove runtime/prepared commit equals intended release or satisfies the repository's explicit immutable-floor rule
- preserve starting network posture and required restoration
- no target mutation is required just to prove deployment

If multiple authorized controllers are in scope, record each separately. Do not infer controller B from controller A.

PROOF CEILING
Field tooling/runtime deployed. No production-user success claim.

FINAL RESPONSE
Report merge commit, deployed controller(s), installed/runtime commit evidence, installer/refresh command used, validation results, skipped controllers, and the exact P6 production-verification entrypoint.
```

---

## Panel 6 — P6 Production Verification + Closeout

```text
EXECUTE PRODUCTION VERIFICATION. DO NOT CALL DEPLOYMENT OR LIVE CERTIFICATION PRODUCTION PROOF.

Repo: EndeavorEverlasting/SysAdminSuite
Wave: P6
Lane: normal-use production acceptance
Hard dependency: P5 deployment proof
Planning source: docs/plans/northwell-printer-runtime-to-production-p04-20261009.plan.md

MISSION
Prove the deployed released path closes the original privilege-dependent Northwell printer defect in normal use.

REQUIRED ENTRYPOINT
Use the installed technician front door, not a developer-only script.

MINIMUM ACCEPTANCE
- exact deployed runtime/commit proven
- M0 machine registration proven
- at least one real standard-user session reaches the correct materialization outcome
- if claiming durable all-user behavior, two sequential eligible standard-user sessions prove it
- real requested document observed printing where operationally appropriate
- temporary task/Startup artifacts end in the contract-defined durable or cleanly retired state
- evidence paths and outcome classification recorded

CLOSED OUTCOMES
PRODUCTION_VERIFIED
DEPLOYED_LIVE_GAP_REMAINS
ROLLBACK_REQUIRED
or another implemented closed result

FAILURE
If production behavior differs from controlled live cert, preserve the evidence, classify the delta, and reopen the smallest owning sprint. Do not erase earlier valid proof and do not normalize a failure into "works on my machine."

PROOF CEILING
Production verified only for observed released Northwell use. Fleet-wide certification requires its own rollout evidence.

FINAL RESPONSE
Report deployed SHA/runtime, target/user observations, physical-output evidence when applicable, final cleanup state, proof level, residual risks, and whether the original defect can be closed.
```
