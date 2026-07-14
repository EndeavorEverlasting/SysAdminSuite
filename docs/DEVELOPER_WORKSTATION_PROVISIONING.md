# Developer Workstation Provisioning

## Purpose

SysAdminSuite owns the operator-workstation orchestration layer for a Windows development workstation. WezTerm is the required terminal host and the preferred user-facing entrypoint. The default execution profile is Windows-native PowerShell inside WezTerm.

WSL is an optional, lower-priority execution profile for tools or workflows that genuinely need a Linux environment. It is not the default and must not be installed, enabled, or selected merely because it is present on the current workstation. tmux belongs only to the optional WSL profile.

This document defines the first contract slice only. It does not install software, authenticate agents, mutate target workstations, or duplicate AgentSwitchboard implementation.

## Product preference

The preferred stack is:

```text
Windows -> WezTerm -> PowerShell 7 -> OpenCode / AGY / Goose
```

The optional compatibility and experimentation stack is:

```text
Windows -> WezTerm -> WSL -> tmux -> OpenCode / AGY / Goose
```

WezTerm and WSL are not equivalent layers: WezTerm is the terminal host, while WSL is one possible execution environment launched by that host. The product preference is therefore expressed by requiring WezTerm and ranking a Windows-native profile ahead of a disabled WSL profile.

## Repository ownership boundary

### SysAdminSuite owns

- Windows prerequisite inventory and future orchestration;
- WezTerm installation posture, configuration templates, launch profiles, and preference order;
- Windows-native shell selection and project workspace composition;
- optional WSL distribution selection only when an enabled profile requires it;
- optional tmux configuration only inside an enabled WSL profile;
- elevation boundaries, rollback, and technician-facing evidence;
- validation that the external AgentSwitchboard contract is available before invocation.

### AgentSwitchboard owns

- coding-agent installation, detection, upgrade, and repair;
- agent-specific PATH and wrapper handling across supported execution profiles;
- authentication-readiness reporting without automatic authentication;
- per-agent smoke tests and normalized agent inventory.

SysAdminSuite must consume AgentSwitchboard through a versioned external contract. It must not copy AgentSwitchboard installers into this repository or silently replace customized agent installations.

## Canonical profile contract

- Schema: `schemas/harness/developer-workstation-profile.schema.json`
- Sanitized sample: `Config/developer-workstation-profile.sample.json`
- Contract test: `Tests/survey/test_developer_workstation_profile_contracts.py`

The sample contract enforces:

- `wezterm` as the required terminal provider;
- `windows-native` as the enabled default profile;
- PowerShell 7 as the preferred native shell;
- `wsl-tmux` as disabled and lower priority;
- explicit profile ordering rather than an inferred fallback;
- install-missing-only behavior;
- preservation of existing user configuration;
- no automatic account authentication;
- no deployment-target contact or mutation;
- no committed runtime evidence, credentials, or machine-local paths.

A future implementation may allow the operator to explicitly enable or select the WSL profile. It must not silently promote WSL to the default when Windows-native agent tooling is healthy.

## Proof ceiling

The contract test can prove schema shape, preference ordering, repository-boundary declarations, sanitized tracked configuration, and validation-runner registration. It cannot prove:

- WezTerm, PowerShell 7, WSL, tmux, or any coding agent is installed;
- OpenCode, AGY, or Goose works natively on the current Windows machine;
- AgentSwitchboard exposes a stable executable command;
- installation, repair, upgrade, authentication readiness, or launch behavior works;
- Windows elevation and rollback behavior;
- end-to-end workstation provisioning.

Those require later bounded implementation and Windows fixture/runtime sprints.

## Next implementation seam

Before adding an executable SysAdminSuite installer, AgentSwitchboard must publish a stable, versioned invocation and result contract that identifies supported execution profiles. The SysAdminSuite adapter should then validate that contract, prefer the enabled Windows-native profile, refuse silent fallback to disabled WSL, invoke AgentSwitchboard without forwarding secrets, and translate normalized PASS/SKIP/FAIL results into a SysAdminSuite evidence summary.
