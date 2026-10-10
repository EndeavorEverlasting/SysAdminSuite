# Cursor Handoff — Northwell Printer Standard-User Multimodal Materialization

## Banner

EXECUTE THE REPO SPRINT. THE ARCHITECTURE IS ALREADY DECIDED. DO NOT REPLAN IT.

Repo: `EndeavorEverlasting/SysAdminSuite`  
Planning source: `docs/plans/northwell-printer-multimodal-materialization-p04-p82-20261007.plan.md`  
Research source: `docs/research/northwell-printer-session-materialization-p97-20261007.md`  
Authoring floor: `main@2b63c6afd032c3c36fa6d6e615032fcebeb5cee4`  
Suggested implementation branch after refreshing main: `fix/printer-standard-user-multimodal-materialization-20261007`

## Role

Act as the senior **implementation** engineer for this bounded printer sprint. The remote coordinator has already supplied the architecture and decision policy.

Your job is legwork:

- refresh current provider/repository truth;
- inspect/reuse current printer helpers and contracts;
- implement the frozen mode/state design;
- build fixtures/tests/validators;
- diagnose failures and rerun gates;
- integrate cleanly;
- produce evidence.

You do **not** own architecture selection. Do not replace the design with a simpler per-user mapper, direct-IP install, policy relaxation, GPO invention, or an unrelated printer framework.

## Mandatory execution frame

Before mutation, report:

- repo path/worktree
- branch/head
- refreshed `origin/main`
- git status
- open overlapping printer PRs/branches
- implementation lane
- owned files
- forbidden files/scope
- expected artifacts
- validation order
- proof ceiling

If this handoff branch has already merged, start from refreshed main. If it has not merged and the operator explicitly supplied this plan branch as the base, preserve that fact. Do not silently resurrect an old August printer branch; historical printer branches are heavily behind current main.

## Read first

1. `AGENTS.md`
2. `CODEBASE_MAP.md`
3. `.claude/skills/field-workflow/SKILL.md`
4. `START-HERE-NORTHWELL-PRINTER-MAPPING.md`
5. `mapping/README.md`
6. `harness/api/printer-mapping-use-case-registry.json`
7. `harness/api/northwell-printer-mapping-evidence-policy.json`
8. `mapping/Invoke-NorthwellPrinterMapping.ps1`
9. `mapping/Invoke-NorthwellPrinterState.ps1`
10. `mapping/Confirm-NorthwellPrinterActiveUserMaterialization.ps1`
11. `mapping/Invoke-NorthwellPrinterSharelessActiveUser.ps1`
12. `mapping/Agents/Invoke-NorthwellPrinterActiveUserAgent.ps1`
13. relevant printer Pester suites and CI workflows
14. the P97 research and P04/P82 plan named above

Search for existing helpers before creating files. Reuse current queue normalization, evidence, remote registry, scheduled-task, user-SID, cleanup, network, and operator-result conventions.

## Frozen architecture

### Mandatory machine plane

`M0 SYSTEM_GA_REGISTER`

- always first;
- existing SYSTEM `PrintUIEntry /ga`;
- requested queue proven under HKLM;
- downstream user failure never invalidates successful M0.

### Session/deferred modes

- `M1 ACTIVE_SESSION_DIRECT`: existing-user InteractiveToken + quiet `/in` + HKU/HKCU proof.
- `M2 NATIVE_GA_NEXT_LOGON`: observe a standard user's clean future logon before installing a helper.
- `M3 DRIVER_READINESS_BOOTSTRAP`: only for a **proven** driver-readiness gap; privileged/SYSTEM stage/install; no printer-security policy relaxation; then retry M1/M2.
- `M4 DEFERRED_LOGON_TASK`: preferred durable fallback. Machine-owned lifecycle; runs only already-authorized queue materialization in eligible interactive user context; no stored password; evidence + cleanup.
- `M5 COMMON_STARTUP_ONE_SHOT`: Common Startup bridge; self-deletes **only after verified success and evidence write**; never claim durable future-user coverage from it.
- `M6 COMMON_STARTUP_PERSISTENT`: last-resort persistent idempotent Startup fallback when M4 is concretely unavailable/failed; explicit SYSTEM/admin retirement.

Do not skip directly from an unclassified standard-user failure to M5/M6.

## First implementation wave — contract floor

Before runtime changes, encode the mode/state machine in the repository's existing contract style.

Preferred candidate if no equivalent exists:

- `harness/api/northwell-printer-materialization-policy.json`
- `schemas/harness/northwell-printer-materialization-policy.schema.json`
- validator/test wiring following current harness conventions

Contract requirements:

- modes M0-M6
- allowed transitions
- required proof per transition
- closed result codes
- one-shot/persistent distinction
- cleanup completeness
- driver/policy guardrails
- Northwell use-case binding
- no live infrastructure

At minimum support outcomes equivalent to:

- `MACHINE_REGISTRATION_PROVEN`
- `READY_ACTIVE_SESSION`
- `PENDING_NATIVE_NEXT_LOGON`
- `NATIVE_GA_STANDARD_USER_PROVEN`
- `BLOCKED_DRIVER_NOT_READY`
- `DRIVER_STAGE_SOURCE_REQUIRED`
- `DRIVER_STAGED_RETRY_REQUIRED`
- `BLOCKED_SESSION_TASK`
- `DEFERRED_LOGON_TASK_STAGED`
- `COMMON_STARTUP_ONESHOT_STAGED`
- `COMMON_STARTUP_PERSISTENT_STAGED`
- `STANDARD_USER_FORCED_MATERIALIZATION_PROVEN`
- `BLOCKED_UNCLASSIFIED_STANDARD_USER_FAILURE`
- `CLEANUP_FAILED_INCOMPLETE`

Normalize names only if validators keep equivalent closed semantics.

## Second wave — read-only classifier

Strengthen or create the smallest canonical classifier.

Inputs:

- machine-registration receipt
- loaded interactive users/SIDs
- privilege classification
- per-user queue state
- driver readiness
- relevant read-only printer-policy facts
- prior deferred artifact state

Output:

- exact next mode or blocking result
- reason code
- evidence references
- zero mutation

Do not infer "driver issue" solely from privileged success.

## Third wave — M4 preferred durable fallback

Implement the deferred logon task behind existing printer orchestration.

Requirements:

- installed only after matching M0 proof;
- no credentials/password;
- queue list bound to exact approved machine registration;
- interactive user execution;
- HKU/HKCU proof;
- repeat-safe/idempotent;
- bounded local evidence;
- explicit cleanup/retirement;
- cleanup failure -> incomplete;
- no security-policy changes.

Do not build M5 first merely because it is easier.

## Fourth wave — M5/M6 Common Startup

Resolve Windows Common Startup correctly. It is typically:

`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup`

It is **not** `C:\Users\Public\Startup`.

Prefer a Known Folder resolution path or a repository-consistent equivalent. In tests, use a temporary surrogate, never the host's real Common Startup.

Use a tracked **synthetic** template plus local/untracked generated assignment state. Never commit live queue/server/host values.

### M5

- verifies matching M0 receipt;
- materializes only those queues;
- proves HKCU/HKU;
- writes durable result;
- deletes launcher/payload only after proof + receipt;
- preserves itself/evidence after failure.

### M6

- same authority/proof checks;
- persistent and idempotent;
- does not self-delete after first user;
- explicit cleanup by machine authority.

## Fifth wave — orchestration

Integrate modes into the current canonical active-user/operator path.

Do not create a second top-level printer engine.

Expected behavior:

- existing proven M1 happy path remains fast;
- standard-user failure becomes typed/classified;
- no-user path becomes explicit;
- driver gap becomes M3 candidate only with evidence;
- M4 is preferred fallback;
- M5/M6 require explicit eligible disposition;
- batch and quick modes share the same materialization authority.

Update docs/field skill only after implementation matches them.

## P82 live-experiment order

Do not reorder these solely for convenience:

1. E0 reproduce and capture privilege split.
2. E1 task/session-token discriminator.
3. E2 driver-readiness discriminator.
4. E3 safe driver staging only if E2 proves it.
5. E4 native no-user -> standard-user next-logon observation.
6. E5 M4 with sequential eligible standard-user sessions.
7. E6 M5 only if still needed.
8. E7 M6 only if M4 unavailable/failed and persistent fallback remains required.

Each iteration reports:

`HYPOTHESIS -> BUILD -> MEASURE -> CRITIQUE -> DECIDE`

Do not repeat already-proven M0 work without invalidation.

## Guardrails that tests must enforce

Fail the sprint if a changed implementation introduces any of these:

- direct printer IP
- guessed server/queue
- `Add-Printer -ConnectionName` as Northwell authority
- password-backed scheduled task
- changes that disable/weaken `RestrictDriverInstallationToAdministrators` or equivalent printer security
- fallback execution before matching M0 proof
- success from exit code without user registry proof
- live assignment values in tracked files
- M5 deleting before evidence-backed success
- M5 described as persistent all-user delivery
- M6 silently installed as default
- cleanup failure reported as success
- Health & Hospitals inheritance

## Validation order

Run the narrowest gates first, fix failures, then expand.

1. PowerShell 5.1 parse for changed printer scripts.
2. New focused mode/classifier/fallback tests.
3. Existing:
   - `Tests/Pester/NorthwellPrinterActiveUserMaterialization.Tests.ps1`
   - `Tests/Pester/NorthwellPrinterSharelessFallback.Tests.ps1`
   - `Tests/Pester/NorthwellPrinterMapping.Tests.ps1`
   - `Tests/Pester/NorthwellPrinterUniversalEntryPoint.Tests.ps1`
   - relevant reversibility/interaction-cache tests when touched
4. printer use-case/evidence validators.
5. harness registry/schema validator if new contracts are added.
6. changed-surface workflows/CI.
7. `git diff --check`.
8. broader Pester/harness regression only after focused convergence.

A green static suite proves repository behavior only. It does not prove live standard-user repair.

## Live certification

If the current environment actually has the authorized Northwell target and required accounts/network, continue through the P82 matrix. Otherwise stop at the precise external boundary and preserve the live-cert packet; do not invent a runtime success.

For an all-user claim, one user is insufficient. Prove at least two sequential eligible standard-user sessions under the durable mechanism.

A real requested document printing remains the highest runtime acceptance layer, but keep separate:

- M0 HKLM proof
- user HKU/HKCU proof
- driver-readiness proof
- deferred lifecycle proof
- physical output observation

## Git/integration contract

- protect unrelated open work, especially ScanSnap PRs;
- one writer for overlapping printer runtime surfaces;
- keep commits coherent by lane;
- push the implementation branch;
- open/update one PR against refreshed `main`;
- inspect changed files, checks, review threads, mergeability, and behind/ahead state;
- repair owned failures and rerun;
- do not claim merged/deployed unless provider truth proves it.

## Final response contract

Report:

- completed work
- files created/modified
- mode/state implementation status
- exact validation commands + results
- live P82 experiments actually performed and their evidence
- skipped checks + why
- unresolved gaps/risks
- evidence/log/report paths
- branch, commit, PR, mergeability/checks
- deployment/production state
- next useful command/decision

Use strict evidence states: designed / implemented / locally validated / integration validated / committed / pushed / merged / deployed / production verified.

Do not call a plan, code commit, or green CI run a production repair.
