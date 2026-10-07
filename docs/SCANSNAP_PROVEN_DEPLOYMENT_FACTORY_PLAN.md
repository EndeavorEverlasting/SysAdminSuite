# ScanSnap proven-deployment-factory execution plan

**Status:** execution plan for the next Cursor sprint  
**Canonical floor:** `main@9a0d2756f77d0b41582c70bc6fa68ac1fd3829af`  
**Control host:** Admin Box 1 = `LPW003ASI173`  
**Home prototype target:** `CheexMcClappeth`  
**Field targets:** `WRH250STR001`, `WRH250STR002`

## Outcome

Deliver ScanSnap remotely and unattended by reusing SysAdminSuite's existing production-proven software deployment machinery instead of maintaining a parallel ScanSnap transport.

The operator should not have to repeatedly decide what to try next. Runtime failures are typed branch points: diagnose the failed stage, preserve proven stages, repair or select the next already-supported path, and continue until the highest currently reachable completion state is exhausted.

## Prompt provenance

This plan invokes:

- **P04 — Repo-Aware Sprint + Harness Factoring Distributor**
  - canonical repository: `EndeavorEverlasting/TokenCorridor`
  - registry: `src/tokencorridor/interface/promptkit/registry/base/prompts.json`
  - source blob: `848728632c1243ebba023fa0012292a2ad33cada`
- **P82 — Prototype-Measure-Refine Delivery Loop**
  - canonical repository: `EndeavorEverlasting/TokenCorridor`
  - registry: `src/tokencorridor/interface/promptkit/registry/prompts/spec-architecture-prompts.v1.json`
  - source blob: `5926a198a14567de55110ed19e922fc444b4dec7`

P04 owns repository factoring and convergence. P82 owns empirical package/auth/target experiments. Neither prompt replaces implementation.

## Proven SysAdminSuite factory — reuse this

### Canonical SMB + SYSTEM transport

`scripts/SasSoftwareDeploymentAdapter.psm1` owns `Invoke-SasSmbScheduledTaskDeployment`.

It already accepts:

- exact remote computer identity;
- **local installer path**;
- expected source SHA-256;
- package name;
- installer arguments;
- package validation checks;
- run ID / evidence root.

Therefore ScanSnap does **not** need the internal Northwell package share in order to reuse the proven transport.

The adapter already implements:

1. source hash verification immediately before staging;
2. `ADMIN$` and `C$` verification;
3. run-scoped staging under `C:\ProgramData\SysAdminSuite\SoftwareInstall\<run-id>`;
4. installer + generated worker hash verification through the target share;
5. one-time remote Task Scheduler execution as `SYSTEM`;
6. target-local installer hash verification;
7. installer execution with timeout and 0/3010 handling;
8. package-specific validation;
9. closed worker-result retrieval;
10. staged payload removal;
11. task deletion;
12. run-root removal;
13. verification that task and staging are absent;
14. independent install / validation / preservation / teardown classification.

### Production proof

`docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md` records production proof from PR #229 for one authorized BCA installation using admin-share staging + Remote Task Scheduler, including returned result, cleanup, and technician-confirmed application behavior.

`docs/handoff/deployment-transport-convergence.md` records the convergence chain:

- PR #229: production SMB/Task Scheduler implementation proof;
- PR #246: first-class canonical PowerShell SMB/Task Scheduler application transport;
- PR #250: harmless one-target live-cert producer with SYSTEM execution, result retrieval, and complete cleanup.

This is the factory to reuse.

### Validation / finalization factory

`scripts/SasSoftwareInstallFinalization.psm1` already supports deterministic validation checks:

- `FileExists`
- `FileSha256Equals`
- `FileVersionEquals`
- `JsonPropertyEquals`
- `RegistryValueEquals`
- `UninstallEntry`
- `ServiceExists`

Use these for ScanSnap detection instead of retaining a separate ad-hoc detection vocabulary when the same meaning can be represented canonically.

### Transport/readiness factory

Reuse:

- `scripts/Test-SasSoftwareDeploymentTransport.ps1`
- `scripts/SasSoftwareDeploymentAdapter.psm1`
- `docs/SOFTWARE_DEPLOYMENT_LOW_NOISE.md`
- `scripts/SasNorthwellNetworkAuthority.psm1`
- `scripts/SasNetworkGuard.psm1`

Protected Northwell execution should converge on the existing `kerberos_smb_task` readiness model.

## What remains ScanSnap-specific

ScanSnap owns only:

1. authoritative web/package acquisition;
2. package identity/version provenance;
3. local installer path;
4. SHA-256;
5. vendor-supported unattended arguments;
6. deterministic post-install validation;
7. mapping of the package manifest into canonical validation checks;
8. multimodal logical target resolution;
9. operator-facing ScanSnap CMD/front door.

Do not duplicate:

- SMB copy engine;
- scheduled-task lifecycle;
- SYSTEM worker;
- hash verification;
- closed result retrieval;
- cleanup;
- validation execution;
- evidence/finalization state machine.

## Existing ScanSnap code disposition

Current:

`Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.ps1`

contains its own staging + scheduled-task installer path.

The sprint should converge this toward a thin ScanSnap orchestrator around the canonical factory.

### KEEP

- `Deploy-ScanSnap.cmd` as the operator-facing package command unless repository routing proves the `sas` dispatcher is the stronger direct owner;
- `Bind-ScanSnapPackage.ps1`;
- package manifest/provenance;
- `hosts_smoke.txt`;
- `hosts_field.txt`;
- ScanSnap-specific logs/status/runbook;
- target-mode resolution logic that does not already have a canonical owner.

### REPLACE / FACTOR OUT

From the ScanSnap engine, retire duplicated logic for:

- run-scoped staging;
- installer + worker copy;
- remote SYSTEM task creation/run;
- result polling/retrieval;
- package detection after install where canonical validation checks suffice;
- task cleanup;
- target staging cleanup;
- final transport classification.

Delegate these to `Invoke-SasSmbScheduledTaskDeployment`.

Do not delete the old path until the canonical delegation is tested and proves equivalent-or-stronger behavior. Preserve last-known-good history through Git.

## Package-source model

ScanSnap is web-sourced.

Flow:

```text
authoritative vendor/client web source
-> Admin Box local installer
-> SHA256 + signer/version/provenance
-> silent-argument qualification
-> validation-check qualification
-> bound ScanSnap manifest
-> canonical local-installer SMB/SYSTEM adapter
-> remote workstation
```

The validated generic front door currently assumes an approved UNC software-share root. Do **not** distort the web-sourced ScanSnap package into that model merely to satisfy an existing request schema.

For this sprint, converge below that source-policy layer:

`ScanSnap package orchestrator -> SasSoftwareDeploymentAdapter -> finalization/evidence factory`.

If the repository later generalizes the validated request schema to support pinned local/web-acquired artifacts, do that as a separate shared-owner convergence unless it is strictly required for this deployment.

## Unattended invariant

Normal deployment must remain controller-initiated and target-unattended.

No field success path may require:

- physical workstation location;
- target console access;
- target-side clicks;
- end-user participation;
- user login;
- target-side credential entry.

The authorized logical identity and remote management path are sufficient.

## Multimodal target model

### LAB_LOCAL

Controller: `LPW003ASI173`  
Target: `CheexMcClappeth`

Use the home environment to prove the same unattended deployment shape.

Identity candidates may include:

- `CheexMcClappeth`
- `CheexMcClappeth.local`
- runtime IPv4 after exact resolution

Do not hard-code the prior DHCP address.

The canonical SMB adapter currently requires an exact FQDN. First test whether `CheexMcClappeth.local` resolves to the intended PTop and satisfies the factory unchanged.

If it does, KEEP the factory unchanged.

If it does not, that is a P82 result, not a dead end: implement the smallest typed `LAB_LOCAL` identity adaptation needed **above** the core staging/worker lifecycle, preserving the exact-FQDN rule for protected production modes.

### NORTHWELL_PROTECTED

Exact targets:

- `WRH250STR001`
- `WRH250STR002`

Use existing Northwell network authority and corporate DNS/FQDN resolution.

### NORTHWELL_VPN

Treat a live `DomainAuthenticated` protected VPN path as another authority route into the same target deployment factory.

VPN changes reachability/identity authority, not package/install architecture.

## Authentication strategy

### Protected Northwell / VPN

Prefer the factory exactly as designed: current authorized Windows admin token + Kerberos/CIFS + remote Task Scheduler.

### Home lab

Prior evidence:

- target was reachable;
- no Northwell DC was available;
- hostname auth classified `AUTH_DC_UNAVAILABLE`;
- direct-IP auth classified `LOGON_FAILURE`.

Do not repeat that same domain-token experiment.

Use P82 to test the smallest unattended local-auth variation.

Inspect repo-proven credential/session patterns such as `EnvSetup/Deploy-Shortcuts.ps1`, but do not weaken the canonical protected adapter's no-credential parameter contract merely to solve the lab.

Preferred order:

1. exact `.local` identity + existing controller token if a valid local trust/account context already makes it work;
2. explicit controller-side local-account session/bootstrap using repository-safe transient credential handling;
3. if the Task Scheduler RPC leg still requires a credential-aware lab shim, implement it as the smallest typed lab authentication seam while reusing the canonical worker, staging root, validation and cleanup lifecycle;
4. do not require any interaction on PTop.

A lab-auth adaptation must not become the production Northwell credential model.

## One-shot failure continuation matrix

A failure class is a work queue entry, not a sprint-ending answer.

| Failure | Continue with |
|---|---|
| installer absent | acquire official package, fingerprint, bind, continue |
| product identity ambiguous | exhaust repo/client/vendor evidence; bind only when one exact product is defensible |
| hash mismatch | reacquire/rebind source; do not stage mismatched bytes |
| short hostname unresolved | mode-aware exact alias/FQDN resolution; preserve requested identity |
| `AUTH_DC_UNAVAILABLE` in LAB_LOCAL | use local-auth branch; do not wait for a corporate DC |
| `LOGON_FAILURE` in LAB_LOCAL | change authentication context, not target discovery |
| `ADMIN_SHARE_READY` but task RPC fails | inspect canonical readiness dependencies (135/Schedule/task query) and repair/retry only that stage |
| task creation/run fails | preserve staging/hash proof; diagnose scheduler/auth; rerun task stage, not package acquisition |
| installer exit fails | retrieve closed result; inspect vendor exit; refine evidenced args; rerun package execution |
| installer succeeds but validation fails | inspect actual installed state; fix the validation rule if wrong; avoid blind reinstall when package is present |
| cleanup fails | perform cleanup/recovery only; do not reinstall a package that already validated |
| one target fails | continue the other authorized target independently |
| home mode remains blocked | preserve receipt and move to Northwell/VPN; home success is not a field prerequisite |

Only a genuinely external requirement (for example an unavailable secret, unavailable VPN session, or unreachable authorized target) may stop that specific lane. Independent work continues.

## P82 experiment contract

Each empirical branch records:

`HYPOTHESIS -> BUILD -> MEASURE -> CRITIQUE -> DECIDE`

Decisions:

- KEEP
- REFINE
- DISCARD

A REFINE decision immediately executes the next bounded attempt when the required capability is available. It is not a request to return to planning.

## Execution waves

### Wave 0 — refresh and branch

- verify `main@9a0d2756...` or newer;
- inspect status/worktrees/open PRs;
- protect unrelated changes;
- create bounded implementation branch.

### Wave 1 — parallel

**Lane A: package qualification**

- locate/download exact authoritative ScanSnap package;
- compute hash/signature/version;
- qualify silent arguments;
- map detection to canonical validation checks;
- bind/read back manifest.

**Lane B: deployment-factory convergence**

- refactor ScanSnap orchestrator to import/use `SasSoftwareDeploymentAdapter.psm1`;
- translate ScanSnap manifest detection to canonical validation checks;
- keep WhatIf non-mutating;
- make evidence expose requested identity, resolved identity, mode and canonical adapter result;
- add regression tests proving no duplicate schtasks/staging engine remains on the canonical path.

### Wave 2 — home live path

- controller proof = `LPW003ASI173`;
- exact PTop resolution;
- home authentication branch;
- canonical readiness/staging/SYSTEM/install/validation/cleanup;
- continue through final classification.

Preferred success:

`DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED`

Map that to the ScanSnap user-facing success:

`INSTALLATION_DETECTED`

without losing the stronger canonical evidence.

### Wave 3 — protected field

When Northwell/VPN authority is available:

- resolve `WRH250STR001/002` to exact corporate identities/FQDNs;
- run canonical low-noise readiness independently per target;
- deploy the bound ScanSnap package through the same canonical adapter;
- preserve independent per-target results.

## Tests

At minimum run after implementation changes:

- `Tests/Pester/ScanSnapDeploy.Tests.ps1`
- `Tests/Pester/SmbScheduledTaskDeployment.Tests.ps1`
- `Tests/survey/test_canonical_smb_task_deployment_contracts.py`
- relevant transport/network-authority contracts if those owners changed.

Add ScanSnap regression coverage for:

1. web/local installer path can feed the canonical adapter;
2. source SHA is passed exactly;
3. DetectType/DetectValue maps to one or more supported canonical validation checks;
4. canonical adapter receives resolved FQDN in protected mode;
5. LAB_LOCAL identity adaptation cannot alter protected FQDN rules;
6. WhatIf performs no target mutation;
7. target results remain independent;
8. `INSTALLATION_DETECTED` is emitted only from canonical completed+validated evidence;
9. duplicate legacy ScanSnap remote task/staging execution is no longer the selected production path.

## Repository artifacts

Update:

- `Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.ps1`
- `Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.cmd` only if needed for the converged operator surface
- `Tests/Pester/ScanSnapDeploy.Tests.ps1`
- ScanSnap runbook/status docs
- package manifest after real package qualification

Reuse, do not fork:

- `scripts/SasSoftwareDeploymentAdapter.psm1`
- `scripts/SasSoftwareInstallFinalization.psm1`
- `scripts/Test-SasSoftwareDeploymentTransport.ps1`
- network authority modules

Modify shared owners only when a measured gap cannot be solved in the ScanSnap orchestration layer; add shared regression coverage when doing so.

## Definition of done

Home result is best-effort runtime proof. Field delivery is the business destination.

The implementation is complete when:

1. ScanSnap package is bound to real source/hash/args/validation evidence;
2. the ScanSnap command delegates remote install lifecycle to the canonical SysAdminSuite factory;
3. home mode either reaches canonical validated completion or records the exact remaining external auth boundary without requiring target-side interaction;
4. Northwell/VPN modes use the same canonical transport;
5. `WRH250STR001` and `WRH250STR002` can be independently deployed when reachable;
6. successful execution is proven by canonical package validation + cleanup, surfaced as `INSTALLATION_DETECTED`;
7. tests are green;
8. implementation is committed/pushed/reviewed/integrated when authorized;
9. no critical fact exists only in chat.

## Proof ceiling

This plan is repository architecture + evidence-based execution routing. It does not itself prove the current ScanSnap installer, current PTop credential path, or live field installations. Those are the P82 runtime proofs Cursor must execute.
