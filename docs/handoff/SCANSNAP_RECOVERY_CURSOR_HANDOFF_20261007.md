# ScanSnap recovery handoff — 2026-10-07

## Execution frame

- **Repo:** `EndeavorEverlasting/SysAdminSuite`
- **PR:** #514
- **Branch:** `feat/scansnap-unattended-multimodal-deploy-20261006`
- **Recovered Cursor floor:** `8e658c7d48a702dcd6fafba9a1639e4f2a584c49`
- **Remote hardening floor added after crash:** `5f149a4ef7dfa4b83df3f022e864b6e0313d801f`
- **Related architecture source:** PR #512 / `docs/scansnap-factory-plan-20261006` (stale/diverged; do not merge wholesale)
- **Admin Box 1:** `LPW003ASI173`
- **Field targets:** `WRH250STR001`, `WRH250STR002`
- **Lab target:** `CheexMcClappeth`
- **Lane:** ScanSnap Home package qualification -> sealed/offline protected runtime -> deterministic remote deployment
- **Forbidden:** ad-hoc operator PowerShell as the production interface; public-Internet/agent dependency after protected-network switch; guessed target identity; secrets/password parameters; live target mutation before required dry-run/live-cert gates; claiming deployment without evidence.

## Mission

Finish the ScanSnap deployment surface so the operator can switch Admin Box 1 onto Northwell protected LAN/WAB or authenticated VPN and complete the entire transaction without Cursor, public Internet, Git, or a chat response.

Judgment is already bounded. Do legwork, validation, integration, and evidence production. Do not redesign the architecture.

## What the overnight Cursor sprint proved

PR #514 established:

- qualified ScanSnap Home 4.1.0 package identity;
- SHA-256 binding;
- vendor InstallShield response-file silent route;
- measured local install on Admin Box;
- PID-delta installer discovery;
- Northwell route classification;
- Pester coverage;
- local silent-install success evidence.

The original PR head `8e658c7d...` had green Pester but review exposed first-shot blockers.

## Remote hardening already committed after recovery

Do **not** redo these unless refreshed truth proves regression.

### Package truth and privacy

- `package.manifest.json` now detects the measured executable:
  `C:\Program Files (x86)\PFU\ScanSnap\Home\PfuSshMain.exe`
- tracked `BoundBy` is non-identifying.
- generic directory-only success detection is no longer the canonical package gate.

### Static installer route

- `installer-process-route.v1.json` no longer contains live controller/PID/timestamp observations.
- generic path fragment `ScanSnap` was removed so the installed application cannot masquerade as the installer.
- runtime detection candidates are executable-only.

### PID resolver

- candidate logic requires an installer process-name hit or a strong path + exact setup-title hit;
- `AttachPid` no longer wraps the selected row in an array;
- `LaunchAndResolve` fails if the expected setup surface never becomes ready;
- live observation writes go to ignored `evidence/installer-route-observed.json`, not the tracked route manifest.

### Remote deployment runner

- denied Northwell authority cannot authorize live `LAB_LOCAL` mutation;
- lab-local remains a WhatIf-only diagnostic when authority is denied;
- required InstallShield `.iss` participates in binding and is rechecked before staging;
- remote EXE runs with the staged installer directory as `WorkingDirectory`, so relative `-f1".\*.iss"` resolves correctly;
- runner records `InstallerSucceeded`; install success requires both acceptable installer exit and executable detection.

### Interactive setup-driver fallback

- keys are never sent when exact-window focus fails;
- the Install key has its own focus gate;
- pre-existing detection is recorded and cannot prove this run succeeded;
- post-install setup dismissal no longer independently marks install success.

### Silent-install qualification helper

- global named mutex enforces single launch;
- pre-existing executable detection returns idempotent `ALREADY_INSTALLED` without launching;
- evidence is constrained to the ignored ScanSnap evidence root;
- PID delta is preserved but process-tree completion is awaited;
- acceptable launcher exit + executable detection are both required for success;
- timeouts/nonzero/unproven-exit cases fail closed.

### Regression tests

`Tests/Pester/ScanSnapDeploy.Tests.ps1` now locks the above first-shot invariants.

## Current architectural gap — must finish

PR #512 correctly froze the production architecture:

```
ScanSnap package orchestrator
  -> scripts/SasSoftwareDeploymentAdapter.psm1
  -> Invoke-SasSmbScheduledTaskDeployment
  -> shared finalization/evidence/cleanup
```

PR #514 still contains a ScanSnap-specific SMB/Task Scheduler implementation in `Deploy-ScanSnap.ps1`.

**Do not ship two deployment factories.**

Refactor the production path to delegate staging / source-target hash proof / SYSTEM task lifecycle / result retrieval / cleanup / finalization to `Invoke-SasSmbScheduledTaskDeployment`.

ScanSnap should own only:

1. package acquisition/binding;
2. ScanSnap-specific silent arguments and required response sibling;
3. target/mode classification above the shared transport;
4. ScanSnap detection/result interpretation;
5. the technician-facing launcher and ScanSnap evidence summary.

Do not add password parameters to the canonical adapter. Do not fork a VPN-specific installer engine.

## Protected/offline execution contract to port from PR #512

PR #512 is currently stale/diverged. **Do not merge or rebase it wholesale into this execution lane.**

Refresh main, inspect whether these artifacts already landed elsewhere, then selectively port/reconcile only missing current versions:

- `harness/contracts/protected-network-offline-execution.v1.json`
- `harness/validators/validate-protected-network-offline-execution.py`
- `docs/GUEST_SYNC_TO_PROTECTED_DEPLOYMENT.md`
- relevant minimal registrations in:
  - `.github/workflows/harness-contracts.yml`
  - `harness/workflows/fresh-agent-intake.yaml`
  - `tools/validate-ai-layer.ps1`
  - `Tests/survey/test_agent_governance_doctrine_contracts.py`
  - `AGENTS.md`
  - `CODEBASE_MAP.md`

Preserve current main governance if those files evolved after PR #512. Port semantics, not stale file bodies.

## Required operator front door

Repository doctrine requires the technician/operator path to be a tracked CMD launcher.

Strengthen the existing ScanSnap CMD front door so it:

1. works from any working directory and Windows username;
2. proves prepared/sealed runtime state before protected mutation;
3. chooses/accepts approved target(s);
4. performs route classification;
5. runs no-mutation dry-run/live-cert first;
6. stops on ambiguous/denied authority;
7. invokes the shared deployment adapter;
8. validates the installed executable;
9. performs cleanup/finalization;
10. writes a concise local ignored evidence summary;
11. returns one deterministic final class and useful next action;
12. requires no Cursor/chat/Git/public Internet once the network switch occurs.

## Local validation / review loop

Start by refreshing provider and local truth. Preserve unrelated local work.

Run at minimum:

```powershell
Invoke-Pester -Path Tests/Pester/ScanSnapDeploy.Tests.ps1
```

Then run the repository-selected scoped validation and any PowerShell parse/PSScriptAnalyzer gates required by current governance.

Fetch **all current PR #514 review threads after the latest head**. Treat old comments as historical if the diff is already corrected; fix every still-valid P1/Major blocker. Do not merely resolve threads without code/evidence.

If validation fails, diagnose, patch within this lane, rerun the failed gate, then rerun the bounded integration suite.

## First-shot live-cert gates

### Before switching networks

Prove locally that the protected transaction is sealed:

- installer EXE present;
- matching ISS present;
- manifest SHA matches payload;
- required scripts/modules/launcher present;
- prepared commit recorded;
- tracked-file seal recorded;
- no runtime step requires Git/public web/agent;
- failure continuation is local/deterministic.

Do not enter Northwell protected execution until these are true.

### On Northwell protected LAN/WAB or authenticated VPN

Run WhatIf/dry-run independently for:

- `WRH250STR001`
- `WRH250STR002`

Required proof per target:

- one exact resolved corporate identity/FQDN;
- route authority allowed;
- admin-share/readiness classification;
- package binding remains valid;
- no target mutation during WhatIf;
- shared adapter says the target is ready for the bounded deployment lifecycle.

### Production

Only after the gates above:

1. deploy to one target;
2. require shared adapter completion + cleanup;
3. require `PfuSshMain.exe` detection and acceptable installer exit;
4. preserve local evidence;
5. classify the first target independently;
6. only then proceed to the second target.

A failure on target 1 must not erase or repeat proven work for target 2, and vice versa.

## Acceptance gates

The sprint is not complete until all are true:

- PR #514 current head is based on refreshed current main or otherwise proven non-stale;
- package/route/privacy regressions remain fixed;
- current review blockers are cleared by code, not thread cosmetics;
- targeted Pester passes;
- required repo CI is green on the exact final head;
- production ScanSnap transport delegates to `SasSoftwareDeploymentAdapter.psm1`;
- protected/offline contract is integrated on current code, not left only in stale PR #512;
- one tracked CMD front door owns the complete protected transaction;
- sealed/offline runtime proof says no public Internet/agent/Git dependency after switch;
- field WhatIf evidence exists for each reachable target before live mutation;
- deployment evidence distinguishes designed / locally validated / integration validated / deployed / production verified;
- merge occurs only when the exact validated head is green, mergeable, dependency-satisfied, and unblocked.

## Proof ceiling at handoff

Remote repository hardening and CI/review evidence only.

No claim here that:

- Admin Box local working tree contains the latest branch;
- the sealed protected runtime has been rebuilt;
- WRH250STR001/002 were reachable;
- field WhatIf ran;
- ScanSnap was deployed to either field target;
- PR #514 was merged.

## Final report required from Cursor

Return:

- completed work;
- created/modified files;
- exact validation commands and pass/fail counts;
- skipped checks and why;
- unresolved gaps/risks;
- evidence/log/report paths;
- final branch / PR / commit / git status;
- exact CI/review state;
- merge/default-branch state;
- sealed/offline runtime state;
- per-target WhatIf/deployment state;
- one exact next command or operator action if anything remains.
