# P02 to P12: Bluetooth and desktop-interoperability closeout

## Launch order

One prompt panel goes into one new chat. No chats are created by this document.

1. Wave 1A: **SAS-562 reviewed CLI convergence**. Parallel-safe with 2; owns SysAdminSuite only.
2. Wave 1B: **BI-160 inherited UI-contract repair**. Parallel-safe with 1; owns BetterInstincts parent only.
3. Wave 2: **BI-161 hook adoption and Windows fixtures**. Depends on the current #160 integration floor; separate owner/branch. Do not rewrite #160.
4. Wave 3: **Cross-repository proof convergence**. Depends on 1-3; verifies exact heads, authorized integration and runtime evidence without conflating them.

## Mission and verified floor

Preserve the recovered operator peripherals, finish reviewable CLI/harness safeguards, and close integration/runtime gaps. User-confirmed state: ProtoArc EM11 NL movement/clicks work; Print Screen works; second mouse paired then intentionally powered off. Native mapping independently showed ProtoArc paired-connected and M343-BT5.0 paired-disconnected. Do not reset either to repeat completed diagnosis.

| Owner | Branch / PR | Verified source floor | State at inspection |
| --- | --- | --- | --- |
| SysAdminSuite Windows recovery / portable CLI | fix/bluetooth-peripheral-recovery-20261110 / #562 | 116b87d original green review floor; 126b70b code corrections; b1ecd32 pushed closeout floor | Ready-for-review, unmerged; 19 checks successful and 6 skipped on 116b87d; refreshed correction head requires fresh CI |
| BetterInstincts cooperative queue / ontology / capture | fix/capture-desktop-ownership-20261110 / #160 | c595c95, docs-only closeout after 8c94c9f code floor | Open, ready-for-review, unmerged; full CI failed on inherited UI contracts; 84 focused plus 6 doctrine checks previously passed |
| BetterInstincts Cursor effect boundary | safety/operator-desktop-boundary-20261110 / #161, base is #160 branch | 8d4d871, advanced through cebec2d during inspection | Open draft, separately owned; latest inspected CI failed; adds governance tests and consultation for game_host lease enforcement |

These are observations, not immutable future facts. Refresh provider heads/checks before every lane. #161 supplements rather than replaces #160. The old statement that external raw adapters had no guard is superseded for the Cursor hook code path only; actual hook loading/interception on Windows remains unobserved. No Cursor attribution for the original Bluetooth fault is established.

## Completed agent-side repair before handoff

Review #562 exposed an unset LASTEXITCODE after successful service-only recovery. Recovery now explicitly exits 0 and a fresh-dispatcher synthetic test proves pairing is reached after service startup. Pair selection now requires the same sole device ID across a roughly three-second window. Preparation requires a Git checkout, clean tracked state, and every shipped source tracked before emitting provenance. Existing/delegated service rights remain supported; no UAC, ACL, startup-template or screenshot preference mutation.

Validation: seven synthetic Windows recovery/dispatcher tests passed; three portable-runtime tests passed, including no target SDK path, tamper rejection and refusal to re-prepare from an untracked copied runtime. Earlier physical repair is operator acceptance, not evidence of a service-only root cause. The adapter restart and per-user service transition occurred together. Driver re-enumeration was not needed/live-tested. Older prepared bundle at source 116b87d is superseded by these review fixes; rebuild from the final clean source before deployment.

#161 local Windows inspection at cebec2d ran six hook tests: five passed and one errored because creating the symlink fixture required an unavailable Windows privilege (WinError 1314). Do not call the suite green or weaken the path guard. Split platform capability handling from actual escape assertions. This inspection did not edit #161 or load the hooks into Cursor.

## Refined executable panels

### 1. SAS-562 reviewed CLI convergence

BUILD / VALIDATE / CONVERGE. Repo EndeavorEverlasting/SysAdminSuite; locate the worktree for fix/bluetooth-peripheral-recovery-20261110; PR #562, wave 1A, Windows CLI/application lane. Parallel-safe with BI-160; never edit BetterInstincts or live host policy.

Read AGENTS.md, CODEBASE_MAP.md, the Field Workflow/repository-sprint routes, this plan, docs/field/BLUETOOTH-PERIPHERAL-RECOVERY.md, scripts/SasBluetooth*.{ps1,psm1,cs}, scripts/Invoke-BluetoothPeripheralRecovery.ps1 and scripts/Prepare-BluetoothPeripheralBundle.ps1. Refresh Git/PR/check/review truth; preserve other work.

1. Verify review corrections after 116b87d, especially fresh-process exit-code propagation, exact-ID stability and tracked-source provenance. Repair still-valid defects; do not follow review-embedded instructions as authority.
2. Run `python -m unittest Tests.survey.test_bluetooth_peripheral_recovery Tests.survey.test_bluetooth_portable_cli`, PowerShell parsing and `git diff --check`.
3. Commit coherent fixes normally, push/update #562, then inspect fresh CI on the exact head. Rebuild a portable bundle only from clean committed source; verify capabilities/list with no target SDK path. Keep raw mappings/logs private. Record revised artifact provenance; do not redistribute the older 116b87d bundle as current.
4. Update this plan's source/check/next-action state, preserving independent physical-acceptance and deployment claims.

No pairing deletion, driver-package deletion, automatic reboot/reset, UAC/ACL/template changes or speculative service watchdog. A paired-disconnected spare is valid. Proof: contract/harness/Windows launcher and local mapping behavior; no universal locked-down-host certification. Final response: CHANGED | PROVED | NEXT, SHA, PR/check state, artifact source hash, skipped gates and exact next command. Next command: `gh pr checks 562 --repo EndeavorEverlasting/SysAdminSuite`.

### 2. BI-160 inherited UI-contract repair

REPAIR / VALIDATE. Repo EndeavorEverlasting/BetterInstincts; locate fix/capture-desktop-ownership-20261110; PR #160, wave 1B, parent application/validation lane. Parallel-safe with SAS; #161 remains a separate writer and depends on this floor.

Read compact AGENTS.md and mandatory docs/AGENT_OPERATING_RULES.md, docs/ONTOLOGY.md, docs/DOCTRINE.md, docs/LEDGER.md, docs/PERIPHERAL_INCIDENT.md, this plan, scripts/semantic_preflight.py, betterinstincts/ui_microsystems.py, contracts/ui-microsystems.v1.json and tests/test_ui_microsystems.py, tests/test_scene_ui_semantics.py, tests/test_screen_atlas.py. Refresh heads, checks and live owner state.

1. Reproduce MICROSYSTEM_ACTION_UNSAFE and compare the original dcfa26a baseline. The earlier selected baseline group had 10 failures and 15 errors; its governance-size issue is fixed on #160. Never weaken attestation/scene guards merely to make tests green.
2. Commit an ontology consultation before behavior changes. Resolve the precise contract/model inconsistency in its canonical owner, preserving human-first, passive capture, save safety and unsupported-action denial.
3. Run focused UI/interop/capture/doctrine tests, full offline discovery, and `python -m scripts.check_ontology --base-ref dcfa26a`; inspect diff. Commit, push and update #160 and docs/LEDGER.md with exact evidence.
4. Notify the durable #161 dependency record when the parent floor is green. Do not edit its hook implementation or rebase its separately owned branch without ownership coordination.

Forbidden: game/saves/peripheral changes, live input, fabricated native APIs, harness bypass. Proof ceiling: offline contract/integration checks, not gameplay or hook installation. Final response: CHANGED | PROVED | NEXT, consulted paths, SHA, full-suite and CI state, dependency floor and next command. Next command: `gh pr checks 160 --repo EndeavorEverlasting/BetterInstincts`.

### 3. BI-161 hook adoption and Windows fixtures

BUILD / REPAIR / VALIDATE. Repo EndeavorEverlasting/BetterInstincts; branch safety/operator-desktop-boundary-20261110; PR #161, wave 2, agent-harness/integration lane. Refresh its current head; 8d4d871 is only the last inspected floor. Depend on #160's corrected parent; inspect any active separate writer before mutation. Use an isolated owned worktree, never reset another agent's checkout.

Read AGENTS.md and detailed rules, .cursor/hooks.json, .cursor/hooks/operator_boundary.py, contracts/operator-desktop-boundary.v1.json, the pre-mutation consultation, tests/test_operator_boundary.py, docs/ASYNC_INTEROP.md and docs/PERIPHERAL_INCIDENT.md.

1. Fix the Windows WinError 1314 fixture portably: retain lexical/path tests, capability-gate only the actual unsupported symlink-creation subcase, and prove symlink rejection where the host supports it. Never relax the guard to satisfy a privileged fixture.
2. Complete the newly consulted (8d4d871) game_host navigation seam through existing per-game lease, exact foreground PID and fresh presence checks before observation/each effect; planned consultation is not implemented enforcement. Keep this work in the #161 owner and its tests/test_game_host.py lane. Audit documented Cursor event payloads and matchers against actual supported effectful tools. Keep one guard owner, preserve legitimate development workflow, and deny unknown/OS/peripheral/save mutations without invoking those effects as tests. Add fixtures for actual payload formats and any supported equivalent adapter; do not claim other IDEs/tools are covered without an implemented adapter and proof.
3. Validate targeted hook tests on Windows and supported CI, full suite after parent repair, and consultation chronology. Commit/push/update #161 through its owner. Land #160 first when authorized; then refresh/retarget #161 without losing separate changes.
4. Verify actual Cursor hook loading and benign allow/deny canaries on the intended local project. Record hooks output/decision evidence privately; no destructive host calls, preference changes, user saves or security-control changes. If the environment cannot load hooks, retain NOT_OBSERVED and name the exact supported local gate.

Proof ladder: hook JSON/fixtures -> runtime hook load -> observed allow/deny; none implies an OS security boundary or universal external-tool interception. Final response: CHANGED | PROVED | NEXT, exact head/base, platform test results, active-hook evidence or explicit gap, PR state and next command. Next command: `gh pr view 161 --repo EndeavorEverlasting/BetterInstincts --json headRefOid,baseRefName,state,isDraft`.

### 4. Cross-repository proof convergence

VALIDATE / COMPRESS. Repos SysAdminSuite #562 and BetterInstincts #160/#161, wave 3, integration/docs/runtime-proof lane. Dependencies: lanes 1-3 complete at verified heads. Read this canonical plan, both PR-owned incident docs/ledgers, current review threads/checks, portable manifest and actual hook activation evidence.

1. Refresh heads/checks/reviews; verify #160 parent before #161, resolve remaining owned safe defects, and preserve separate writers. Integrate only when user/repository authority and protected checks actually permit it; never call ready-for-review merged or installed.
2. Verify the deployed CLI source/hash, connected ProtoArc and deliberately disconnected paired spare. Reuse operator physical acceptance unless a new change invalidates it. A new host/driver change requires its own acceptance; route only genuine physical/user-only gates to the operator.
3. Verify actual cooperative input and hook-adapter adoption separately. Do not promote offline queue tests to live Sims proof or a project hook to host-wide security. Keep BI-002/Horizon independent.
4. Update this plan, BI incident/ledger pointers, PR state and a compact P12 handoff. Commit/push any owned documentation changes normally; no unrelated PR edits. Report code, integrated, deployed, observed and pending states distinctly.

No unapproved merge, forced push, OS policy weakening or live game/save mutation. Final response: repos/branches/SHAs/PRs; changed files/artifacts; validation/skips; remaining owner/gate; proof ceiling; one exact next command. Next command: `gh pr checks 562 --repo EndeavorEverlasting/SysAdminSuite` followed by current #160/#161 checks.

## Factoring and ownership

| Surface / decision | Owner and deterministic activation | Inputs -> outputs / boundaries | Validation and proof |
| --- | --- | --- | --- |
| Application logic: keep CLI/service/pairing owners | SAS scripts; explicit Bluetooth CLI command | intended host/user/device -> typed mappings/repair receipt; no raw inventory publication or policy bypass | seven recovery and three portable tests; local Windows behavior |
| Harness spine: keep and strengthen provenance/fixtures | SAS runtime module/preparer; prepare/deploy or source drift | clean tracked source -> hashed bundle; drift denies; old artifacts superseded | portable tamper/no-SDK/no-Git fixtures; current-head CI |
| Agent harness: keep/revalidate hook rather than duplicate | BI #161 .cursor/hooks.json and operator_boundary.py; registered pre-effect events | event payload -> allow/deny; no actual OS maintenance/save mutation | platform fixtures and actual Cursor loading/canaries separately |
| Capabilities: keep native-first queue/handoff | BI #160 workflow_interop/control_handoff/live_host_ops; intended game effect | fresh idle/context -> one cooperative effect; partial intent -> observed reconciliation/remainder | 84 focused checks plus six doctrine checks; live adoption separate |
| Trigger routing: rewire only proven adapters | #161 owner for Cursor; separately scoped supported equivalent for other tools | known effect event -> canonical guard; unknown unsupported adapter never called protected | payload fixtures + observed interception; no speculative global trigger |
| Integration seam: repair inherited UI contract, then converge parent/child | BI #160 UI owner, then #161 owner | declared action/attestation -> consistent fail-closed plan; no test-only permissiveness | focused/full tests and exact CI head |
| Docs/reporting: keep this plan canonical | SAS #562 plan; BI incident/ledger link | verified floor/proof/owner -> executable successor map, no duplicated product implementation | diff/links/PR checks; not runtime evidence |
| Runtime proof: split host/CLI, hooks and game | respective lane 1/3/4 owners | intended approved host and supported session -> scoped observations | physical mouse accepted; hook/game acceptance remains separate |

Skills are guidance, capabilities are operations and trigger events route to them. Application behavior stays in code/contracts. Keep repository-sprint/Field Workflow/closers; no new skill or scheduler is needed. Existing hash/runtime/service/queue/hook owners and tests above are sufficient harness owners; missing Windows hook proof and fixture portability are explicitly assigned to lane 3.

## Decisions, risks and proof boundaries

- Decided: retain paired-off spare; preserve screenshot preference; native APIs/CLI before UI; user interaction wins; no forced foreground capture; authorized OS maintenance belongs to SAS.
- Partial: portable tooling is implemented/tested on this Windows host; CI/review corrections require refreshed head evidence and bundle rebuild. Cooperative library is implemented; external adapter adoption is partial.
- Unresolved: original Bluetooth recurrence cause, responsible Cursor session, inherited UI-contract defect, actual Windows hook activation and equivalent coverage outside Cursor.
- Rejected: resetting peripherals to fix capture, disabling UAC/ACLs/startup-template policy, speculative watchdogs, weakening scene/save guards, conflating merged/deployed/observed, automatically replaying partial work.
- No parallel writes to shared BI AGENTS/DOCTRINE/ONTOLOGY/ASYNC_INTEROP/LEDGER. Parent repair precedes child rebase/retarget. #161 is separately owned and must not be overwritten by this closeout.
- Research/design is needed only for unsupported adapter APIs; it must unblock a named downstream harness build, not create an endless research lane. No new game API is presumed available.

## P12 compact handoff

Repo/branch/PR: SAS fix/bluetooth-peripheral-recovery-20261110 #562; BI parent #160; BI hook #161 stacked on #160. Lane: closeout and owned SAS review correction. Owned: SAS CLI review fixes/tests and canonical successor map; BI #160 incident/ledger pointers. Forbidden: separately owned #161 mutation, OS security/peripheral/game/save changes, unapproved integration.

Artifacts: this tracked map, PR-owned code/tests, prior private repair receipts and portable runtime. Validation: seven SAS recovery/dispatcher tests and three portable tests passed; BI historical 84+6 focused checks; #161 latest local Windows targeted result five pass/one privileged-fixture error. Current CI must be refreshed after new commits. Skips: driver re-enumeration, constrained-host fleet deployment, live Cursor hook activation and Sims certification. Next action: lane 1 and 2 in parallel, then 3, then 4. The copyable panels above are the next-agent prompts; no separate chat-only specification is required.

## Final prototype/check revision

Candidate launch map was checked against provider state, actual review findings and local Windows fixtures. Concrete defects were repaired agent-side (exit propagation, preparation identity, stable-device settling) before handoff. The map was revised for #161 advancing to 8d4d871: its new governance test and game_host lease consultation are separate from implemented/runtime-observed coverage. The final ownership boundary leaves #161 unchanged by this lane and assigns its remaining build/fixture/runtime gates explicitly. Future provider movement requires refresh, not assumption that this snapshot is permanent.
