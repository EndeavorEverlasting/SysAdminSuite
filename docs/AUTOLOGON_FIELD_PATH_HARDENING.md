# AutoLogon field path hardening

## Problem

AutoLogon Remote produces several nested evidence trees. A checkout under a long OneDrive/backup path can therefore exceed the practical Windows PowerShell 5.1 path budget even when the top-level launcher itself is reachable. The observed failure happened before AutoLogon apply because the restart wrapper could not persist `autologon_s4u_deployment_result.json` beneath the deeply nested physical checkout path.

The prior portable trampoline used a checkout-root length threshold. That was insufficient: a repository root can be shorter than the threshold while the generated AutoLogon child path still exceeds the Windows path budget.

## Runtime contract

`Invoke-SasAutoLogonOnsite.ps1` is the field front door behind `sas autologon Remote HOST`, `S4U`, and `Recover`. Every target-facing AutoLogon action re-enters the request from one stable short worktree:

```text
C:\SASAL\
```

Live field evidence is written beneath the repository's already-ignored short run root:

```text
C:\SASAL\runs\
```

This retains the existing `<repo>\runs` evidence-discovery contract while removing OneDrive/backup checkout length from the nested S4U path budget.

The short worktree is created only from the already-present local Git object database. No repository-network access is required. Before re-entry the launcher must prove:

- source committed HEAD resolves;
- `C:\SASAL` is absent or is an owned worktree of the same Git common directory;
- the runtime worktree is clean;
- the runtime can move to the exact source HEAD without touching the source checkout;
- runtime HEAD equals source HEAD;
- the canonical on-site launcher exists in the runtime worktree.

A dirty, unrelated, malformed, or non-owned `C:\SASAL` fails closed. The launcher does not delete, reset, or clean an unexpected path.

The source checkout is retained in process-scoped `SAS_REPO_ROOT`. Existing evidence discovery can therefore consider both the stable short runtime and the original checkout, while `SasNetworkGuard` can use the source checkout's ignored `Config\sas-network-guard.local.json` fallback when `C:\SASAL` has no operator-local policy file.

The `runs/` root is already gitignored. Generated live evidence stays untracked. Artifact schemas, result filenames, target policy, S4U behavior, restart semantics, and terminal proof classification are unchanged.

## Network authority

The outer `Invoke-SasAutoLogonFieldDeployment.ps1` transaction is the sole protected-network admission gate. It calls `Confirm-SasNorthwellNetwork.ps1`, which evaluates the shared `SasNetworkGuard` policy. The on-site launcher must not add a second DomainAuthenticated-only precheck that can contradict the canonical guard.

The VPN/network bootstrap helper remains available to create an exact `/32` operator-local allowlist when a qualifying DomainAuthenticated non-Wi-Fi interface is actually present. Its absence or failure does not override the canonical guard and never grants target authority by itself.

## Proof boundary

Short-runtime preparation and network admission are preconditions only. Deployment completion still requires the canonical outer result:

```text
status = COMPLETED
classification = AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

with AutoLogon applied, clean pre-reboot readiness, observed offline/online restart cycle, restart-task cleanup, and target mutation truthfully recorded. Automatic interactive sign-in remains a separate higher proof ceiling.
