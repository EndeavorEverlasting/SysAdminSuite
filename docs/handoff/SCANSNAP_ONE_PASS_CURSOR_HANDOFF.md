# Cursor / Kirsten handoff — ScanSnap one-pass execution

## Mission

Execute ScanSnap deployment by converging the ScanSnap package onto SysAdminSuite's proven software-deployment factory. Do not invent another transport. Do not return to planning after each runtime failure. Treat each failure as a typed continuation branch, preserve completed proof, repair the failed stage, and continue every independent lane.

Start from current provider truth. The plan owner is:

`docs/SCANSNAP_PROVEN_DEPLOYMENT_FACTORY_PLAN.md`

Read it completely before mutation.

## Fixed topology

- Admin Box 1 / controller: `LPW003ASI173`
- Home prototype target: `CheexMcClappeth`
- Field targets: `WRH250STR001`, `WRH250STR002`
- Retired target: `LPW003ASI105` — never reintroduce.

The deployment is remote and unattended. Nobody needs to find, log into, click on, or stand in front of the target workstation.

## Canonical repository floor

At handoff creation the base floor was:

`main@9a0d2756f77d0b41582c70bc6fa68ac1fd3829af`

Refresh before acting. Do not infer current truth from this SHA if main has advanced.

Prior integrated ScanSnap work:

- PR #507 / `2610c4f4` — initial ScanSnap package
- PR #510 / `1b2b86bd` — precise access classification
- PR #511 / `9a0d2756...` — multimodal + unattended deployment context

## P00 / P01 / P04 / P82 invocation

P00, P01, P04 and P82 are not decorative references; apply their execution contracts.

P00:

- canonical name: `Governance Doctrine Installer`
- canonical repo: `EndeavorEverlasting/TokenCorridor`
- registry: `src/tokencorridor/interface/promptkit/registry/base/prompts.json`
- source blob: `848728632c1243ebba023fa0012292a2ad33cada`

P01:

- canonical name: `Harness Infrastructure Builder`
- canonical repo: `EndeavorEverlasting/TokenCorridor`
- registry: `src/tokencorridor/interface/promptkit/registry/base/prompts.json`
- source blob: `848728632c1243ebba023fa0012292a2ad33cada`

P04:

- canonical repo: `EndeavorEverlasting/TokenCorridor`
- registry: `src/tokencorridor/interface/promptkit/registry/base/prompts.json`
- source blob: `848728632c1243ebba023fa0012292a2ad33cada`

P82:

- canonical repo: `EndeavorEverlasting/TokenCorridor`
- registry: `src/tokencorridor/interface/promptkit/registry/prompts/spec-architecture-prompts.v1.json`
- source blob: `5926a198a14567de55110ed19e922fc444b4dec7`

Use P00 to enforce the offline protected-network governance invariant. Use P01 to make that invariant executable through the harness and sealed runtime. Use P04 for ownership/factoring/parallel work. Use P82 only on real empirical unknowns.

## Read first

Read current versions of:

- `docs/SCANSNAP_PROVEN_DEPLOYMENT_FACTORY_PLAN.md`
- `docs/SCANSNAP_MULTIMODAL_DEPLOYMENT.md`
- `docs/SCANSNAP_LIVECERT_STATUS.md`
- `Config/SoftwareDeploy/ScanSnap/Runbook-ScanSnap.md`
- `Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.cmd`
- `Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap.ps1`
- `Config/SoftwareDeploy/ScanSnap/Bind-ScanSnapPackage.ps1`
- `Config/SoftwareDeploy/ScanSnap/package.manifest.json`
- `Config/SoftwareDeploy/ScanSnap/hosts_smoke.txt`
- `Config/SoftwareDeploy/ScanSnap/hosts_field.txt`
- `scripts/SasSoftwareDeploymentAdapter.psm1`
- `scripts/SasSoftwareInstallFinalization.psm1`
- `scripts/Test-SasSoftwareDeploymentTransport.ps1`
- `docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`
- `docs/handoff/deployment-transport-convergence.md`
- `docs/SOFTWARE_DEPLOYMENT_LOW_NOISE.md`
- `scripts/SasNorthwellNetworkAuthority.psm1`
- `scripts/SasNetworkGuard.psm1`
- `EnvSetup/Deploy-Shortcuts.ps1`
- `harness/contracts/protected-network-offline-execution.v1.json`
- `docs/GUEST_SYNC_TO_PROTECTED_DEPLOYMENT.md`

## Protected execution is agent-independent

The Northwell protected network cannot be assumed to provide public Internet access. Cursor itself may become unavailable when the Admin Box moves onto Northwell.

Therefore the deployment must be split into two hard runtime phases.

### Phase A — Internet preparation

While Cursor and Internet access are still available, do all agent-dependent work:

- refresh provider/repository truth;
- implement and integrate the ScanSnap factory convergence;
- acquire the exact web-sourced installer;
- establish package provenance, SHA256, silent arguments, and validation;
- bind the package;
- stage every required payload locally;
- prepare the protected operator front door;
- encode local failure classification and continuation;
- stage and seal the exact protected runtime.

### Phase B — protected execution

The offline/sealed deployment transaction begins after the switch to Northwell or protected VPN.

From this point forward:

- protected execution is agent-independent;
- there is no public Internet dependency;
- no Git fetch/pull/clone is allowed or required;
- no vendor web lookup is allowed or required;
- no future Cursor/ChatGPT response may be required to choose the next executable stage;
- all deployment code and the installer payload must already exist locally;
- the tracked CMD/runtime owns target resolution, readiness, staging, SYSTEM execution, validation, cleanup, evidence, and same-transaction failure continuation.

Machine-readable authority:

`harness/contracts/protected-network-offline-execution.v1.json`

Do not switch onto protected Northwell until the sealed runtime can finish or locally classify/recover the entire intended ScanSnap transaction without the agent.

## The core decision is already made

The ScanSnap implementation currently duplicates remote staging/task execution.

Converge it onto:

`Invoke-SasSmbScheduledTaskDeployment`

from:

`scripts/SasSoftwareDeploymentAdapter.psm1`

Do not redesign that lifecycle.

The canonical adapter already accepts a **local installer path**, so the fact that ScanSnap comes from the web instead of the Northwell software share is not a transport blocker.

The ScanSnap layer owns:

- web/package acquisition;
- source provenance;
- hash;
- silent args;
- validation/detection mapping;
- multimodal target resolution;
- ScanSnap operator UX.

The canonical adapter owns:

- C$/ADMIN$ checks;
- run-scoped staging;
- installer + worker hash verification;
- SYSTEM scheduled task;
- result retrieval;
- package validation;
- payload cleanup;
- task cleanup;
- run-root cleanup;
- final transport classification.

## Do this in execution waves

The key ordering constraint is: **finish all Internet/agent preparation before the protected network switch.** Cursor does not travel into the protected phase as an execution dependency.


### Wave 0 — recover current truth

1. `git fetch`
2. inspect current branch/status/worktrees
3. inspect open ScanSnap-related PRs
4. protect unrelated operator changes
5. branch from current `origin/main`
6. record controller hostname; expected `LPW003ASI173`

Do not reset or clean unrelated work.

### Wave 1A — package qualification

This lane can run independently.

The previous installer drop was empty. The operator has clarified that ScanSnap is web-sourced.

Do the legwork:

1. recover any exact product identity already present in repository/client evidence;
2. if needed, use authoritative Ricoh/PFU/Fujitsu source evidence;
3. determine the exact requested ScanSnap product, not a guessed family;
4. download the installer locally;
5. capture version/signer/provenance where available;
6. compute SHA256;
7. determine real silent args from vendor/package evidence;
8. determine a deterministic validation check;
9. bind with `Bind-ScanSnapPackage.ps1`;
10. read the manifest back and prove `Bound=true`.

Do not stop merely because no installer was pre-dropped.

### Wave 1B — factory convergence

Refactor `Deploy-ScanSnap.ps1` so the production path imports and delegates to `SasSoftwareDeploymentAdapter.psm1`.

Map the bound ScanSnap detection into canonical validation checks:

- file detection -> `FileExists`, `FileVersionEquals`, or `FileSha256Equals` as evidence supports;
- registry detection -> `RegistryValueEquals` or `UninstallEntry` as evidence supports;
- service detection -> `ServiceExists` if that is the real package evidence.

Do not create arbitrary validation scriptblocks when the canonical validation vocabulary already fits.

The adapter's returned completed+validated state is stronger than the existing ScanSnap `INSTALLATION_DETECTED` state. Preserve both: retain canonical result evidence and project successful canonical completion to the ScanSnap operator-facing final class.

### Wave 1C — prepare and seal the protected transaction

Before any Northwell/VPN switch:

1. ensure the exact implementation candidate is integrated or otherwise selected as the immutable deployment floor;
2. refresh/stage through the existing Guest/Internet workflow;
3. ensure `C:\SASAL` contains the ScanSnap front door and every required tracked dependency;
4. ensure the real installer payload is locally available to the protected runtime;
5. preserve its SHA256, silent args, and validation rules locally;
6. prove runtime remotes are removed;
7. prove the tracked-file seal;
8. prove no protected code path needs public web/Git/agent access;
9. prove failures create local evidence and have a local continuation/recovery path;
10. only then switch networks.

### Wave 2 — home deployment

This is a real deployment attempt, not another architecture exercise.

Controller:

`LPW003ASI173`

Target:

`CheexMcClappeth`

Previous evidence:

- PTop responded;
- no Northwell DC existed on the home LAN;
- short-name C$ -> `AUTH_DC_UNAVAILABLE`;
- direct-IP C$ -> `LOGON_FAILURE`.

Do not repeat the same domain-token experiment.

#### Identity

First attempt to resolve:

`CheexMcClappeth.local`

and prove that it maps to the intended PTop.

The canonical SMB adapter requires an exact FQDN. If the `.local` identity works, use the factory unchanged.

If `.local` fails but the short name/current IP still conclusively identifies PTop, do not declare deployment impossible. That is the P82 trigger to create the smallest LAB_LOCAL identity seam above the canonical transport, while leaving protected production FQDN rules unchanged.

#### Authentication

Try the actual unattended remote-auth path.

Inspect existing repository patterns such as `EnvSetup/Deploy-Shortcuts.ps1` for transient `net use` / local account handling.

Do not add password fields to `SasSoftwareDeploymentAdapter.psm1`; its no-secret parameter surface is an established production contract.

If the home environment needs a credential-aware Task Scheduler shim, build the smallest LAB_LOCAL authentication wrapper that:

- receives credentials only transiently from the controller;
- stores no secret in Git/logs/manifests;
- requires no target-side interaction;
- reuses the canonical staging root, worker generator, validation, result retrieval, and teardown concepts;
- cannot become the protected Northwell credential path.

Use the result to deploy ScanSnap on PTop in this sprint.

### Wave 3 — field modes

Home success is not required before field execution.

**Cursor/agent execution stops being a dependency before this wave begins.** The local sealed runtime carries the operation.

When protected Northwell or VPN authority becomes available, use:

- `WRH250STR001`
- `WRH250STR002`

Resolve exact corporate FQDNs through the existing network/domain authority.

Use the canonical low-noise `kerberos_smb_task` readiness model and canonical SMB/SYSTEM deployment adapter.

Do not fork a VPN installer engine. VPN is only another protected route.

## Failure continuation rules

Never finish a run with only "blocked because X" when the repository/runtime contains a next action.

### If the package is missing

Acquire it, qualify it, bind it, continue.

### If target resolution fails

Try the mode-correct exact logical forms and fix the resolver. Do not broadly scan.

### If LAB_LOCAL gets `AUTH_DC_UNAVAILABLE`

Switch to the local-auth branch. The lack of a Northwell DC is already known.

### If LAB_LOCAL gets `LOGON_FAILURE`

Change authentication context. Do not rediscover the machine.

### If admin shares work but Task Scheduler fails

Run/read the exact scheduler readiness dependencies and repair that stage. Keep the package/staging proof.

### If task creation succeeds but task run fails

Repair/retry task execution only.

### If installer fails

Retrieve the closed result and use the vendor exit evidence to refine silent args/package invocation.

### If installer succeeded but validation failed

Inspect actual installed state before reinstalling. If the package is present and the validation rule is wrong, fix the validation contract and revalidate.

### If teardown fails

Repair teardown only. Do not reinstall software that already validated.

### If one target fails

Continue the other target.

### If home remains impossible because of an external credential boundary

Persist the exact receipt and continue on Northwell/VPN as soon as that route exists.

A typed failure changes the next action. It does not end the sprint.

## P82 receipt for each meaningful unknown

Record:

- HYPOTHESIS
- BUILD/PROBE
- MEASURE
- CRITIQUE
- DECISION = KEEP / REFINE / DISCARD
- next executable action

If decision is REFINE and the next action is executable, execute it immediately.

## Tests

After code convergence, run at least:

```text
Tests/Pester/ScanSnapDeploy.Tests.ps1
Tests/Pester/SmbScheduledTaskDeployment.Tests.ps1
Tests/survey/test_canonical_smb_task_deployment_contracts.py
harness/validators/validate-protected-network-offline-execution.py
```

If network-authority owners change, run their relevant contracts too.

Add regression tests proving:

1. ScanSnap passes a local bound installer into the canonical adapter;
2. SHA256 is preserved exactly;
3. canonical validation checks are generated from the ScanSnap manifest;
4. protected mode passes exact FQDN;
5. LAB_LOCAL adaptation cannot relax protected FQDN behavior;
6. WhatIf remains non-mutating;
7. final ScanSnap success requires canonical completed+validated evidence;
8. the canonical path does not execute the old duplicated staging/task engine.

## Integration

Once the converged path passes tests:

1. commit;
2. push;
3. open a bounded PR;
4. inspect CI/reviews;
5. repair failures rather than leaving them for the operator;
6. merge when green and authorized;
7. refresh main;
8. continue runtime deployment from the integrated exact candidate when the runtime requires integration first.

Do not claim merge/deployment state without provider/runtime proof.

## Final success

For PTop, strongest desired proof:

`DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED`

projected to:

`FinalClass=INSTALLATION_DETECTED`

For field hosts, report each independently.

Do not call ping/C$/task-start/exit-code alone successful deployment.

## Required final report

### COMPLETED
Exact execution/mutations.

### FACTORY CONVERGENCE
Which old ScanSnap responsibilities were removed/delegated and which canonical owners now execute them.

### PACKAGE
Product/version/source/path/SHA/silent args/validation/Bound.

### PTOP
Requested identity/resolved identity/auth path/adapter result/final class/evidence.

### WRH250STR001
Network mode/FQDN/readiness/adapter result/final class/evidence.

### WRH250STR002
Same fields.

### P82 LEDGER
Every meaningful hypothesis/result/decision.

### TESTS
Exact commands/results.

### GIT/PROVIDER
Branch/HEAD/PR/checks/merge/main.

### OFFLINE PROTECTED-RUNTIME STATE

Report:

```text
sealed runtime prepared: YES/NO
prepared commit:
tracked-file seal verified: YES/NO
installer payload local: YES/NO
public Internet required after switch: YES/NO
agent required after switch: YES/NO
offline failure continuation proven: YES/NO
```

For an acceptable protected deployment surface, the final two dependency answers must be NO and offline failure continuation must be YES.

### UNRESOLVED EXTERNAL BOUNDARIES
Only things the runtime truly cannot supply.

### NEXT ACTION
Only the smallest remaining external action, if one exists.

## Execution directive

This handoff is already the plan. Do not answer it with another plan.

Recover current truth, implement the factory convergence, qualify the package, and deploy it.

Do the legwork.
