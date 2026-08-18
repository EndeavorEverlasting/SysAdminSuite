# Controller Network-Mode Map

## Purpose

This map covers the controller-side boundary between repository preparation and protected-network field work. It supplements `CODEBASE_MAP.md`; it does not replace repository governance or product deployment contracts.

The operational constraint is serialized, not hybrid:

1. `OFF_NETWORK_REPOSITORY_PREP`
2. `TRANSITION_TO_PROTECTED_NETWORK`
3. `PROTECTED_NETWORK_DEPLOYMENT`

A controller must finish every Git-dependent repository proof before entering the protected-network phase. After the transition, the harness assumes **all Git commands may be unavailable**, including local commands such as `git rev-parse`, `git status`, `git worktree`, and `git checkout`. The protected phase consumes the serialized handoff artifact created in phase 1 instead of asking Git to prove the checkout again.

## Repository orientation

| Surface | Purpose in this lane |
| --- | --- |
| `AGENTS.md` | Read-only governance authority. Harness work must not edit it. |
| `CODEBASE_MAP.md` | General repository map and canonical command orientation. |
| `harness/workflows/` | Task intake, freshness, pre-stage safety, and this controller-mode workflow. |
| `harness/api/` | Artifact registries and machine-readable harness contracts. |
| `harness/validators/` | Offline harness validators. |
| `harness/skills/` | Repeatable agent/operator procedures. |
| `harness/reports/` | Human-readable state and proof ceilings. |
| `.githooks/` | Commit/push admission checks; these run only while Git is available. |
| `.github/workflows/` | CI proof for harness contracts; never field deployment. |
| `Tests/survey/` | Offline completeness and contract tests. |
| `scripts/` | Product/runtime surfaces. Read-only in this harness lane. |

## Read-only product dependencies

- `scripts/Enable-SasNorthwellVpnNetworkGuard.ps1` — bootstraps exact active DomainAuthenticated VPN/LAN addresses into operator-local network authority. No target contact or mutation.
- `scripts/Confirm-SasNorthwellNetwork.ps1` — fail-closed protected-network proof.
- `scripts/Invoke-SasAutoLogonFieldDeployment.ps1` — product field transaction; network gate precedes target resolution/contact.
- `scripts/Invoke-SasAutoLogonOnsite.ps1` — canonical on-site product launcher. **Known current product gap:** its short-runtime preparation calls Git locally (`rev-parse`, `worktree`, `status`, `checkout`).
- `Run-AutoLogonCrashSafe.cmd` — registered crash-safe field front door.

Harness code may inspect these surfaces as dependencies. It must not patch them in a harness-only sprint.

## Phase contract

### 1. OFF_NETWORK_REPOSITORY_PREP

Allowed and expected:

- `git clone`, `git fetch --no-force`, `git rev-parse`, `git status`, `git worktree`, local validators, and PR checks.
- Select and verify the exact repository branch/commit.
- Run the owning harness/product regression validators required before field work.
- Write `%LOCALAPPDATA%\SysAdminSuite\controller-handoff\controller-repo-certification.json`.
- Record the exact source checkout path and commit identity in that runtime artifact.

Forbidden:

- Target contact or mutation.
- Treating a fetch as execution-tree convergence.
- Connecting the protected-network phase before the certification artifact is complete.

### 2. TRANSITION_TO_PROTECTED_NETWORK

Actions:

- Stop Git and GitHub CLI activity.
- Preserve the certified checkout exactly as serialized.
- Connect the approved VPN/protected network.
- Do not use Git to re-prove the checkout after the transition.

Invariant: `no_git_after_transition`.

### 3. PROTECTED_NETWORK_DEPLOYMENT

Allowed:

- Read the certification JSON with ordinary filesystem/PowerShell APIs.
- Verify its schema/version, expected repository, expected commit, and source path without invoking Git.
- Bootstrap VPN authority with `Enable-SasNorthwellVpnNetworkGuard.ps1 -ConfirmVpnPosture`.
- Run `Confirm-SasNorthwellNetwork.ps1 -NonInteractive -NoOpenWifiSettings`.
- Continue only through a canonical product entrypoint whose protected-network execution no longer requires Git.

Forbidden:

- `git`, `gh`, clone, fetch, pull, rev-parse, status, worktree, checkout, or branch manipulation.
- Reconstructing an alternate product deployment path just to avoid a product dependency.
- Target contact before protected-network proof.

## Known trap and current blocker

A command can be repository-correct and still be operationally invalid if it mixes phases. A command that clones off-network, asks the operator to connect VPN, then runs `git rev-parse` or creates a Git worktree is a harness failure even when each individual command is otherwise valid.

At the current inspected product surface, `scripts/Invoke-SasAutoLogonOnsite.ps1` still uses local Git to prepare `C:\SASAL`. If the protected environment blocks Git execution, classify the gate as `PRODUCT_RUNTIME_GIT_DEPENDENCY`. Stop before target contact and hand the issue to a separate product-code lane. Do not weaken the network gate and do not invent an alternate field launcher inside this harness lane.

## Build / test / deploy orientation

Harness proof while Git is available:

```text
python harness/validators/validate-controller-network-mode.py
python Tests/survey/test_controller_network_mode_harness_completeness.py
python harness/validators/validate-prestage-bootstrap-safety.py
python harness/validators/validate-repository-freshness-contracts.py
git diff --check
```

Field preparation is governed by `harness/workflows/controller-network-mode-serialization.yaml`. Actual deployment remains product-owned and is not authorized by this map.
