# P04 — Native Command Evidence Convergence (SysAdminSuite #528)

**Date:** 2026-10-10  
**Status:** PLANNED / REMOTE EVIDENCE CHECKED / LOCAL AGENTS NOT DISPATCHED  
**Owner:** EndeavorEverlasting/SysAdminSuite  
**Source:** TokenCorridor canonical P04 [PARALLEL] Repo-Aware Sprint + Harness Factoring Distributor; predecessor P141 selected #528.  
**Parent objective:** Reduce repeated Windows process/receipt failures using proven SysAdminSuite primitives, without recreating capabilities or corrupting the completed **PTop** Android tooling.  
**Handoff:** `docs/handoff/native-process-evidence-528-agent-handoff.md`  
**Dispatch record:** `docs/plans/native-process-evidence-528-dispatch.provisional.json`  
**No implementation authorized by planning alone.** The user's request authorizes preparing a handoff for local agents to pursue the gated investigation and justified follow-on work; new production behavior is conditional on P95 evidence.

## 1. LAUNCH ORDER (first)

1. **Panel 1 — P95-Core: existing bounded-native owner audit** (local agent, independent read-only analysis; parallel wave 1).
2. **Panel 2 — P95-Callers: Android and Git refresh consumer audit** (local agent, independent read-only analysis; parallel wave 1).
3. **Panel 3 — P95-Decision: executable seam/design decision** (after panels 1 and 2; sole design/convergence owner).
4. **Panel 4 — P07-Core: implementation of selected reusable primitive** (conditional on P95 choosing integration; parallel wave 2).
5. **Panel 5 — P07-Regression: contract/fixture and Windows test owner** (conditional on P95; parallel wave 2; must not write core module).
6. **Panel 6 — P07-Consumer/Convergence: one selected consumer, integration, CI, PTop smoke** (after 4+5, sole merge owner).
7. If P95 **REJECTS** consolidation, do not launch panels 4–6; close the strategic question with evidence and maintain the original independent implementations.

**First proof gate:** validate existing owner interfaces / regression behavior; no implementation until P95 records a reasoned architecture choice and confirms a bounded acceptable contract.  
**Final proof gate:** exact merged mainline + passing Windows regressions + independent PTop read-only application smoke *only if actually run*.

## 2. EXECUTION PLACEMENT / DISPATCH

P04 partition host and provider separately:

| Work unit | Host | Provider | State / evidence |
|---|---|---|---|
| Resolve P04, inspect GitHub repository, create plan and handoff | CURRENT_CHAT_RUNTIME | GitHub read/write | Executed now; provider metadata and tracked docs only. |
| P95 core and caller analyses | LOCAL_AGENT_RUNTIME | Local Git plus GitHub fetch | Ready for local orchestration; requires repository checkout and complete PowerShell/Windows sources. |
| P95 design / executable call-stack evaluation | LOCAL_AGENT_RUNTIME | Local Git plus GitHub PR if approved | Awaiting two parallel analyses. |
| P07 bounded implementation and fixture work | LOCAL_AGENT_RUNTIME | Local Git, CI on PR | CONDITIONAL, awaiting P95 decision. |
| Windows CI matrix | CI_OR_REMOTE_RUNNER | GitHub Actions | CONDITIONAL, triggered by a proven integration candidate. |
| PTop Windows-specific smoke | LOCAL_AGENT_RUNTIME | No production/device provider required | CONDITIONAL; cannot be proved from GitHub or this chat. |
| First-party source pin approval, physical-device mutation, firmware | OPERATOR_OR_PHYSICAL_RUNTIME | External human authority | Outside #528; **not requested here**. |

**Parallel graph width:** 2 in first wave (independent read-only analyses), 2 in second wave if P95 approves a bounded implementation (module owner and test owner). Collision owner is the P95 decision maker in wave 1 and the consumer/convergence worker in wave 3.

**Execution adapter ladder:** This chat has provider GitHub read/write but no tool binding to invoke PTop's local Cursor/Codex/OpenCode workers. No actual local child-agent or executable local-shell dispatch is observed. TokenCorridor [#142](https://github.com/EndeavorEverlasting/TokenCorridor/issues/142) independently tracks missing canonical `prompt-parallel-dispatch` schema, CLI and runtime canary; both advertised files were confirmed absent on TokenCorridor main. Do **not** fabricate validated parallel manifest conformance, claim `observed_parallelism=true`, or implement a competing dispatcher in SysAdminSuite. Record `PARALLEL EXECUTION: DEGRADED` from the current chat. The local coordinating agent must probe its own native subagents first, then repository-proven agent runners, provider workers, CI, and genuine processes; dispatch independent lanes concurrently if possible. A single local coordinator may serialize only with an explicit adapter-degradation receipt. Local agent is not to ask operator to paste each lane.

## 3. PREFLIGHT / EVIDENCE FLOOR

- Repo: `EndeavorEverlasting/SysAdminSuite`, default branch `main`. Public provider metadata established #523–#527 **merged**; #527 merge commit `846e8c1b00cf12134574d06ab0ddf071832c7024`. This is a **historical verified floor**, not a claim that current head cannot move before local dispatch.
- One open adjacent PR: #519 printer session-materialization; another #520 Windows recovery/NVMe documentation. No overlapping #528 native-process changes were identified in the inspected open PR list. Refresh before work.
- Local PTop path and machine worktree cleanliness are **not observed by ChatGPT**. Local coordinator must discover canonical path via `scripts/Resolve-SasCanonicalDevelopmentPath.ps1`, `git status --short --branch`, `git worktree list --porcelain`, `git remote -v`, `git fetch --all --prune --tags`, and provider PR state; do not infer host by username or copy PTop facts to DTop.
- Primary paths: `AGENTS.md`, `CODEBASE_MAP.md`, `harness/api/agent-routing-manifest.json`, `.claude/skills/repository-sprint/SKILL.md`, `harness/workflows/fresh-agent-intake.yaml`, `scripts/SasBoundedNative.psm1`, `scripts/Invoke-SasAndroidToolchain.ps1`, `scripts/Refresh-SasOperatorCommand.ps1`, `Tests/PowerShell/SasOperatorRefreshNativeStderr.Tests.ps1`, `Tests/survey/test_android_toolchain_contracts.py`, `Tests/PowerShell/AutoLogonS4UTaskCreateTimeoutReconciliation.Tests.ps1`, `harness/api/harness-{command,artifact,validator,outcome}-registry.json`, `docs/ANDROID_TOOLCHAIN_PROVISIONING.md`.
- Evidence: PTop installation and live checks reported in #522 closeout (private receipts on PTop; not independently inspected); four narrow follow-up merged PRs #524–#527 repaired exit, serialized output, type and empty stdout handling. Existing `SasBoundedNative.psm1` implements separately bounded process, output, timeout and S4U-specific reconciliation; Git refresh has another Git-only wrapper.
- **Proof ceiling today:** remote code and merge inspection + persisted handoff. No Windows runtime execution, no local branch inspection, no vendor source qualification, no actual autonomous local agents observed.

## 4. FACTORING / OWNERSHIP

| Topic | Primary owner | Decision |
|---|---|---|
| Verified product floor and source freshness | Repository-sprint skill, canonical development path | KEEP. No resets or forced pushes. |
| Child process start/exit/timeout/output | `scripts/SasBoundedNative.psm1` (existing potential reusable owner) | REUSE / EVALUATE; never create generic duplicate before P95 decision. |
| S4U remote scheduled-task ambiguous timeout | AutoLogon-specific consumer/provider | KEEP isolated special reconciliation; must not silently repeat remote mutation. |
| Android tooling Apply/Verify/Build/Emulator | `scripts/Invoke-SasAndroidToolchain.ps1` | KEEP lifecycle, PTop role, AVD and SDK posture; consumer candidate only. |
| Git refresh and freshness preflight | `scripts/Refresh-SasOperatorCommand.ps1` | KEEP network/source admission and user-facing semantics; consumer candidate only. |
| Shared receipt schema and contract tests | Existing harness artifact/validator registries and specific tests | REUSE; add only if shared result has real new type/owner. |
| CLI launchers and Windows authorizations | Existing CMD plus path/network-intent/handoff controls | PRESERVE; no new general launcher. |
| AndroidProvider M2 and SAS offline-qualified ADB | `harness/api/android_provider.py` and #522 | FORBIDDEN. Staged digest alone cannot be approved. |
| DTop, printer mapping, Windows recovery | Separate owners | FORBIDDEN. No changes to #519/#520. |
| Parallel worker execution implementation | TokenCorridor #142 | NOT OWNED by #528; do not recreate. |

Harness treatment: `AGENTS.md`, routing manifest, skills, capabilities, triggers, hooks and large governance surfaces remain unchanged unless P95 produces evidence that one new deterministic route is essential. Prefer enforceable test/validator assertions over additional prose. Product behavior stays in process owner and adapters, not prompts.

## 5. P95 DESIGN ACCEPTANCE — NO AUTOMATIC REFACTOR

First-wave outputs must reconstruct three real call stacks and failure cases:

- **Android:** `Manage-AndroidToolchain.cmd` → bootstrap → `Invoke-SasAndroidToolchain.ps1` → native process → stdout/stderr + exit/timeout + local private receipt → typed toolchain result; test silent success, nonzero stderr, deep serialization, path with spaces, nested CMD invocation, interrupted process.
- **Shared bounded native:** caller in network/AutoLogon → `Invoke-SasBoundedNative` → subprocess + timeout/tree cleanup → result; S4U `/Create` exact GUID task may time out after server commit and must reconcile the exact task read-only, never blindly replay create.
- **Git refresh:** operator refresh → `Invoke-SasRefreshGit` → Git command under current source/network intent → preserved stdout/stderr, `$global:LASTEXITCODE` and fail-closed stale source handling.

Compare **(A)** adopt existing `SasBoundedNative` directly, **(B)** extract a narrower result/primitive with explicit domain adapters, **(C)** leave runners separate but standardize a tiny tested evidence contract. Require module dependency graph, compatibility (Windows PS5.1/PS7), timeout and cleanup safety, no plaintext sensitive output in tracked artifacts, code/test churn and rollback. **Reject** convergence if it increases cross-lane coupling, S4U risk, instability or churn more than it prevents.

If architecture/design choice is resolved, scope implementation to one existing shared primitive, explicit domain-specific wrappers, and one high-signal consumer migration. No mass sweeping replacement.

## 6. EXECUTION WAVES / COLLISIONS

- **Wave 1:** Core and Callers are two independent read-only research lanes. They write separate `docs/research/native-process-528-{core,callers}.md` files, isolated worktrees/branches or independent note artifacts. No production code changes. Their report must include evidence path, line/function, pass/fail scenario, and design risk.
- **Wave 1 merge:** P95 decision owner reads both, performs the narrow real Windows call-stack prototype/negative controls in a disposable environment if design alternatives need it, writes `docs/plans/native-process-seam-528.design.md` with selected/rejected alternatives, issue/PR references and rollback. If rejecting, close analysis and skip P07.
- **Wave 2 conditional parallel:** shared primitive owner writes **only** selected `scripts/SasBoundedNative.psm1` or P95's exact owned seam; regression owner writes **only** new or existing relevant `Tests/` files and mock fixtures, not source. Freeze the typed interface from P95 first. Do not edit same shared registry concurrently.
- **Wave 3:** sole consumer and convergence owner integrates previous lanes, migrates **one** selected Android or Git refresh consumer, owns any necessary shared schemas/registries/CI edits, reruns relevant Windows and Python tests plus diff/format safety, inspects review/CI, performs authorized merge to main, verifies final default head. Handle failures and regressions in the same sprint; do not stop at green PR.
- **Runtime proof:** only read-only PTop Verify, existing test launchers, and isolated synthetic tests as appropriate; do not Apply/install, touch AVD/device/ADB provider, or claim production/device certification. Label host-only proof clearly; private logs stay ignored.

## 7. VALIDATION / ACCEPTANCE

**Floor:** `git diff --check`, ParseFile checks for touched PowerShell, run only relevant registration validators before broad CI. Candidate sets:

- `python Tests/survey/test_android_toolchain_contracts.py`;
- `powershell.exe -NoProfile -File Tests/PowerShell/SasOperatorRefreshNativeStderr.Tests.ps1`;
- `powershell.exe -NoProfile -File Tests/PowerShell/AutoLogonS4UTaskCreateTimeoutReconciliation.Tests.ps1`;
- `python harness/validators/validate-harness-registries.py`;
- `python harness/validators/validate-outcome-contracts.py`;
- CI `.github/workflows/android-toolchain.yml`, plus related native/S4U/refresh workflows discovered locally.

Do not blindly invoke mutation-capable installer or command. Check whether tests are scripts/Pester and requisite local dependencies before running; classify skips rather than invent passes. Add explicit negative controls for: successful empty stdout; stderr-only successful Java; nonzero exit with stdout; spaces/unicode paths; timed out process and tree cleanup; serialization preserving plain string vs object; remote S4U create may have committed; original `$LASTEXITCODE` ownership; privacy/no logged credentials; no overlapping file writes. Existing PTop Android toolchain repeat-Apply idempotence is inherited historical proof only, not a requirement to rerun Apply.

## 8. SUCCESS / FAILURE / PROOF CEILING

**Success:** P95 question resolved and either safely rejected with evidence, or a single bounded improvement integrated into main with regression proof; no introduction of new unowned native wrapper; all Android/AutoLogon/Git-refresh invariants preserved; downstream work provenance/PR links updated in #528. Any independently observed PTop smoke is explicitly separate.

**Failure/blockers:** dirty/unowned local checkout → isolated analysis without destructive reset; unresolved remote base → fetch/reconcile; unsatisfied architecture decision → stop before production writes; missing test dependency → report accurate ceiling and repair safely; no trustworthy concurrency adapter → serial only with degraded receipt; SAS digest missing → remains in #522 and does not block #528. No operator manual work unless credential, license, approval or actual physical access necessary.

**Closeout:** CHANGED | PROVED | NEXT with exact paths, evidence, commands/results, tests and skips, branch/PR/check/merge/default SHA, local vs CI proof, unqualified SAS status and first actionable next gate.

## 9. DURABILITY / AUTONOMY BLOCK

- This tracked plan and local-agent handoff are owned by SysAdminSuite #528. Cross-reference #522 but do not close it.
- TokenCorridor #142 already owns missing canonical `prompt-parallel-dispatch.v1.json` and `prompt_parallel_dispatch.py` plus OpenCode subagent canary. **This project must not invent that framework.**
- `native-process-evidence-528-dispatch.provisional.json` is a dependency- and placement-complete **transport plan**, not a validated TokenCorridor executable manifest. No `prompt_parallel_dispatch.py validate/run/verify-receipt` has run; automatic dispatch and observed parallelism are UNPROVEN from this runtime.
- Local agent coordinator should read the tracked handoff once and independently dispatch the first parallel wave if its runtime supports workers. The operator should not act as a scheduler across multiple chats.
