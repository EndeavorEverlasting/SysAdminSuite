# AutoLogon field path hardening

## Problem

AutoLogon Remote produces several nested evidence trees. A checkout under a long OneDrive/backup path can therefore exceed the practical Windows PowerShell 5.1 path budget even when the top-level launcher itself is reached through a temporary drive alias. The observed failure happened before AutoLogon apply because the restart wrapper could not persist `autologon_s4u_deployment_result.json` beneath the deeply nested physical checkout path.

## Runtime contract

`Invoke-SasAutoLogonOnsite.ps1` is the field front door behind `sas autologon Remote HOST`, `S4U`, and `Recover`. When its physical repository root is longer than the bounded field threshold, it must re-enter the requested field action from an exact-HEAD detached worktree under:

```text
%LOCALAPPDATA%\SysAdminSuite\field-runtime\autologon\<12-char-head>\
```

The worktree is created only from the already-present local Git object database. No repository-network access is required. The source checkout is not reset, cleaned, switched, or overwritten.

Before re-entry the launcher must prove:

- source committed HEAD resolves;
- the short runtime worktree exists or can be added detached at that exact HEAD;
- short-runtime HEAD equals source HEAD;
- short runtime is clean;
- the canonical on-site launcher exists in the short runtime.

A dirty, malformed, or mismatched short runtime fails closed. The launcher does not destructively repair it.

The original source checkout is retained in process-scoped `SAS_REPO_ROOT`. That gives existing evidence discovery access to prior results from the original checkout and lets `SasNetworkGuard` use the source checkout's ignored `Config\sas-network-guard.local.json` fallback when the short worktree has no operator-local policy file.

Generated AutoLogon evidence remains under the executing repository's existing registered `survey\output` structure. The change is the physical runtime root, not the deployment artifact schema or terminal proof contract.

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
