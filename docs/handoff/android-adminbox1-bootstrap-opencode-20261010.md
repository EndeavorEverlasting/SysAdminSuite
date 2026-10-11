# OpenCode / Admin Box 1 — EXECUTE P04 Android cold-start bootstrap

**THIS IS THE ONE HANDOFF TO GIVE OPENCODE ON ADMIN BOX 1. IMPLEMENT AND EXECUTE; DO NOT WRITE A REPLACEMENT PLAN.**

Repo: `EndeavorEverlasting/SysAdminSuite` | baseline `main@180b2e91d74a48cd9920baa4926e256c3ab4de71` at authoring, refresh safely. Canonical P04 prompt: `EndeavorEverlasting/TokenCorridor:harness/exports/prompt-invocation-catalog.v1.json`. Parent detailed execution contract: `docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md`. Existing downstream program: `docs/plans/android-suite-closeout-p04-20261010.plan.md`. Typed provisional dispatch: `docs/plans/android-suite-closeout-dispatch.provisional.json`. Historical PTop work #517/#523–#530 already merged. #522 may be closed; closure does not prove Admin Box tools.

## LAUNCH ORDER — automatically coordinate, no manual multi-chat prompts

**0. W0-INTAKE** (serial, immediately). The laptop has **NO established Android SDK or Google Android CLI**. Do not try to execute a PTop-only management tool or claim Admin Box readiness from PTop's installed state. Read `AGENTS.md`, `CODEBASE_MAP.md`, `harness/workflows/fresh-agent-intake.yaml`, new cold-start plan, `docs/ANDROID_TOOLCHAIN_PROVISIONING.md`, `docs/ANDROID_PROVIDER.md`, `scripts/Invoke-SasAndroidToolchain.ps1`, `scripts/Start-SasAndroidToolchain.ps1`, `Manage-AndroidToolchain.cmd`, `Config/android-toolchain-profile.json`, `Config/Fetch-Installers.ps1`, `scripts/SasBoundedNative.psm1` and related tests/registries. Resolve canonical repo/source/host authority and actual Windows/Admin Box 1 identity; profile `adminbox_reference` requires existing approval. Check installed executable paths, aliases, WinGet/SDK/JDK/CLI/Studio/AVD, disk/virtualization, organization network and license constraints. Identify allowed download source and whether protected network requires staged offline packages; preserve all existing local work and key material. Record private initial inventory in ignored `survey/output/android-adminbox-bootstrap/`. Do not force online fetch on protected network or send sensitive host data to unapproved OpenCode models.

**WAVE 1 — launch B1-CONTRACT || B2-SOURCE || B3-TESTS through an observed OpenCode native subagent/task adapter with isolated writer worktrees.** Verify actual concurrent launch/receipt before claiming parallelism. If adapter fails, try supported repo/CI/process rungs; safe serial work may proceed with typed degraded status. `B2-SOURCE` can discover manifests and vendor packages while `B1` builds the shared profile-aware lifecycle; `B3` adds disjoint negative fixtures.

**WAVE 2 — B4-INTEGRATE** (serial): integrate and validate contracts and adversarial tests; implement one **new tracked CMD entrypoint for Admin Box 1** delegating to existing shared provisioner adapted to validated `adminbox_reference`. Preserve existing `Manage-AndroidToolchain.cmd` PTop behavior and never strip role/profile/authority checks. Add role-specific accepted packages and exact official acquisition, install-only-missing, backup/scoped env changes, interrupted-install repair and fresh-shell verification. Register launcher/artifacts/schema/validator wiring through established repository owners. If local source is protected/offline, stage/download only through permitted cache/approved acquisition network.

**WAVE 3 — B5-LIVE-APPLY** (serial, actual authorized Admin Box 1): after approved host/profile and allowed installer source, execute `Inventory -> Plan -> Apply -> Verify` (and `Repair` only for a documented partial failure). Android Studio and Google Android CLI from official validated sources, standalone compatible JDK, SDK cmdline tools/sdkmanager/platform-tools/build-tools/API platforms, emulator and optional NDK/CMake as supported; Kotlin Gradle Wrapper smoke generating a real APK; AVD isolated boot only if Windows resources/virtualization/policy allow. Fresh CMD+PowerShell source/path checks and user-vs-system scope; no automatic licenses/elevation/policy bypass. If emulator not feasible, report `EMULATOR_RESOURCE_BLOCKED` while preserving verified CLI/SDK/build success. Rerun `Apply` as safe no-op if relevant. Keep all raw logs private/ignored and preserve existing workspace.

**WAVE 4 — B6-PROVIDER** (serial, independent SAS gate): only after current-source or protected offline source seal with the selected commit verified, inspect `Run-SasAndroidProvider.cmd status/doctor/verify --role adminbox_reference --expected-commit <approved selected SHA>`. `prepare` requires an **independently approved complete official Windows Platform-Tools ZIP digest** plus archive/role/seal safety, and uses same `--expected-commit`. Development `adb.exe` remains non-qualified, even when working perfectly. Absence of pin means `QUALIFICATION_AUTHORITY_REQUIRED`, not undoing completed developer install.

**WAVE 5 — B7-CLOSEOUT** (serial): run focused Android toolchain/Pester PS5.1+7/native process regressions and provider/H&H policy tests, relevant registry/outcome/CI/fixture E2E and real Admin Box smoke; repair red CI, inspect hosted review, push/scoped PR/merge into default main when authorized and gates pass; recheck exact merged state. Update canonical issue/artifact owner truth; no release/device/production claim from fixtures. Report `CHANGED | PROVED | NEXT`, actual source SHA, actions/paths/versions, tests/skips, host profile, package provenance and authority, real APK/emulator or blocker, SAS bundle proof/authority blocker, privacy proof, PR/merge and next actionable gate.

## Portability panel B1-CONTRACT (one isolated code writer)

```text
EXECUTE B1-CONTRACT: role-aware Android developer lifecycle, no PTop regression.
Repo EndeavorEverlasting/SysAdminSuite; host Admin Box 1 verified, ref refreshed canonical main; sprint P04 Android coldstart.
Owned: scripts/Invoke-SasAndroidToolchain.ps1 (shared lifecycle), new tracked Admin Box CMD/boot front door, new sanitized adminbox developer package profile and host-authority validation, focused shared lifecycle tests; isolate worktree and coordinate shared schema/registry finalization through B4. Forbidden: AndroidProvider M2 runtime/role semantics, H&H firmware, PTop host spoof, AgentSwitchboard internals, unowned downloads/keys/AVD deletion.
Read: AGENTS.md, CODEBASE_MAP.md, docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md, scripts/Invoke-SasAndroidToolchain.ps1, scripts/Start-SasAndroidToolchain.ps1, Manage-AndroidToolchain.cmd, Config/android-toolchain-profile.json, relevant schema/validator/fixtures and network/install source owners.
Preflight: branch/worktree/dirty status, current main/PRs, host authority and source/network. Preserve PTop engine baseline including exit/output semantics.
Tasks: extract smallest role-scoped profile layer and common Inventory/Plan/Apply/Verify/Repair; bind adminbox_reference to independently resolved approved host profile; keep ptop_lab unchanged; create simple tracked front door; adopt current source-verified executable discovery, official installers, additive backed-up env PATH/JAVA_HOME/ANDROID_HOME, exact role whitelist. Do not make PTop's host authority sample a real Admin Box authorization. Ensure protected network fails safely and user/system install scope is explicit.
Validation: PTop eight Android contract groups, new role-mismatch/host-profile/source negative fixtures, PS5.1/7 Pester, registry checks where changed; do not claim actual installation from fixtures.
Artifact: scoped commit/ref + changed paths/test receipts for B4 single writer. Final CHANGED | PROVED | NEXT.
Next: submit B1 contract+ref to B4-INTEGRATE, not operator.
```

## Portability panel B2-SOURCE (parallel, source provenance)

```text
EXECUTE B2-SOURCE: discover sanctioned Android developer installers and independent SAS platform-tools authority.
Repo EndeavorEverlasting/SysAdminSuite; host actual Admin Box 1; read-only source/local inventory lane, no runtime install.
Owned: disjoint sanitized source research and private provenance receipt, **no** changes to B1 files. Forbidden: autoaccept licenses, bypass managed network, invent approved hash, run provider prepare, copy PTop private keys/SDK state, disclose organizational data.
Read AGENTS.md, CODEBASE_MAP.md, docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md, Config/Fetch-Installers.ps1, docs/ANDROID_PROVIDER.md, Config/android-toolchain-profile.json, official vendor manifest/package-factory owners, source-seal and network policy.
Tasks: enumerate known installed/missing Admin Box tools, authoritative current WinGet IDs and vendor package metadata; discover existing offline approved cache or permitted guest/Internet acquisition route. Classify supported Java/JDK and SDK/CLI package command/version/Gradle matrix, disk/AVD/NDK constraints. Output machine-readable acquisition decision per component and exact approved source/path class. Separately find existing independently approved Google Platform-Tools official archive SHA256; do not approve candidate hash. If first-party approval missing, emit typed human-gate packet, continue independent sources.
Validation: source provenance/approved permit/host safe data policy; no synthetic vendor claims, no install run. Final CHANGED | PROVED | NEXT and opaque ref to B4.
Next: return source decision, not downloads list for operator.
```

## Portability panel B3-TESTS (parallel, disjoint fixtures)

```text
EXECUTE B3-TESTS: cold-start regression/fixture gate for Admin Box 1.
Repo EndeavorEverlasting/SysAdminSuite; read current repo + cold-start plan; separate isolated test branch/worktree.
Owned: new Android Admin Box coldstart test/fixture files ONLY until B4 owns shared tests/registry. Forbidden: production lifecycle engine, provider runtime, shared schema without coordinator, real install/AVD/device mutation.
Tasks: create tests which initially fail for missing role-aware lifecycle: no Android CLI/SDK/JDK, user alias vs machine scope, missing WinGet, wrong source hash, protected network, no independent SAS SHA, profile mismatch, low disk, API/version mismatch, license/elevation, interrupted acquisition repair, environment backup/restore, source path spaces, PS5.1 native exit/stderr, concurrent writer overlap, SDK adb not SAS, low-resource emulator and no-op second Apply. Check PTop unchanged.
Validate synthetic tests and negative-path contracts; no pretending host live proof. Commit disjoint test ref; send B4 exact tests and expected fixes.
Next B4-INTEGRATE.
```

## B4–B7 integration ownership

Only the coordinating agent may edit common schemas/registries and integrate B1/B2/B3. It must actually finish reachable Admin Box installation and source qualification gates, not stop at a PR or task list. The detailed P04 plan is authoritative for rollback, typed receipt fields, and separation of Admin Box vs PTop vs DTop. There must be no new generic package installer and no second AndroidProvider. If a real operator-only approval blocks one component, return **BOUNDARY | IMPACT | PROVED | RECOVERY | NEXT** for that component while completing every independent ready lane. The local agent must not ask the operator to paste separate panel prompts.

**First action in the local OpenCode session:** inspect this very file from refreshed SysAdminSuite main, verify actual Admin Box 1 and source/host permissions, inventory tools **as absent until independently observed**, then autonomously dispatch B1/B2/B3 and carry the program through to real Apply/Verify on Admin Box 1.
