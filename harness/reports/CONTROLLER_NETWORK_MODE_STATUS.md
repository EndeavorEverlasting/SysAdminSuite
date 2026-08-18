# Controller Network-Mode Status

## Working

- Repository freshness has an existing preservation-first workflow and focused validators.
- The repository already provides `scripts/Enable-SasNorthwellVpnNetworkGuard.ps1` for exact active DomainAuthenticated VPN/LAN authority without target contact or mutation.
- The protected-network gate is product-owned and runs before canonical target resolution/contact in the field deployment transaction.
- The harness treats controller repository preparation and protected-network work as serialized phases rather than one hybrid command.
- PR-backed repository certification now uses the GitHub PR head ref `refs/pull/<pr>/head` copied into a private local `refs/sas-cert/pr-<pr>` ref and verified against the expected immutable SHA.

## Repaired harness boundary

The controller has two different operational environments:

1. `OFF_NETWORK_REPOSITORY_PREP` — Git/repository proof is allowed and must be completed here.
2. `PROTECTED_NETWORK_DEPLOYMENT` — protected-network proof and target work happen here; Git must not be required.

The transition between them is explicit. Before connecting to the protected network, the controller writes `%LOCALAPPDATA%\SysAdminSuite\controller-handoff\controller-repo-certification.json` containing the exact repository, branch, commit, source checkout path, timestamp, phase, and validator proof. After the transition, that file—not a new `git rev-parse` or `git status`—is the checkout identity authority.

`no_git_after_transition` is deliberately broader than "no remote Git." It assumes the environment may block the Git executable or its operations entirely.

For PR-backed certification, the branch name is descriptive metadata only. The remote-tracking ref `refs/remotes/origin/<branch>` is mutable and can disappear or move during branch lifecycle events. The certification authority is the fetched PR head ref plus exact SHA equality.

## Repaired incident: mutable branch ref during certification

Observed failure signature:

```text
Cloning into '<temporary repo>'...
...
- [deleted] (none) -> origin/<branch>
fatal: ambiguous argument 'refs/remotes/origin/<branch>'
```

The earlier NEXT COMMAND fetched a mutable branch name directly into `refs/remotes/origin/<branch>` after cloning and then required that ref to exist. That made certification vulnerable to a branch deletion/recreation or movement race even when the pull request still had a known head SHA.

The harness now requires PR-backed certification to fetch:

```text
refs/pull/<pr>/head -> refs/sas-cert/pr-<pr>
```

and then verify that private local ref exactly equals the expected PR head SHA. If the PR head cannot be fetched or moved, classify `REMOTE_PR_HEAD_UNAVAILABLE_OR_MOVED`, remain off-network, refresh PR metadata, and restart certification. Do not fall back to a stale remote-tracking branch.

## Broken / blocked conditions

- Any command that clones/fetches off-network and then uses `git rev-parse`, `git status`, `git worktree`, `git checkout`, `gh`, or another Git-dependent check after the protected-network transition violates this harness.
- A missing or malformed serialized certification is `CERTIFICATION_ARTIFACT_INVALID`; do not improvise checkout identity after transition.
- An expected PR head ref that cannot be fetched or no longer equals the selected commit is `REMOTE_PR_HEAD_UNAVAILABLE_OR_MOVED`; do not substitute `refs/remotes/origin/<branch>`.
- An unproven VPN/protected-network posture is `NETWORK_POSTURE_UNPROVEN`; no target contact is allowed.
- Current inspected `scripts/Invoke-SasAutoLogonOnsite.ps1` prepares the short `C:\SASAL` runtime using local Git commands. If the protected environment blocks Git, this is `PRODUCT_RUNTIME_GIT_DEPENDENCY`.

## Product-lane boundary

`PRODUCT_RUNTIME_GIT_DEPENDENCY` is not repaired here because product code is outside this harness sprint. The safe harness behavior is to expose the dependency before target contact and hand it to a separately authorized product-code lane. The harness must not bypass it by reconstructing an inner deployment command.

## Missing proof

This harness does not prove:

- whether a particular VPN/firewall blocks every Git operation or only selected operations;
- live VPN authentication on a controller;
- target DNS/reachability;
- S4U task creation, registry mutation, restart, cleanup, or automatic sign-in;
- a product-side Git-independent protected-network entrypoint.

Those require their owning runtime/product lanes.

## Operator next gate

While still off the protected network, resolve the current PR head SHA, fetch `refs/pull/<pr>/head` into `refs/sas-cert/pr-<pr>`, verify exact SHA equality, run the owning validators, and create/inspect the serialized controller certification artifact. Only after that artifact is complete should the controller transition to the protected network. If the selected product entrypoint still requires Git there, stop with `PRODUCT_RUNTIME_GIT_DEPENDENCY` before target contact.
