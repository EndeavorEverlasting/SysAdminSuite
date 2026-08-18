# Controller Network-Mode Serialization Skill

Use this skill when repository/Git work must happen off the protected network and deployment requires a VPN or other protected network that can block Git. Typical signals include:

- "Git works off network but not on VPN."
- "Connect to the VPN and then deploy."
- "Could not read the local certified checkout HEAD" after a network transition.
- A proposed field command mixes clone/fetch/rev-parse/worktree operations with protected-network target work.

## Required inputs

- repository root and repository identity
- selected branch and exact selected commit
- owning validators for the planned field operation
- intended protected-network operation
- current dirty/concurrent-work constraints

Do not require a live hostname in tracked documentation or harness artifacts.

## Procedure

1. **OFF_NETWORK_REPOSITORY_PREP**
   - Read `AGENTS.md`, `CODEBASE_MAP.md`, and `harness/maps/controller-network-mode-map.md`.
   - Resolve dirty state, worktrees, branch/PR state, and repository freshness while Git is available.
   - Fetch without force when remote proof is required.
   - Preserve unrelated work with an isolated worktree.
   - Run `python harness/validators/validate-controller-network-mode.py` and the owning field/regression validators.
   - Serialize the exact repository, branch, commit, source checkout path, UTC timestamp, phase, and validator results to `%LOCALAPPDATA%\SysAdminSuite\controller-handoff\controller-repo-certification.json`.
   - Do not contact or mutate a deployment target.

2. **TRANSITION_TO_PROTECTED_NETWORK**
   - Stop all Git and GitHub CLI commands.
   - Connect the approved VPN/protected network.
   - Treat `no_git_after_transition` as a hard invariant. This includes local `git rev-parse`, `git status`, `git worktree`, and `git checkout`, not only remote fetch/pull.

3. **PROTECTED_NETWORK_DEPLOYMENT**
   - Read the certification JSON through ordinary filesystem APIs. Do not ask Git to re-prove the checkout.
   - Bootstrap exact VPN authority with `scripts/Enable-SasNorthwellVpnNetworkGuard.ps1 -ConfirmVpnPosture` when needed.
   - Run the fail-closed `scripts/Confirm-SasNorthwellNetwork.ps1 -NonInteractive -NoOpenWifiSettings` gate.
   - Continue only if the canonical product entrypoint is already proven not to require Git in this phase.
   - If it still invokes Git, classify `PRODUCT_RUNTIME_GIT_DEPENDENCY`, stop before target contact, and hand off to a separately authorized product-code lane.

## Known traps

- Fetching before VPN and then running `git rev-parse` after VPN is still a phase violation.
- A temporary clone path is not proof after transition unless its exact identity was serialized before transition.
- Do not weaken the network gate to keep Git working.
- Do not reconstruct an alternate deployment path from inner scripts to bypass a product runtime Git dependency.
- A harness validator passing does not prove live VPN, target reachability, target mutation, restart, or AutoLogon.

## Expected outputs

Tracked:

- `harness/maps/controller-network-mode-map.md`
- `harness/workflows/controller-network-mode-serialization.yaml`
- `harness/api/controller-network-mode-artifact-registry.json`
- `schemas/harness/controller-network-mode-artifact-registry.schema.json`
- `harness/reports/CONTROLLER_NETWORK_MODE_STATUS.md`

Runtime/local only:

- `%LOCALAPPDATA%\SysAdminSuite\controller-handoff\controller-repo-certification.json`
- protected-network evidence emitted by the registered network gate

## Validation

```text
python harness/validators/validate-controller-network-mode.py
python Tests/survey/test_controller_network_mode_harness_completeness.py
python harness/validators/validate-prestage-bootstrap-safety.py
python harness/validators/validate-repository-freshness-contracts.py
git diff --check
```

## Handoff

Report the exact certified commit, source checkout path, last completed phase, network evidence path if any, current failure classification, and proof ceiling. If `PRODUCT_RUNTIME_GIT_DEPENDENCY` is present, the next owner is the product-code lane; the harness lane must not patch product code.
