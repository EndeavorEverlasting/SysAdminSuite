# SysAdminSuite Operator Command Handoff

## Why this exists

A SysAdminSuite field command is not ready merely because the product syntax is correct. The operator may be standing in the wrong directory, the canonical checkout may be stale, and the currently connected network may be wrong for either repository synchronization or protected target work.

The repository therefore treats an operator handoff as one transaction:

**canonical path -> repository freshness -> starting network / required intent -> canonical command -> required network restoration**

The authoritative agent procedure is `harness/skills/operator-command-handoff/SKILL.md`. This page is the concise human-facing statement of the same rule.

## The three recurrence guards

### 1. Start from the canonical path

Do not assume the shell opened in SysAdminSuite. Resolve the machine/profile-owned path first through `harness/skills/canonical-path-resolution/SKILL.md` and `harness/api/canonical-path-registry.json`.

For Windows development profiles, the checkout is composed from the OS-resolved Desktop Known Folder plus `Dev\SysAdminSuite`. `C:\SASAL` is a separate sealed Admin Box production/use runtime, not the development checkout.

A convenient clone, remembered path, temporary acquisition, or unrelated current directory is not a substitute.

### 2. Refresh before trusting a repository-owned command

Before the command is selected or handed to an operator, execute the repository freshness contract. The required remote refresh is:

```text
git fetch --all --prune --tags
```

The workflow resolves the actual remote default branch and compares it to the canonical checkout. A clean, owned, healthy canonical default-branch checkout that is strictly behind may converge with `git pull --ff-only`. Dirty, diverged, unhealthy, missing, or separately owned state is preserved and fails closed before the product command.

Fetching alone is not pulling. A working `sas` installation is not proof that the checkout is current.

### 3. Treat network switching as a transaction

Capture the **starting network posture** before changing it. Resolve the operation through `scripts/SasNetworkIntent.psm1`:

- `InternetSync`: Guest / ordinary Internet for repository synchronization;
- `ProtectedNorthwell`: approved Northwell hardwire, `NSLIJHS-WAB`, or authenticated `DomainAuthenticated` VPN;
- `LocalOnly`: leave the network unchanged;
- `CommandSpecific`: the selected command owns any additional network admission.

Use `scripts/Invoke-SasNetworkAwareField.ps1` or the installed network-aware front door. Do not reproduce Wi-Fi/VPN switching logic in operator snippets.

Automatic transition is limited to proven saved WLAN profiles. SysAdminSuite does not guess VPN-client lifecycle or disable protected hardwire to reach Internet. When the wrapper changed WLANs, it restores the recorded starting profile in `finally`; a required restore failure prevents the operation from being reported as successful.

When a VPN or hardwire transition must be manual, the handoff must state both the network required before execution and the return posture required afterward. Where the saved return bookmark permits it, the repository-owned local return command is `%LOCALAPPDATA%\SysAdminSuite\bin\sas-leave.cmd` (installed from `Switch-Back-To-Previous-Network.cmd`).

## Operator-facing rule

An agent should not give a technician a bare `sas ...`, `.cmd`, or PowerShell product snippet and then add canonical relocation, pull-latest, or network correction only after it fails.

When workstation execution is not available to the agent, the first operator paste must be one fail-closed block that owns the prerequisites it can safely automate and delegates network transition/product execution/restoration to the canonical repository front door.

## Validation

The contract is enforced by:

- `harness/validators/validate-operator-command-handoff.py`;
- `Tests/survey/test_operator_command_handoff_contracts.py`;
- `.github/workflows/operator-command-handoff-contracts.yml`;
- `.githooks/pre-commit`;
- `.githooks/pre-push`.

These checks prove repository composition. They cannot prove a particular workstation's path, network, credentials, remote reachability, or physical target behavior; those require field evidence from the existing runtime authorities.
